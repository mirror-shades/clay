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
    literal: []const u8,
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
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_GROUP, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_ARROW, .literal = "->", .value_type = .nothing, .value = .{ .nothing = {} } });
                        continue;
                    }
                    if (self.groups.items.len > 0) {
                        for (self.groups.items) |group| {
                            try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_GROUP, .literal = group.name, .value_type = .nothing, .value = .{ .nothing = {} } });
                            try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_ARROW, .literal = "->", .value_type = .nothing, .value = .{ .nothing = {} } });
                        }
                    }
                    if (self.tokens[current_index].token_type == .TKN_ARROW) {
                        if (self.tokens[current_index + 1].token_type == .TKN_LBRACE) {
                            continue;
                        }
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_GROUP, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_ARROW, .literal = "->", .value_type = .nothing, .value = .{ .nothing = {} } });
                        continue;
                    }
                    if (self.tokens[current_index].token_type == .TKN_TYPE_ASSIGN or self.tokens[current_index].token_type == .TKN_VALUE_ASSIGN or self.tokens[current_index].token_type == .TKN_NEWLINE or self.tokens[current_index].token_type == .TKN_INSPECT) {
                        try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_IDENTIFIER, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                        if (self.tokens[current_index].token_type == .TKN_TYPE_ASSIGN) {
                            continue;
                        }
                        if (self.groups.items.len > 0) {
                            if (self.groups.items[self.groups.items.len - 1].type) |t| {
                                try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_TYPE_ASSIGN, .literal = ":", .value_type = .nothing, .value = .{ .nothing = {} } });
                                try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_TYPE, .literal = t, .value_type = .nothing, .value = .{ .nothing = {} } });
                            }
                        }
                        continue;
                    }
                },
                .TKN_RBRACKET => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_RBRACKET, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_LBRACKET => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_LBRACKET, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
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
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_LBRACE, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_RBRACE => {
                    _ = self.groups.pop();
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_RBRACE, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_VALUE_ASSIGN => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_VALUE_ASSIGN, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_TYPE_ASSIGN => {
                    if (self.tokens[current_index - 2].token_type == .TKN_ARROW) {
                        // this is a group -> : typing which would have been handled in the group -> identifier parsing
                        continue;
                    }
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_TYPE_ASSIGN, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_NEWLINE => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_NEWLINE, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_TYPE => {
                    if (self.tokens[current_index - 3].token_type == .TKN_ARROW) {
                        // this is a group -> : typing which would have been handled in the group -> identifier parsing
                        continue;
                    }
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_TYPE, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_VALUE => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_VALUE, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_INSPECT => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_INSPECT, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_ARROW => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_ARROW, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_PLUS => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_PLUS, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_MINUS => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_MINUS, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_STAR => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_STAR, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_SLASH => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_SLASH, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_PERCENT => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_PERCENT, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_POWER => {
                    try self.parsed_tokens.append(ParsedToken{ .token_type = .TKN_POWER, .literal = current_token.literal, .value_type = .nothing, .value = .{ .nothing = {} } });
                    continue;
                },
                .TKN_EOF => {
                    break;
                },
                else => unreachable,
            }
        }
    }
};
