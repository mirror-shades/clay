const std = @import("std");
const debugPrint = std.debug.print;
const lexer = @import("lexer.zig");
const token = @import("token.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");
const Preprocessor = @import("prepro.zig").Preprocessor;
const Writer = @import("writer.zig");

fn getDisplayText(token_kind: token.TokenKind, token_text: []const u8) []const u8 {
    return switch (token_kind) {
        .TKN_NEWLINE => "\\n",
        .TKN_TYPE_ASSIGN => ":",
        .TKN_VALUE_ASSIGN => "=",
        .TKN_EOF => "EOF",
        else => token_text,
    };
}

pub fn main() !void {
    var debug_lexer = false;
    var debug_parser = false;
    var debug_preprocessor = false;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Get the program name first before skipping
    const program_name = args.next() orelse "para";

    // Process arguments
    var filename: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--debug_lexer")) {
            debug_lexer = true;
        } else if (std.mem.eql(u8, arg, "--debug_parser")) {
            debug_parser = true;
        } else if (std.mem.eql(u8, arg, "--debug_preprocessor")) {
            debug_preprocessor = true;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            debug_lexer = true;
            debug_parser = true;
            debug_preprocessor = true;
        } else if (filename == null) {
            filename = arg;
        }
    }

    // Check if filename was provided
    const file_path = filename orelse {
        std.log.err("Usage: {s} [options] <file>", .{program_name});
        std.log.err("Options:", .{});
        std.log.err("  --debug_lexer        Enable lexer debug output", .{});
        std.log.err("  --debug_parser       Enable parser debug output", .{});
        std.log.err("  --debug_preprocessor Enable preprocessor debug output", .{});
        std.log.err("  --debug              Enable all debug output", .{});
        return;
    };

    if (!std.mem.endsWith(u8, file_path, ".para")) {
        std.log.err("File must have a .para extension", .{});
        return;
    }

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(contents);

    // if build folder doesn't exist, create it
    const build_dir = "build";
    std.fs.cwd().access(build_dir, .{}) catch {
        std.fs.cwd().makeDir(build_dir) catch |e| {
            std.log.err("Error creating build directory: {s}\n", .{@errorName(e)});
            return;
        };
    };

    var para_lexer = try Lexer.init(allocator, contents);
    defer para_lexer.deinit();

    para_lexer.tokenize() catch |e| {
        std.log.err("Error tokenizing file: {s}\n", .{@errorName(e)});
        para_lexer.dumpLexer();
        return;
    };

    if (debug_lexer) {
        debugPrint("Successfully tokenized file: {s}\n", .{file_path});
        para_lexer.dumpLexer();
    }

    var para_parser = Parser.init(allocator, para_lexer.tokens.items);
    defer para_parser.deinit();

    para_parser.parse() catch |e| {
        std.log.err("Error parsing file: {s}\n", .{@errorName(e)});
        para_parser.dumpParser();
        return;
    };

    if (debug_parser) {
        debugPrint("Successfully parsed file: {s}\n", .{file_path});
        para_parser.dumpParser();
    }

    try Writer.writeFlatFile(para_parser.parsed_tokens.items);

    var preprocessor = Preprocessor.init(allocator);
    defer preprocessor.deinit();

    if (debug_preprocessor) {
        debugPrint("preprocesser starting tokens: {s}\n", .{file_path});
    }

    try preprocessor.process(para_parser.parsed_tokens.items);

    // Create a file with the final variable state
    try Writer.writeVariableState(&preprocessor, "output.w.para", allocator);
}

fn printNode(node: *ast.Node, indent: usize) !void {
    // Print indentation
    for (0..indent) |_| {
        debugPrint("  ", .{});
    }

    // Print node info
    debugPrint("{s}: {s}", .{ @tagName(node.type), node.name });
    if (node.is_const) {
        debugPrint(" (const)", .{});
    }
    if (node.value) |value| {
        switch (value) {
            .int => |i| debugPrint(" = {d}", .{i}),
            .float => |f| debugPrint(" = {d}", .{f}),
            .string => |s| debugPrint(" = {s}", .{s}),
            .bool => |b| debugPrint(" = {}", .{b}),
            else => {},
        }
    }
    debugPrint("\n", .{});

    // Print children with increased indentation
    if (node.children) |children| {
        for (children.items) |child| {
            try printNode(child, indent + 1);
        }
    }
}
