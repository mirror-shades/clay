const std = @import("std");
const debugPrint = std.debug.print;
const lexer = @import("lexer.zig");
const token = @import("token.zig");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");

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
    const debug = true;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Get the program name first before skipping
    const program_name = args.next() orelse "para";

    const filename = args.next() orelse {
        std.log.err("Usage: {s} <file>", .{program_name});
        return;
    };

    if (!std.mem.endsWith(u8, filename, ".para")) {
        std.log.err("File must have a .para extension", .{});
        return;
    }

    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(contents);

    var para_lexer = try Lexer.init(allocator, contents);
    defer para_lexer.deinit();

    try para_lexer.tokenize();

    if (debug) {
        debugPrint("Successfully tokenized file: {s}\n", .{filename});
        para_lexer.dumpLexer();
    }

    var para_parser = Parser.init(para_lexer.tokens.items);
    defer para_parser.deinit();

    try para_parser.parse();
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
