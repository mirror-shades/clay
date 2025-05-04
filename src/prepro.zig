const std = @import("std");
const ParsedToken = @import("parser.zig").ParsedToken;
const Token = @import("token.zig").Token;

pub fn preprocess(tokens: []ParsedToken) !void {
    for (tokens) |token| {
        switch (token.token_type) {
            .TKN_NEWLINE => {
                std.debug.print("\n", .{});
            },
            .TKN_INSPECT => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_GROUP => {
                std.debug.print("{s} -> ", .{token.literal});
            },
            .TKN_TYPE => {
                std.debug.print(": {s} ", .{token.literal});
            },
            .TKN_VALUE_ASSIGN => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_VALUE => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_IDENTIFIER => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_PLUS => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_MINUS => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_STAR => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_SLASH => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_PERCENT => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_POWER => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_LPAREN => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_RPAREN => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_LBRACKET => {
                std.debug.print("{s} ", .{token.literal});
            },
            .TKN_RBRACKET => {
                std.debug.print("{s} ", .{token.literal});
            },
            else => continue,
        }
    }
}
