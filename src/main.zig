const std = @import("std");
const print = std.debug.print;
//const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const token = @import("token.zig");
const Lexer = @import("lexer.zig").Lexer;

fn getDisplayText(token_kind: token.TokenKind, token_text: []const u8) []const u8 {
    return switch (token_kind) {
        .TKN_NEWLINE => "\\n",
        .TKN_TYPE_ASSIGN => "::",
        .TKN_VALUE_ASSIGN => "is",
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
    const program_name = args.next() orelse "clay";

    const filename = args.next() orelse {
        std.log.err("Usage: {s} <file>", .{program_name});
        return;
    };

    if (!std.mem.endsWith(u8, filename, ".clay")) {
        std.log.err("File must have a .clay extension", .{});
        return;
    }

    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(contents);

    var clay_lexer = Lexer.init(allocator, contents);
    defer clay_lexer.deinit();

    try clay_lexer.tokenize();

    if (debug) {
        print("Successfully tokenized file: {s}\n", .{filename});
        for (clay_lexer.tokens.items) |t| {
            const token_text = contents[t.start..t.end];
            const display_text = getDisplayText(t.kind, token_text);
            print("Token: {s} (kind: {any}, line {d})\n", .{ display_text, t.kind, t.line });
        }
    }
    // var clay_parser = parser.Parser.init(allocator);
    // defer clay_parser.deinit();

    // try clay_parser.parse(contents);
}
