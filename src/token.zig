const std = @import("std");

pub const ValueType = enum {
    int,
    float,
    string,
    bool,
    time,
    array,
    null,
};

pub const Value = union(ValueType) {
    int: i32,
    float: f64,
    string: []const u8,
    bool: bool,
    time: i64,
    array: []const Value,
    null: void,
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
    TKN_TYPE_INT, // int
    TKN_TYPE_FLOAT, // float
    TKN_TYPE_STRING, // string
    TKN_TYPE_BOOL, // bool
    TKN_TYPE_TIME, // time
    TKN_TYPE_ARRAY, // array
    TKN_VALUE_INT, // 123
    TKN_VALUE_FLOAT, // 123.45
    TKN_VALUE_STRING, //"hello"
    TKN_VALUE_BOOL, // true/false
    TKN_VALUE_TIME, // ISO timestamp
    TKN_VALUE_NULL, // null
    TKN_VALUE_ARRAY, // [1, 2, 3]
    TKN_NEWLINE, // \n
    TKN_EOF, // end of file
};

pub const Token = struct {
    kind: TokenKind,
    start: usize,
    end: usize,
    line: usize,
};

pub const keywords = std.StaticStringMap(TokenKind).initComptime(.{
    .{ "int", .TKN_TYPE_INT },
    .{ "float", .TKN_TYPE_FLOAT },
    .{ "string", .TKN_TYPE_STRING },
    .{ "bool", .TKN_TYPE_BOOL },
    .{ "time", .TKN_TYPE_TIME },
    .{ "array", .TKN_TYPE_ARRAY },
    .{ "true", .TKN_VALUE_BOOL },
    .{ "false", .TKN_VALUE_BOOL },
    .{ "null", .TKN_VALUE_NULL },
    .{ "array", .TKN_VALUE_ARRAY },
    .{ "const", .TKN_CONST },
});
