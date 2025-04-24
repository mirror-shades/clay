const std = @import("std");
const print = std.debug.print;
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const token = @import("token.zig");
const Lexer = @import("lexer.zig").Lexer;
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

    var para_lexer = Lexer.init(allocator, contents);
    defer para_lexer.deinit();

    try para_lexer.tokenize();

    if (debug) {
        print("Successfully tokenized file: {s}\n", .{filename});
        for (para_lexer.tokens.items) |t| {
            const token_text = contents[t.start..t.end];
            const display_text = getDisplayText(t.kind, token_text);
            print("Token: {s} (kind: {any}, line {d})\n", .{ display_text, t.kind, t.line });
        }
    }

    var para_parser = try parser.Parser.init(allocator, para_lexer.tokens.items, contents, debug);
    defer para_parser.deinit();

    try para_parser.parse();

    // After parsing, print the AST if debug is true
    if (debug) {
        print("\nParsed AST:\n", .{});
        try printNode(para_parser.root, 0);
    }
}

fn printNode(node: *ast.Node, indent: usize) !void {
    // Print indentation
    for (0..indent) |_| {
        print("  ", .{});
    }

    // Print node info
    print("{s}: {s}", .{ @tagName(node.type), node.name });
    if (node.is_const) {
        print(" (const)", .{});
    }
    if (node.value) |value| {
        switch (value) {
            .int => |i| print(" = {d}", .{i}),
            .float => |f| print(" = {d}", .{f}),
            .string => |s| print(" = {s}", .{s}),
            .bool => |b| print(" = {}", .{b}),
            else => {},
        }
    }
    print("\n", .{});

    // Print children with increased indentation
    if (node.children) |children| {
        for (children.items) |child| {
            try printNode(child, indent + 1);
        }
    }
}
