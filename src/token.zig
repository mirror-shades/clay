const std = @import("std");

pub const ValueType = enum {
    int,
    float,
    string,
    bool,
    nothing,

    pub fn toString(self: ValueType) []const u8 {
        return switch (self) {
            .int => "int",
            .float => "float",
            .string => "string",
            .bool => "bool",
            .nothing => "nothing",
        };
    }
};

pub const Value = union(ValueType) {
    int: i32,
    float: f64,
    string: []const u8,
    bool: bool,
    nothing: void,
};

pub const TokenKind = enum {
    TKN_IDENTIFIER, // variable/group names
    TKN_TYPE_ASSIGN, // :
    TKN_ARROW, // ->
    TKN_VALUE_ASSIGN, // =
    TKN_SLASH, // /
    TKN_STAR, // *
    TKN_PLUS, // +
    TKN_MINUS, // -
    TKN_POWER, // ^
    TKN_PERCENT, // %
    TKN_LPAREN, // (
    TKN_RPAREN, // )
    TKN_LBRACE, // {
    TKN_RBRACE, // }
    TKN_LBRACKET, // [
    TKN_RBRACKET, // ]
    TKN_COMMA, // ,
    TKN_CONST, // const
    TKN_VALUE, // value
    TKN_TYPE, // type
    TKN_GROUP, // group
    TKN_NEWLINE, // \n
    TKN_INSPECT, // ?
    TKN_LOOKUP, //
    TKN_EXPRESSION, // expression
    TKN_EOF, // end of file

    pub fn toString(self: TokenKind) []const u8 {
        return switch (self) {
            .TKN_IDENTIFIER => "TKN_IDENTIFIER",
            .TKN_NEWLINE => "TKN_NEWLINE",
            .TKN_EOF => "TKN_EOF",
            .TKN_ARROW => "TKN_ARROW",
            .TKN_EXPRESSION => "TKN_EXPRESSION",
            .TKN_VALUE_ASSIGN => "TKN_VALUE_ASSIGN",
            .TKN_TYPE_ASSIGN => "TKN_TYPE_ASSIGN",
            .TKN_SLASH => "TKN_SLASH",
            .TKN_STAR => "TKN_STAR",
            .TKN_PLUS => "TKN_PLUS",
            .TKN_MINUS => "TKN_MINUS",
            .TKN_POWER => "TKN_POWER",
            .TKN_PERCENT => "TKN_PERCENT",
            .TKN_LPAREN => "TKN_LPAREN",
            .TKN_RPAREN => "TKN_RPAREN",
            .TKN_LBRACE => "TKN_LBRACE",
            .TKN_RBRACE => "TKN_RBRACE",
            .TKN_LBRACKET => "TKN_LBRACKET",
            .TKN_RBRACKET => "TKN_RBRACKET",
            .TKN_COMMA => "TKN_COMMA",
            .TKN_CONST => "TKN_CONST",
            .TKN_TYPE => "TKN_TYPE",
            .TKN_GROUP => "TKN_GROUP",
            .TKN_VALUE => "TKN_VALUE",
            .TKN_INSPECT => "TKN_INSPECT",
            .TKN_LOOKUP => "TKN_LOOKUP",
        };
    }
};

pub const Token = struct {
    literal: []const u8,
    token_type: TokenKind,
    value_type: ValueType,
    line_number: usize,
    token_number: usize,
};

pub fn makeToken(literal: []const u8, token_type: TokenKind, value_type: ValueType, line_number: usize, token_number: usize, start_pos: usize) Token {
    return Token{
        .literal = literal,
        .token_type = token_type,
        .value_type = value_type,
        .line_number = line_number,
        .token_number = token_number,
        .start_pos = start_pos,
    };
}
