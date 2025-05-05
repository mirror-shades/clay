const std = @import("std");
const Token = @import("token.zig").Token;
const TokenKind = @import("token.zig").TokenKind;
const ValueType = @import("token.zig").ValueType;
const Value = @import("token.zig").Value;
const printError = std.debug.print;
const printInspect = std.debug.print;

const Group = struct {
    name: []const u8,
    type: ?[]const u8,
};

pub const ParsedToken = struct {
    token_type: TokenKind,
    value_type: ValueType,
    value: Value,
    expression: ?[]Token,
    literal: []const u8,
    line_number: usize,
    token_number: usize,

    pub fn deinit(self: *ParsedToken, allocator: std.mem.Allocator) void {
        if (self.expression) |expr| {
            allocator.free(expr);
            self.expression = null;
        }
    }
};

pub const Parser = struct {
    tokens: []Token,
    groups: std.ArrayList(Group),
    parsed_tokens: std.ArrayList(ParsedToken),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, tokens: []Token) Parser {
        return Parser{
            .tokens = tokens,
            .groups = std.ArrayList(Group).init(allocator),
            .parsed_tokens = std.ArrayList(ParsedToken).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Parser) void {
        // Clean up any allocated memory in parsed tokens
        for (self.parsed_tokens.items) |*token| {
            token.deinit(self.allocator);
        }

        self.groups.deinit();
        self.parsed_tokens.deinit();
        self.tokens = undefined;
    }

    pub fn parse(self: *Parser) !void {
        if (self.tokens.len == 0) {
            return error.NoTokens;
        }

        var current_token = self.tokens[0];
        var current_index: usize = 0;
        var has_equals: bool = false;

        while (current_index < self.tokens.len) {
            current_token = self.tokens[current_index];
            current_index += 1;

            switch (current_token.token_type) {
                .TKN_IDENTIFIER => {
                    if (self.tokens[current_index].token_type == .TKN_ARROW) {
                        if (self.tokens[current_index + 1].token_type == .TKN_LBRACE) {
                            continue;
                        } else if (self.tokens[current_index + 1].token_type == .TKN_TYPE_ASSIGN) {
                            continue;
                        }
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_GROUP, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                        continue;
                    }
                    if (self.groups.items.len > 0) {
                        for (self.groups.items) |group| {
                            try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_GROUP, .literal = group.name, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                        }
                    }
                    if (self.tokens[current_index].token_type == .TKN_ARROW) {
                        if (self.tokens[current_index + 1].token_type == .TKN_LBRACE) {
                            continue;
                        }
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_GROUP, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                        continue;
                    }
                    if (self.tokens[current_index].token_type == .TKN_TYPE_ASSIGN or self.tokens[current_index].token_type == .TKN_VALUE_ASSIGN or self.tokens[current_index].token_type == .TKN_NEWLINE or self.tokens[current_index].token_type == .TKN_INSPECT) {
                        if (has_equals) {
                            try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_LOOKUP, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                        } else {
                            try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_IDENTIFIER, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                        }
                        if (self.tokens[current_index].token_type == .TKN_TYPE_ASSIGN) {
                            continue;
                        }
                        if (self.groups.items.len > 0) {
                            if (self.groups.items[self.groups.items.len - 1].type) |t| {
                                try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_TYPE, .literal = t, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                            }
                        }
                        continue;
                    }
                },
                .TKN_RBRACKET => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_RBRACKET, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_LBRACKET => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_LBRACKET, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_LBRACE => {
                    var type_to_add: ?[]const u8 = null;
                    var offset: u8 = 3; // default offset 3 for  group -> {
                    if (self.tokens[current_index - 3].token_type == .TKN_TYPE_ASSIGN) {
                        type_to_add = self.tokens[current_index - 2].literal;
                        offset = 5; // offset 5 for group -> : type {
                    }
                    const token_to_add = self.tokens[current_index - offset];
                    try self.groups.append(Group{ .name = token_to_add.literal, .type = type_to_add });
                    continue;
                },
                .TKN_RBRACE => {
                    _ = self.groups.pop();
                    continue;
                },
                .TKN_VALUE_ASSIGN => {
                    if (has_equals) {
                        return error.MultipleAssignments;
                    }
                    has_equals = true;
                    const assign_line: std.ArrayList(Token) = grabLine(self, current_token);
                    defer assign_line.deinit();
                    if (assign_line.items.len > 1) {
                        std.debug.print("this is an expression\n", .{});
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_VALUE_ASSIGN, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = assign_line.items[0].line_number, .token_number = current_token.token_number });

                        // Clone the tokens to ensure they remain valid
                        var expression_tokens = try self.allocator.alloc(Token, assign_line.items.len);
                        for (assign_line.items, 0..) |token, i| {
                            expression_tokens[i] = token;
                        }

                        // Only add expression tokens if there are actually tokens to process
                        if (expression_tokens.len > 0) {
                            try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_EXPRESSION, .literal = "Expression", .value_type = .nothing, .value = .{ .nothing = {} }, .expression = expression_tokens, .line_number = assign_line.items[0].line_number, .token_number = current_token.token_number });
                        } else {
                            // If no expression tokens, don't add an expression token and free the allocated memory
                            self.allocator.free(expression_tokens);
                            std.debug.print("Warning: Empty expression detected\n", .{});
                        }
                    } else {
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_VALUE_ASSIGN, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = assign_line.items[0].line_number, .token_number = current_token.token_number });
                    }
                    continue;
                },
                .TKN_TYPE_ASSIGN => {
                    if (self.tokens[current_index - 2].token_type == .TKN_ARROW) {
                        // this is a group -> : typing which would have been handled in the group -> identifier parsing
                        continue;
                    }
                    continue;
                },
                .TKN_NEWLINE => {
                    has_equals = false;
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_NEWLINE, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_TYPE => {
                    if (self.tokens[current_index - 3].token_type == .TKN_ARROW) {
                        // this is a group -> : typing which would have been handled in the group -> identifier parsing
                        continue;
                    }
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_TYPE, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_VALUE => {
                    // Parse the value from the literal based on the token's value type
                    const parsed_value = parseValueFromLiteral(current_token.literal, current_token.value_type);
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_VALUE, .literal = current_token.literal, .expression = null, .value_type = current_token.value_type, .value = parsed_value, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_INSPECT => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_INSPECT, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_ARROW => {
                    continue;
                },
                .TKN_PLUS => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_PLUS, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_MINUS => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_MINUS, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_STAR => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_STAR, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_SLASH => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_SLASH, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_PERCENT => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_PERCENT, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_POWER => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_POWER, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_LPAREN => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_LPAREN, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_RPAREN => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_RPAREN, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number });
                    continue;
                },
                .TKN_EOF => {
                    break;
                },
                else => unreachable,
            }
        }
    }

    pub fn dumpParser(self: *Parser) void {
        for (self.parsed_tokens.items) |token| {
            std.debug.print("{s} ", .{token.literal});
            std.debug.print("({s}) ", .{@tagName(token.token_type)});
            std.debug.print("({s}) ", .{@tagName(token.value_type)});
            std.debug.print("\n", .{});
        }
    }
};

fn grabLine(self: *Parser, current_token: Token) std.ArrayList(Token) {
    var line_array = std.ArrayList(Token).init(self.allocator);
    var found_assign: bool = false;
    var last_token_type: ?TokenKind = null;

    for (self.tokens) |token| {
        if (token.line_number == current_token.line_number) {
            if (found_assign) {
                if (token.token_type == .TKN_NEWLINE) {
                    break;
                }

                // Add implicit multiplication for juxtaposition of value and parentheses
                if (last_token_type != null) {
                    const is_value = last_token_type.? == .TKN_VALUE;
                    const is_rparen = last_token_type.? == .TKN_RPAREN;
                    const is_lparen = token.token_type == .TKN_LPAREN;
                    const is_value_next = token.token_type == .TKN_VALUE;

                    if ((is_value and is_lparen) or (is_rparen and is_value_next)) {
                        const implicit_mul = Token{
                            .token_type = .TKN_STAR,
                            .literal = "*",
                            .line_number = token.line_number,
                            .token_number = token.token_number,
                            .value_type = .nothing,
                        };
                        line_array.append(implicit_mul) catch |err| {
                            std.debug.print("Error appending implicit multiplication: {s}\n", .{@errorName(err)});
                        };
                    }
                }

                line_array.append(token) catch |err| {
                    std.debug.print("Error appending to line_array: {s}\n", .{@errorName(err)});
                    break;
                };
                last_token_type = token.token_type;
            }
            if (token.token_type == .TKN_VALUE_ASSIGN) {
                found_assign = true;
            }
        }
    }
    return line_array;
}

fn parseIntFromLiteral(literal: []const u8) i32 {
    return std.fmt.parseInt(i32, literal, 10) catch 0;
}

fn parseFloatFromLiteral(literal: []const u8) f64 {
    return std.fmt.parseFloat(f64, literal) catch 0;
}

fn parseStringFromLiteral(literal: []const u8) []const u8 {
    if (literal.len >= 2 and literal[0] == '"' and literal[literal.len - 1] == '"') {
        return literal[1 .. literal.len - 1];
    }
    return literal;
}

fn parseBoolFromLiteral(literal: []const u8) bool {
    return std.mem.eql(u8, literal, "true") or std.mem.eql(u8, literal, "TRUE");
}

fn parseValueFromLiteral(literal: []const u8, value_type: ValueType) Value {
    return switch (value_type) {
        .int => .{ .int = parseIntFromLiteral(literal) },
        .float => .{ .float = parseFloatFromLiteral(literal) },
        .string => .{ .string = parseStringFromLiteral(literal) },
        .bool => .{ .bool = parseBoolFromLiteral(literal) },
        .nothing => .{ .nothing = {} },
    };
}
