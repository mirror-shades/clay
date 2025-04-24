// every line starts with an identifier
// every identifier is followed by a colon or an arrow
// if it's an arrow, the identifier is a group
// if it's a colon, the identifier is a variable
// an identifier and a group cannot have the same name
// trying to assign to a variable or group that already exists will change the original variable or group
// trying to assign to a variable or group that doesn't exist will create a new variable or group
// all statements end in newlines or EOF
// groups can be nested
// variables and groups can be referenced in other assignements but they must be defined in advance

const std = @import("std");
const token = @import("token.zig");
const ast = @import("ast.zig");
const print = std.debug.print;

pub const ParserError = error{
    UnexpectedToken,
    UnexpectedEOF,
    InvalidValue,
    UndefinedReference,
    OutOfMemory,
};

pub const Parser = struct {
    tokens: []const token.Token,
    current: usize,
    allocator: std.mem.Allocator,
    root: *ast.Node,
    symbol_table: std.StringHashMap(*ast.Node),
    input: []const u8,
    debug: bool,
    current_parent: *ast.Node, // Track the current parent node

    pub fn init(allocator: std.mem.Allocator, tokens: []const token.Token, input: []const u8, debug: bool) !Parser {
        const root = try ast.Node.init(allocator, .Program, "root");
        return .{
            .tokens = tokens,
            .current = 0,
            .allocator = allocator,
            .root = root,
            .symbol_table = std.StringHashMap(*ast.Node).init(allocator),
            .input = input,
            .debug = debug,
            .current_parent = root, // Start with root as the parent
        };
    }

    pub fn deinit(self: *Parser) void {
        self.root.deinit(self.allocator);
        self.symbol_table.deinit();
    }

    fn advance(self: *Parser) void {
        if (self.current < self.tokens.len) {
            self.current += 1;
        }
    }

    fn peek(self: *Parser) ?token.Token {
        if (self.current >= self.tokens.len) return null;
        return self.tokens[self.current];
    }

    fn consume(self: *Parser, expected: token.TokenKind) ParserError![]const u8 {
        if (self.current >= self.tokens.len) {
            return ParserError.UnexpectedEOF;
        }

        const tkn = self.tokens[self.current];
        if (tkn.kind != expected) {
            if (self.debug) {
                print("Expected {any}, got {any}\n", .{ expected, tkn.kind });
            }
            return ParserError.UnexpectedToken;
        }

        const text = self.input[tkn.start..tkn.end];
        self.advance();
        return text;
    }

    pub fn parse(self: *Parser) ParserError!void {
        while (self.current < self.tokens.len) {
            const tkn = self.tokens[self.current];
            if (self.debug) {
                print("Parsing token: {any}\n", .{tkn.kind});
            }
            switch (tkn.kind) {
                .TKN_IDENTIFIER, .TKN_CONST => try self.parseStatement(),
                .TKN_NEWLINE => self.advance(),
                .TKN_EOF => break,
                else => return ParserError.UnexpectedToken,
            }
        }
    }

    fn parseStatement(self: *Parser) ParserError!void {
        // Check for const
        var is_const = false;
        const current = self.tokens[self.current];

        if (current.kind == .TKN_CONST) {
            is_const = true;
            self.advance(); // consume const
            if (self.debug) {
                print("Found const declaration\n", .{});
            }
        }

        const name = try self.consume(.TKN_IDENTIFIER);
        if (self.debug) {
            print("Parsing statement for identifier: {s} (const: {})\n", .{ name, is_const });
        }

        const next = self.peek() orelse return ParserError.UnexpectedEOF;
        if (self.debug) {
            print("Next token: {any}\n", .{next.kind});
        }

        switch (next.kind) {
            .TKN_TYPE_ASSIGN => {
                self.advance(); // consume the :
                try self.parseVariable(name, is_const);
            },
            .TKN_ARROW => {
                if (is_const) {
                    return ParserError.UnexpectedToken; // Groups can't be const
                }
                self.advance(); // consume the ->
                try self.parseGroup(name);
            },
            else => return ParserError.UnexpectedToken,
        }
    }

    fn findNodeByName(_: *Parser, parent: *ast.Node, name: []const u8) ?*ast.Node {
        if (parent.children) |children| {
            for (children.items) |child| {
                if (std.mem.eql(u8, child.name, name)) {
                    return child;
                }
            }
        }
        return null;
    }

    fn resolveReference(self: *Parser, ref_name: []const u8) ParserError!token.Value {
        // Check if the reference exists in the global scope
        if (self.symbol_table.get(ref_name)) |node| {
            // Only allow direct access to global variables, not groups
            if (node.type == .Variable) {
                if (node.value) |value| {
                    return value;
                }
            }
        }

        // If we got here, the reference wasn't found or wasn't accessible
        return ParserError.UndefinedReference;
    }

    fn parseVariable(self: *Parser, name: []const u8, is_const: bool) ParserError!void {
        if (self.debug) {
            print("Parsing variable: {s} (const: {})\n", .{ name, is_const });
        }

        // Parse type
        const type_token = try self.consume(.TKN_TYPE_INT);
        if (self.debug) {
            print("Type: {s}\n", .{type_token});
        }

        // Parse value assignment
        _ = try self.consume(.TKN_VALUE_ASSIGN);

        // Parse value
        const value_token = self.peek() orelse return ParserError.UnexpectedEOF;
        var node: *ast.Node = undefined;
        var final_value: token.Value = undefined;

        switch (value_token.kind) {
            .TKN_VALUE_INT => {
                const value_text = self.input[value_token.start..value_token.end];
                if (self.debug) {
                    print("Int value: {s}\n", .{value_text});
                }
                const value = std.fmt.parseInt(i32, value_text, 10) catch return ParserError.InvalidValue;
                final_value = .{ .int = value };
                self.advance();
            },
            .TKN_IDENTIFIER => {
                const ref_name = try self.consume(.TKN_IDENTIFIER);
                if (self.debug) {
                    print("Reference to: {s}\n", .{ref_name});
                }

                // Check if this is a nested reference
                const next = self.peek() orelse return ParserError.UnexpectedEOF;
                if (next.kind == .TKN_ARROW) {
                    // This is a nested reference
                    const group_node = self.symbol_table.get(ref_name) orelse return ParserError.UndefinedReference;
                    if (group_node.type != .Group) {
                        return ParserError.UnexpectedToken; // Can't use -> on non-group
                    }

                    self.advance(); // consume ->
                    const child_name = try self.consume(.TKN_IDENTIFIER);
                    const child_node = self.findNodeByName(group_node, child_name) orelse return ParserError.UndefinedReference;

                    if (child_node.value) |value| {
                        final_value = value;
                    } else {
                        return ParserError.UndefinedReference;
                    }
                } else {
                    // Simple reference - check if it's in the global scope
                    // We need to make sure we get a GLOBAL variable
                    var found = false;
                    if (self.symbol_table.get(ref_name)) |found_node| {
                        if (found_node.type == .Variable) {
                            // Check if it's accessible from current scope
                            if (found_node.parent == self.root) {
                                // It's a global variable
                                if (found_node.value) |value| {
                                    final_value = value;
                                    found = true;
                                }
                            } else if (found_node.parent == self.current_parent) {
                                // It's in the same scope
                                if (found_node.value) |value| {
                                    final_value = value;
                                    found = true;
                                }
                            }
                        }
                    }

                    if (!found) {
                        if (self.debug) {
                            print("Variable not in scope: {s}\n", .{ref_name});
                        }
                        return ParserError.UndefinedReference;
                    }
                }

                if (self.debug) {
                    print("Resolved value: {any}\n", .{final_value});
                }
            },
            else => return ParserError.UnexpectedToken,
        }

        // Create node with resolved value
        node = try ast.Node.init(self.allocator, .Variable, name);
        node.value = final_value;
        node.value_type = .int;
        node.is_const = is_const;
        node.parent = self.current_parent; // Set the parent

        // Add to symbol table (all variables go here for quick lookup)
        try self.symbol_table.put(name, node);

        // Add to the current parent's children
        if (self.current_parent.children) |*children| {
            try children.append(node);
        } else {
            self.current_parent.children = std.ArrayList(*ast.Node).init(self.allocator);
            try self.current_parent.children.?.append(node);
        }
    }

    fn parseGroup(self: *Parser, name: []const u8) ParserError!void {
        if (self.debug) {
            print("Parsing group: {s}\n", .{name});
        }

        const node = try ast.Node.init(self.allocator, .Group, name);
        node.parent = self.current_parent; // Set the parent

        try self.symbol_table.put(name, node);

        // Add to current parent's children
        if (self.current_parent.children) |*children| {
            try children.append(node);
        } else {
            self.current_parent.children = std.ArrayList(*ast.Node).init(self.allocator);
            try self.current_parent.children.?.append(node);
        }

        // Initialize group's children array
        node.children = std.ArrayList(*ast.Node).init(self.allocator);

        // Save the previous parent
        const previous_parent = self.current_parent;
        // Set this group as the current parent
        self.current_parent = node;

        // Handle nested statements or scope
        const next = self.peek() orelse return ParserError.UnexpectedEOF;
        if (next.kind == .TKN_LBRACE) {
            self.advance(); // consume {
            while (self.current < self.tokens.len) {
                const tkn = self.tokens[self.current];
                if (tkn.kind == .TKN_RBRACE) {
                    self.advance();
                    break;
                }
                try self.parseStatement();
            }
        } else {
            try self.parseStatement();
        }

        // Restore the previous parent
        self.current_parent = previous_parent;
    }
};
