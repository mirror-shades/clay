const std = @import("std");
const token = @import("token.zig");
const reporting = @import("reporting.zig");

const printError = std.debug.print;

pub const Lexer = struct {
    input: []const u8,
    pos: usize,
    line: usize,
    column: usize,
    token_count: usize,
    tokens: std.ArrayList(token.Token),
    lines: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) !Lexer {
        var lexer = Lexer{
            .input = input,
            .pos = 0,
            .line = 1,
            .column = 1,
            .token_count = 0,
            .tokens = std.ArrayList(token.Token).init(allocator),
            .lines = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
        try lexer.readLines();
        return lexer;
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit();
        self.lines.deinit();
    }

    fn readLines(self: *Lexer) !void {
        var start: usize = 0;
        var i: usize = 0;
        while (i < self.input.len) : (i += 1) {
            if (self.input[i] == '\n') {
                try self.lines.append(self.input[start..i]);
                start = i + 1;
            }
            if (self.input[i] == '\r') {
                i += 1;
            }
        }
        // Add the last line if there's any content after the last newline
        if (start < self.input.len) {
            try self.lines.append(self.input[start..]);
        }
    }

    fn peek(self: *Lexer) ?u8 {
        return if (self.pos < self.input.len) self.input[self.pos] else null;
    }

    fn peekNext(self: *Lexer) ?u8 {
        return if (self.pos + 1 < self.input.len) self.input[self.pos + 1] else null;
    }

    fn advance(self: *Lexer) void {
        if (self.pos < self.input.len) {
            const current = self.input[self.pos];
            self.pos += 1;
            if (current == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.peek()) |c| {
            switch (c) {
                ' ', '\t' => {
                    self.advance();
                },
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
        self.advance();
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
        if (last_token.token_type == .TKN_NEWLINE) {
            return;
        }

        const current_column = self.column;
        try self.tokens.append(.{
            .literal = "\\n",
            .token_type = .TKN_NEWLINE,
            .value_type = .nothing,
            .line_number = self.line,
            .token_number = current_column,
        });
        self.token_count += 1;
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

            if (c == '?') {
                const current_column = self.column;
                self.advance();
                try self.tokens.append(.{
                    .literal = "?",
                    .token_type = .TKN_INSPECT,
                    .value_type = .nothing,
                    .line_number = self.line,
                    .token_number = current_column,
                });
                self.token_count += 1;
                continue;
            }

            if (c == '/') {
                const current_column = self.column;
                self.advance();
                if (self.peek() == '*') {
                    self.skipMultiline();
                } else if (self.peek() == '/') {
                    self.skipLine();
                } else {
                    try self.tokens.append(.{
                        .literal = "/",
                        .token_type = .TKN_SLASH,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                }
                continue;
            }

            if (c == 'i') {
                const current_column = self.column;
                const word = try self.readWord();
                if (std.mem.eql(u8, word, "int")) {
                    try self.tokens.append(.{
                        .literal = "int",
                        .token_type = .TKN_TYPE,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                }
                continue;
            }

            if (c == 'f') {
                const current_column = self.column;
                const word = try self.readWord();
                if (std.mem.eql(u8, word, "float")) {
                    try self.tokens.append(.{
                        .literal = "float",
                        .token_type = .TKN_TYPE,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                }
                continue;
            }

            if (c == 's') {
                const current_column = self.column;
                const word = try self.readWord();
                if (std.mem.eql(u8, word, "string")) {
                    try self.tokens.append(.{
                        .literal = "string",
                        .token_type = .TKN_TYPE,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                }
                continue;
            }

            if (c == 'b') {
                const current_column = self.column;
                const word = try self.readWord();
                if (std.mem.eql(u8, word, "bool")) {
                    try self.tokens.append(.{
                        .literal = "bool",
                        .token_type = .TKN_TYPE,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                }
                continue;
            }

            // Process actual tokens
            switch (c) {
                ':' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = ":",
                        .token_type = .TKN_TYPE_ASSIGN,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                '=' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = "=",
                        .token_type = .TKN_VALUE_ASSIGN,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                '-' => {
                    const current_column = self.column;
                    if (self.pos + 1 < self.input.len and self.input[self.pos + 1] == '>') {
                        try self.tokens.append(.{
                            .literal = "->",
                            .token_type = .TKN_ARROW,
                            .value_type = .nothing,
                            .line_number = self.line,
                            .token_number = current_column,
                        });
                        self.token_count += 1;
                        self.advance();
                        self.advance();
                    } else {
                        try self.tokens.append(.{
                            .literal = "-",
                            .token_type = .TKN_MINUS,
                            .value_type = .nothing,
                            .line_number = self.line,
                            .token_number = current_column,
                        });
                        self.token_count += 1;
                        self.advance();
                    }
                },
                '+' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = "+",
                        .token_type = .TKN_PLUS,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                '^' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = "^",
                        .token_type = .TKN_POWER,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                '%' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = "%",
                        .token_type = .TKN_PERCENT,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                '*' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = "*",
                        .token_type = .TKN_STAR,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                '(' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = "(",
                        .token_type = .TKN_LPAREN,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                ')' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = ")",
                        .token_type = .TKN_RPAREN,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                '{' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = "{",
                        .token_type = .TKN_LBRACE,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                '}' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = "}",
                        .token_type = .TKN_RBRACE,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                '[' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = "[",
                        .token_type = .TKN_LBRACKET,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                ']' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = "]",
                        .token_type = .TKN_RBRACKET,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },
                ',' => {
                    const current_column = self.column;
                    try self.tokens.append(.{
                        .literal = ",",
                        .token_type = .TKN_COMMA,
                        .value_type = .nothing,
                        .line_number = self.line,
                        .token_number = current_column,
                    });
                    self.token_count += 1;
                    self.advance();
                },

                '"' => try self.readString(),
                'a'...'z', 'A'...'Z', '_' => {
                    const current_column = self.column;
                    const word = try self.readWord();
                    try self.makeWordToken(word, current_column);
                },
                '0'...'9' => try self.readNumber(),
                else => {
                    const line_content = self.lines.items[self.line - 1];
                    const column = self.column;
                    reporting.underline(line_content, column - 1, 1);
                    printError("Unexpected character: {c}\n", .{c});
                    printError("Line: {d} Column: {d}\n", .{ self.line, self.column });
                    return error.UnexpectedCharacter;
                },
            }
        }

        // Add final EOF token
        try self.tokens.append(.{
            .literal = "EOF",
            .token_type = .TKN_EOF,
            .value_type = .nothing,
            .line_number = self.line,
            .token_number = self.column,
        });
        self.token_count += 1;
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

    fn makeWordToken(self: *Lexer, word: []const u8, column: usize) !void {
        if (std.meta.stringToEnum(token.ValueType, word)) |value_type| {
            try self.tokens.append(.{
                .literal = word,
                .token_type = .TKN_VALUE,
                .value_type = value_type,
                .line_number = self.line,
                .token_number = column,
            });
        } else {
            try self.tokens.append(.{
                .literal = word,
                .token_type = .TKN_IDENTIFIER,
                .value_type = .nothing,
                .line_number = self.line,
                .token_number = column,
            });
        }
        self.token_count += 1;
    }

    fn isKeyword(self: *Lexer) bool {
        return token.keywords.get(self.input[self.pos..]) != null;
    }

    fn readString(self: *Lexer) !void {
        const start = self.pos;
        const current_column = self.column;
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

        // Check if we hit EOF before finding closing quote
        if (self.peek() == null) {
            const line_content = self.lines.items[self.line - 1];
            const column = current_column - 1;
            reporting.underline(line_content, column, self.pos - start);
            printError("Unterminated string at line {d}, column {d}\n", .{ self.line, current_column });
            return error.UnterminatedString;
        }

        try self.tokens.append(.{
            .literal = self.input[start..self.pos],
            .token_type = .TKN_VALUE,
            .value_type = .string,
            .line_number = self.line,
            .token_number = current_column,
        });
        self.token_count += 1;
    }

    fn readNumber(self: *Lexer) !void {
        const start = self.pos;
        const current_column = self.column;
        var has_dot = false;
        var is_valid = true;

        while (self.peek()) |c| {
            switch (c) {
                '0'...'9' => self.advance(),
                '.' => {
                    if (has_dot) {
                        is_valid = false;
                        break;
                    }
                    has_dot = true;
                    self.advance();
                    // Ensure there's at least one digit after the decimal point
                    if (self.peek()) |next| {
                        if (next < '0' or next > '9') {
                            is_valid = false;
                            break;
                        }
                    } else {
                        is_valid = false;
                        break;
                    }
                },
                else => break,
            }
        }

        if (!is_valid) {
            printError("Invalid number format at line {d}, column {d}\n", .{ self.line, current_column });
            return error.InvalidNumberFormat;
        }

        try self.tokens.append(.{
            .literal = self.input[start..self.pos],
            .token_type = .TKN_VALUE,
            .value_type = if (has_dot) .float else .int,
            .line_number = self.line,
            .token_number = current_column,
        });
        self.token_count += 1;
    }

    pub fn dumpLexer(self: *Lexer) void {
        for (self.tokens.items) |t| {
            if (t.token_type == .TKN_NEWLINE or t.token_type == .TKN_EOF) continue;
            printError("{s} (kind: {s}, line {d}, token {d})\n", .{
                t.literal,
                t.token_type.toString(),
                t.line_number,
                t.token_number,
            });
        }
    }
};
