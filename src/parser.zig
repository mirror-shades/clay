const std = @import("std");
const Token = @import("token.zig").Token;
const TokenKind = @import("token.zig").TokenKind;
const ValueType = @import("token.zig").ValueType;
const Value = @import("token.zig").Value;
const printError = std.debug.print;
const printDebug = std.debug.print;
const printTemp = std.debug.print;

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
    temp: bool,
    mutable: bool,

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
        var make_temp: bool = false;
        var make_mutable: bool = false;

        while (current_index < self.tokens.len) {
            current_token = self.tokens[current_index];
            current_index += 1;

            switch (current_token.token_type) {
                .TKN_IDENTIFIER => {
                    if (self.tokens[current_index].token_type == .TKN_IDENTIFIER) {
                        printError("Error: Double identifier: {s} and {s}\n", .{ current_token.literal, self.tokens[current_index].literal });
                        return error.DoubleIdentifier;
                    }
                    if (self.tokens[current_index].token_type == .TKN_ARROW) {
                        if (self.tokens[current_index + 1].token_type == .TKN_LBRACE) {
                            continue;
                        } else if (self.tokens[current_index + 1].token_type == .TKN_TYPE_ASSIGN) {
                            continue;
                        }
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_GROUP, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                        continue;
                    }
                    if (self.groups.items.len > 0) {
                        for (self.groups.items) |group| {
                            try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_GROUP, .literal = group.name, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                        }
                    }
                    if (self.tokens[current_index].token_type == .TKN_ARROW) {
                        if (self.tokens[current_index + 1].token_type == .TKN_LBRACE) {
                            continue;
                        }
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_GROUP, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                        continue;
                    }
                    if (self.tokens[current_index].token_type == .TKN_TYPE_ASSIGN or self.tokens[current_index].token_type == .TKN_VALUE_ASSIGN or self.tokens[current_index].token_type == .TKN_NEWLINE or self.tokens[current_index].token_type == .TKN_INSPECT or self.tokens[current_index].token_type == .TKN_MUTA or self.tokens[current_index].token_type == .TKN_TEMP) {
                        if (has_equals) {
                            try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_LOOKUP, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = make_temp, .mutable = make_mutable });
                        } else {
                            try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_IDENTIFIER, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = make_temp, .mutable = make_mutable });
                        }
                        if (self.tokens[current_index].token_type == .TKN_TYPE_ASSIGN) {
                            continue;
                        }
                        if (self.groups.items.len > 0) {
                            if (self.groups.items[self.groups.items.len - 1].type) |t| {
                                try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_TYPE, .literal = t, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = make_temp, .mutable = make_mutable });
                            }
                        }
                        continue;
                    }
                },
                .TKN_RBRACKET => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_RBRACKET, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_LBRACKET => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_LBRACKET, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
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
                    const assign_line: std.ArrayList(Token) = grabLine(self, current_token) catch |err| {
                        printError("Error grabbing line: {s}\n", .{@errorName(err)});
                        return error.ErrorGrabbingLine;
                    };
                    defer assign_line.deinit();
                    const if_expression = ifExpression(assign_line.items);
                    if (if_expression) {
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_VALUE_ASSIGN, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = assign_line.items[0].line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });

                        // Clone the tokens to ensure they remain valid
                        var expression_tokens = try self.allocator.alloc(Token, assign_line.items.len);
                        for (assign_line.items, 0..) |token, i| {
                            expression_tokens[i] = token;
                        }

                        // Only add expression tokens if there are actually tokens to process
                        if (expression_tokens.len > 0) {
                            try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_EXPRESSION, .literal = "Expression", .value_type = .nothing, .value = .{ .nothing = {} }, .expression = expression_tokens, .line_number = assign_line.items[0].line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                        } else {
                            // If no expression tokens, don't add an expression token and free the allocated memory
                            self.allocator.free(expression_tokens);
                            printError("Warning: Empty expression detected\n", .{});
                            return error.EmptyExpression;
                        }
                    } else {
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_VALUE_ASSIGN, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = assign_line.items[0].line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    }
                    continue;
                },
                .TKN_TYPE_ASSIGN => {
                    if (self.tokens[current_index - 2].token_type == .TKN_ARROW) {
                        // this is a group -> : typing which would have been handled in the group -> identifier parsing
                        continue;
                    }

                    // Look back up to 2 positions for temp or muta tokens
                    var prev1: ?Token = null;
                    var prev2: ?Token = null;

                    if (current_index > 2) {
                        prev1 = self.tokens[current_index - 2];
                    }
                    if (current_index > 3) {
                        prev2 = self.tokens[current_index - 3];
                    }

                    // First check if we have temp or muta at position -2
                    if (prev1) |token| {
                        if (token.token_type == .TKN_TEMP) {
                            make_temp = true;
                        } else if (token.token_type == .TKN_MUTA) {
                            make_mutable = true;
                        }
                    }

                    // Then check position -3, but don't override if already set
                    if (prev2) |token| {
                        if (token.token_type == .TKN_TEMP and !make_temp) {
                            make_temp = true;
                        } else if (token.token_type == .TKN_MUTA and !make_mutable) {
                            make_mutable = true;
                        }
                    }

                    continue;
                },
                .TKN_NEWLINE => {
                    has_equals = false;
                    make_temp = false;
                    make_mutable = false;
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_NEWLINE, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_TYPE => {
                    if (self.tokens[current_index - 3].token_type == .TKN_ARROW) {
                        // this is a group -> : typing which would have been handled in the group -> identifier parsing
                        continue;
                    }
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_TYPE, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_VALUE => {
                    // Parse the value from the literal based on the token's value type
                    const parsed_value = parseValueFromLiteral(current_token.literal, current_token.value_type);
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_VALUE, .literal = current_token.literal, .expression = null, .value_type = current_token.value_type, .value = parsed_value, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_INSPECT => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_INSPECT, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_ARROW => {
                    continue;
                },
                .TKN_PLUS => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_PLUS, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_MINUS => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_MINUS, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_STAR => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_STAR, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_SLASH => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_SLASH, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_PERCENT => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_PERCENT, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_POWER => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_POWER, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_LPAREN => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_LPAREN, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_RPAREN => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_RPAREN, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = false });
                    continue;
                },
                .TKN_MUTA => {
                    make_mutable = true;
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_MUTA, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = false, .mutable = true });
                    continue;
                },
                .TKN_TEMP => {
                    make_temp = true;
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_TEMP, .literal = current_token.literal, .expression = null, .value_type = .nothing, .value = .{ .nothing = {} }, .line_number = current_token.line_number, .token_number = current_token.token_number, .temp = true, .mutable = false });
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
            printDebug("{s} ", .{token.literal});
            printDebug("({s}) ", .{@tagName(token.token_type)});
            printDebug("({s}) ", .{@tagName(token.value_type)});
            printDebug("\n", .{});
        }
    }
};

fn ifExpression(tokens: []Token) bool {
    for (tokens) |token| {
        if (token.token_type == .TKN_PLUS or token.token_type == .TKN_MINUS or token.token_type == .TKN_STAR or token.token_type == .TKN_SLASH or token.token_type == .TKN_PERCENT or token.token_type == .TKN_POWER or token.token_type == .TKN_LPAREN or token.token_type == .TKN_RPAREN) {
            return true;
        }
    }
    return false;
}

fn grabLine(self: *Parser, current_token: Token) !std.ArrayList(Token) {
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
                            printError("Error appending implicit multiplication: {s}\n", .{@errorName(err)});
                            return error.ErrorAppendingImplicitMultiplication;
                        };
                    }
                }

                line_array.append(token) catch |err| {
                    printError("Error appending to line_array: {s}\n", .{@errorName(err)});
                    return error.ErrorAppendingToLineArray;
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

// Helper function to check if a declaration is mutable
fn isMutableDeclaration(tokens: []ParsedToken, id_pos: usize, assign_pos: usize) bool {
    // Scan forward from identifier to assignment to look for MUTA token
    var pos: usize = id_pos + 1;
    while (pos < assign_pos) : (pos += 1) {
        if (tokens[pos].token_type == .TKN_MUTA) {
            return true;
        }
    }
    return false;
}

// Helper function to find the start of a line
fn findLineStart(tokens: []ParsedToken, index: usize) isize {
    var pos: isize = @intCast(index - 1);
    while (pos >= 0) {
        if (tokens[@intCast(pos)].token_type == .TKN_NEWLINE) {
            return pos + 1;
        }
        pos -= 1;
    }
    return 0; // Start of file
}
