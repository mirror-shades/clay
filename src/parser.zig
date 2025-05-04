const std = @import("std");
const Token = @import("token.zig").Token;
const TokenKind = @import("token.zig").TokenKind;
const ValueType = @import("token.zig").ValueType;
const printError = std.debug.print;
const printInspect = std.debug.print;

pub const Parser = struct {
    tokens: []Token,

    pub fn init(tokens: []Token) Parser {
        return Parser{ .tokens = tokens };
    }

    pub fn deinit(self: *Parser) void {
        self.tokens = undefined;
    }

    pub fn parse(self: *Parser) !void {
        if (self.tokens.len == 0) {
            return error.NoTokens;
        }

        var current_token = self.tokens[0];
        var current_index: usize = 0;

        while (current_index < self.tokens.len) {
            current_token = self.tokens[current_index];
            current_index += 1;

            switch (current_token.token_type) {
                .TKN_INSPECT => {
                    const value = self.tokens[current_index - 2];

                    const type_str = if (value.value_type == .nothing)
                        value.token_type.toString()
                    else
                        value.value_type.toString();

                    printInspect("[{d}:{d}] {s} = {s}\n", .{ value.line_number, value.token_number, type_str, value.literal });
                },
                else => continue,
            }
        }
    }
};
