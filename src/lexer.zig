const std = @import("std");
const token = @import("token.zig");

pub const Lexer = struct {
    input: []const u8,
    pos: usize,
    line: usize,
    tokens: std.ArrayList(token.Token),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Lexer {
        return .{
            .input = input,
            .pos = 0,
            .line = 1,
            .tokens = std.ArrayList(token.Token).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit();
    }

    fn peek(self: *Lexer) ?u8 {
        return if (self.pos < self.input.len) self.input[self.pos] else null;
    }

    fn peekNext(self: *Lexer) ?u8 {
        return if (self.pos + 1 < self.input.len) self.input[self.pos + 1] else null;
    }

    fn advance(self: *Lexer) void {
        if (self.pos < self.input.len) {
            self.pos += 1;
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.peek()) |c| {
            switch (c) {
                ' ', '\t' => self.advance(),
                else => break,
            }
        }
    }

    fn skipMultiline(self: *Lexer) void {
        while (self.peek()) |c| {
            if (c == '*' and self.peekNext() == '/') {
                self.advance();
                self.advance();
                break;
            }
            self.advance();
        }
    }

    fn skipLine(self: *Lexer) void {
        while (self.peek()) |c| {
            if (c == '\n') {
                self.advance();
                break;
            }
            self.advance();
        }
    }

    fn handleNewline(self: *Lexer) !void {
        // if there are no tokens, don't add a newline
        if (self.tokens.items.len == 0) {
            self.advance();
            return;
        }

        //check the last token to see if it is a newline
        const last_token = self.tokens.items[self.tokens.items.len - 1];
        if (last_token.kind == .TKN_NEWLINE) {
            return;
        }

        try self.tokens.append(.{
            .kind = .TKN_NEWLINE,
            .start = self.pos,
            .end = self.pos + 1,
            .line = self.line,
        });
    }

    pub fn tokenize(self: *Lexer) !void {
        while (self.peek()) |c| {

            // Handle line endings and comments
            if (c == '\r') {
                try self.handleNewline();
                self.advance();
                if (self.peek() == '\n') {
                    self.advance();
                }
                continue;
            } else if (c == '\n') {
                try self.handleNewline();
                self.advance();
                if (self.peek() == '\r') {
                    self.advance();
                }
                continue;
            }

            // Skip whitespace between tokens
            if (c == ' ' or c == '\t') {
                self.skipWhitespace();
                continue;
            }

            if (c == '/') {
                self.advance();
                if (self.peek() == '*') {
                    self.skipMultiline();
                    self.advance();
                } else if (self.peek() == '/') {
                    self.skipLine();
                    self.advance();
                } else {
                    try self.tokens.append(.{
                        .kind = .TKN_SLASH,
                        .start = self.pos,
                        .end = self.pos + 1,
                        .line = self.line,
                    });
                }
                self.advance();
                continue;
            }

            // Process actual tokens
            switch (c) {
                ':' => {
                    try self.tokens.append(.{
                        .kind = .TKN_TYPE_ASSIGN,
                        .start = self.pos,
                        .end = self.pos + 1,
                        .line = self.line,
                    });
                    self.advance();
                },
                '=' => {
                    try self.tokens.append(.{
                        .kind = .TKN_VALUE_ASSIGN,
                        .start = self.pos,
                        .end = self.pos + 1,
                        .line = self.line,
                    });
                    self.advance();
                },
                '-' => {
                    if (self.pos + 1 < self.input.len and self.input[self.pos + 1] == '>') {
                        try self.tokens.append(.{
                            .kind = .TKN_ARROW,
                            .start = self.pos,
                            .end = self.pos + 2,
                            .line = self.line,
                        });
                        self.advance();
                        self.advance();
                    }
                },
                '(' => {
                    try self.tokens.append(.{
                        .kind = .TKN_LPAREN,
                        .start = self.pos,
                        .end = self.pos + 1,
                        .line = self.line,
                    });
                    self.advance();
                },
                ')' => {
                    try self.tokens.append(.{
                        .kind = .TKN_RPAREN,
                        .start = self.pos,
                        .end = self.pos + 1,
                        .line = self.line,
                    });
                    self.advance();
                },
                '{' => {
                    try self.tokens.append(.{
                        .kind = .TKN_LBRACE,
                        .start = self.pos,
                        .end = self.pos + 1,
                        .line = self.line,
                    });
                    self.advance();
                },
                '}' => {
                    try self.tokens.append(.{
                        .kind = .TKN_RBRACE,
                        .start = self.pos,
                        .end = self.pos + 1,
                        .line = self.line,
                    });
                    self.advance();
                },
                '[' => {
                    try self.tokens.append(.{
                        .kind = .TKN_LBRACKET,
                        .start = self.pos,
                        .end = self.pos + 1,
                        .line = self.line,
                    });
                    self.advance();
                },
                ']' => {
                    try self.tokens.append(.{
                        .kind = .TKN_RBRACKET,
                        .start = self.pos,
                        .end = self.pos + 1,
                        .line = self.line,
                    });
                    self.advance();
                },
                ',' => {
                    try self.tokens.append(.{
                        .kind = .TKN_COMMA,
                        .start = self.pos,
                        .end = self.pos + 1,
                        .line = self.line,
                    });
                    self.advance();
                },
                '"' => try self.readString(),
                'a'...'z', 'A'...'Z', '_' => {
                    const word = try self.readWord();
                    try self.makeWordToken(word);
                },
                '0'...'9' => try self.readNumber(),
                else => {
                    return error.UnexpectedCharacter;
                },
            }
        }

        // Add final EOF token
        try self.tokens.append(.{
            .kind = .TKN_EOF,
            .start = self.pos,
            .end = self.pos,
            .line = self.line,
        });
    }

    fn readWord(self: *Lexer) ![]const u8 {
        const start = self.pos;
        while (self.peek()) |c| {
            switch (c) {
                'a'...'z', 'A'...'Z', '0'...'9', '_' => self.advance(),
                else => break,
            }
        }
        return self.input[start..self.pos];
    }

    fn makeWordToken(self: *Lexer, word: []const u8) !void {
        if (token.keywords.get(word)) |keyword_type| {
            try self.tokens.append(.{
                .kind = keyword_type,
                .start = self.pos - word.len,
                .end = self.pos,
                .line = self.line,
            });
        } else {
            try self.tokens.append(.{
                .kind = .TKN_IDENTIFIER,
                .start = self.pos - word.len,
                .end = self.pos,
                .line = self.line,
            });
        }
    }

    fn isKeyword(self: *Lexer) bool {
        return token.keywords.get(self.input[self.pos..]) != null;
    }

    fn readString(self: *Lexer) !void {
        const start = self.pos;
        self.advance(); // skip opening quote
        while (self.peek()) |c| {
            if (c == '"') {
                self.advance();
                break;
            }
            if (c == '\\') {
                self.advance();
                if (self.peek()) |_| self.advance();
            } else {
                self.advance();
            }
        }
        try self.tokens.append(.{
            .kind = .TKN_VALUE_STRING,
            .start = start,
            .end = self.pos,
            .line = self.line,
        });
    }

    fn readNumber(self: *Lexer) !void {
        const start = self.pos;
        var has_dot = false;
        while (self.peek()) |c| {
            switch (c) {
                '0'...'9' => self.advance(),
                '.' => {
                    if (has_dot) break;
                    has_dot = true;
                    self.advance();
                },
                else => break,
            }
        }
        try self.tokens.append(.{
            .kind = if (has_dot) .TKN_VALUE_FLOAT else .TKN_VALUE_INT,
            .start = start,
            .end = self.pos,
            .line = self.line,
        });
    }
};
