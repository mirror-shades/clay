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
                .TKN_SLASH => {
                    // Skip the slash and the rest of the line (comment)
                    if (self.debug) {
                        print("Skipping comment\n", .{});
                    }
                    self.advance(); // Skip the slash

                    // Skip all tokens until we hit a newline or EOF
                    while (self.current < self.tokens.len) {
                        const curr = self.tokens[self.current];
                        if (curr.kind == .TKN_NEWLINE or curr.kind == .TKN_EOF) {
                            break;
                        }
                        self.advance();
                    }
                },
                .TKN_ARROW => {
                    // Skip arrow tokens in the main loop as they are handled in parseGroup
                    self.advance();
                },
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
        // Only allow access to variables that are:
        // 1. In the current scope (directly)
        // 2. In the global scope (directly under root)
        // 3. NOT inside any groups unless accessed via arrow syntax

        // First check if it's a global variable (directly under root)
        if (self.symbol_table.get(ref_name)) |node| {
            if (node.type == .Variable and node.parent == self.root) {
                if (node.value) |value| {
                    return value;
                }
            }
        }

        // Then check current scope, but ONLY if we're not inside a group
        var current = self.current_parent;
        while (current != self.root) {
            if (current.type == .Group) {
                // We're inside a group, so don't allow direct access to variables
                return ParserError.UndefinedReference;
            }
            if (current.parent) |parent| {
                current = parent;
            } else break;
        }

        // Only if we're not in a group, check current scope
        if (self.findNodeByName(self.current_parent, ref_name)) |found_node| {
            if (found_node.type == .Variable) {
                if (found_node.value) |value| {
                    return value;
                }
            }
        }

        return ParserError.UndefinedReference;
    }

    fn parseVariable(self: *Parser, name: []const u8, is_const: bool) ParserError!void {
        if (self.debug) {
            print("Parsing variable: {s} (const: {})\n", .{ name, is_const });
        }

        // Parse type
        const type_token = self.peek() orelse return ParserError.UnexpectedEOF;
        var value_type: token.ValueType = undefined;

        switch (type_token.kind) {
            .TKN_TYPE_INT => {
                _ = try self.consume(.TKN_TYPE_INT);
                value_type = .int;
            },
            .TKN_TYPE_FLOAT => {
                _ = try self.consume(.TKN_TYPE_FLOAT);
                value_type = .float;
            },
            .TKN_TYPE_STRING => {
                _ = try self.consume(.TKN_TYPE_STRING);
                value_type = .string;
            },
            .TKN_TYPE_BOOL => {
                _ = try self.consume(.TKN_TYPE_BOOL);
                value_type = .bool;
            },
            else => return ParserError.UnexpectedToken,
        }

        if (self.debug) {
            print("Type: {s}\n", .{@tagName(value_type)});
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
            .TKN_VALUE_FLOAT => {
                const value_text = self.input[value_token.start..value_token.end];
                if (self.debug) {
                    print("Float value: {s}\n", .{value_text});
                }
                const value = std.fmt.parseFloat(f64, value_text) catch return ParserError.InvalidValue;
                final_value = .{ .float = value };
                self.advance();
            },
            .TKN_VALUE_STRING => {
                const value_text = self.input[value_token.start..value_token.end];
                if (self.debug) {
                    print("String value: {s}\n", .{value_text});
                }
                final_value = .{ .string = value_text };
                self.advance();
            },
            .TKN_VALUE_BOOL => {
                const value_text = self.input[value_token.start..value_token.end];
                if (self.debug) {
                    print("Bool value: {s}\n", .{value_text});
                }
                const value = std.mem.eql(u8, value_text, "true");
                final_value = .{ .bool = value };
                self.advance();
            },
            .TKN_IDENTIFIER => {
                // Look ahead to see if this is a nested reference
                const peek_ahead = self.peek() orelse return ParserError.UnexpectedEOF;

                if (peek_ahead.kind == .TKN_ARROW) {
                    // This is a nested reference chain (e.g., group1 -> group2 -> var)
                    final_value = try self.resolveNestedReference();
                    if (self.debug) {
                        print("Resolved nested reference to value: {any}\n", .{final_value});
                    }
                } else {
                    // This is a direct reference
                    const ref_name = try self.consume(.TKN_IDENTIFIER);
                    if (self.debug) {
                        print("Direct reference to: {s}\n", .{ref_name});
                    }

                    // Direct reference - only allow if:
                    // 1. It's a global variable (directly under root)
                    // 2. It's in the current scope and we're not inside a group

                    // First check if it's a global variable
                    if (self.symbol_table.get(ref_name)) |n| {
                        if (n.type == .Variable and n.parent == self.root) {
                            if (n.value) |value| {
                                final_value = value;
                            }
                        }
                    }

                    // Check if we're inside a group
                    var current = self.current_parent;
                    while (current != self.root) {
                        if (current.type == .Group) {
                            // We're inside a group, so don't allow direct access to variables
                            return ParserError.UndefinedReference;
                        }
                        if (current.parent) |parent| {
                            current = parent;
                        } else break;
                    }

                    // Only if we're not in a group, check current scope
                    if (self.findNodeByName(self.current_parent, ref_name)) |found_node| {
                        if (found_node.type == .Variable) {
                            if (found_node.value) |value| {
                                final_value = value;
                            }
                        }
                    }

                    if (std.meta.eql(final_value, undefined)) {
                        return ParserError.UndefinedReference;
                    }
                }
            },
            else => return ParserError.UnexpectedToken,
        }

        // Create node with resolved value
        node = try ast.Node.init(self.allocator, .Variable, name);
        node.value = final_value;
        node.value_type = value_type;
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

        // Check if this is a nested group declaration (e.g., bigNest -> littleNest)
        if (next.kind == .TKN_ARROW) {
            self.advance(); // consume ->
            const nested_name = try self.consume(.TKN_IDENTIFIER);
            try self.parseGroup(nested_name);
            return; // Return after handling nested group
        } else if (next.kind == .TKN_LBRACE) {
            self.advance(); // consume {
            while (self.current < self.tokens.len) {
                const tkn = self.tokens[self.current];

                if (tkn.kind == .TKN_RBRACE) {
                    self.advance();
                    break;
                } else if (tkn.kind == .TKN_NEWLINE) {
                    // Skip newlines inside groups
                    self.advance();
                    continue;
                } else if (tkn.kind == .TKN_IDENTIFIER or tkn.kind == .TKN_CONST) {
                    try self.parseStatement();
                } else {
                    return ParserError.UnexpectedToken;
                }
            }
        } else if (next.kind == .TKN_IDENTIFIER) {
            // Handle direct variable assignment pattern: group -> varname = value
            const var_name = try self.consume(.TKN_IDENTIFIER);

            // Check for assignment
            const assign = self.peek() orelse return ParserError.UnexpectedEOF;
            if (assign.kind == .TKN_VALUE_ASSIGN) {
                self.advance(); // consume =

                // Create a simple variable in this group
                const child_node = try ast.Node.init(self.allocator, .Variable, var_name);
                child_node.parent = node;

                // Parse the value - it could be a literal or a reference
                const value_token = self.peek() orelse return ParserError.UnexpectedEOF;

                if (value_token.kind == .TKN_IDENTIFIER) {
                    // This is a reference
                    const ref_name = try self.consume(.TKN_IDENTIFIER);

                    // Look for the reference in all accessible scopes
                    const ref_value = try self.resolveReference(ref_name);

                    // Set this as the child's value
                    child_node.value = ref_value;

                    // Determine value type from the reference
                    switch (ref_value) {
                        .int => child_node.value_type = .int,
                        .float => child_node.value_type = .float,
                        .string => child_node.value_type = .string,
                        .bool => child_node.value_type = .bool,
                        .time => child_node.value_type = .time,
                        .array => child_node.value_type = .array,
                        .null => child_node.value_type = .null,
                    }
                } else {
                    // This is a literal value
                    try self.parseStatement();
                    return;
                }

                // Add to the group's children
                try node.children.?.append(child_node);
            } else if (assign.kind == .TKN_TYPE_ASSIGN) {
                // This is a type assignment (var_name : type = value)
                // We need to back up the current counter to re-parse this as a statement
                self.current -= 1; // Go back to the identifier
                try self.parseStatement();
            }
        }

        // Restore the previous parent
        self.current_parent = previous_parent;
    }

    fn resolveNestedReference(self: *Parser) ParserError!token.Value {
        // Get the first identifier (group or variable name)
        const first_name = try self.consume(.TKN_IDENTIFIER);
        if (self.debug) {
            print("Starting nested reference resolution with: {s}\n", .{first_name});
        }

        var current_node = self.symbol_table.get(first_name) orelse return ParserError.UndefinedReference;

        // Keep following the arrow chain
        while (true) {
            const next = self.peek() orelse return ParserError.UnexpectedEOF;
            if (next.kind != .TKN_ARROW) {
                // If we're at a variable, return its value
                if (current_node.type == .Variable) {
                    if (current_node.value) |value| {
                        return value;
                    }
                }
                return ParserError.UndefinedReference;
            }

            self.advance(); // consume ->
            const child_name = try self.consume(.TKN_IDENTIFIER);
            if (self.debug) {
                print("Following reference to: {s}\n", .{child_name});
            }

            // Find the child in the current node's children
            const child_node = self.findNodeByName(current_node, child_name) orelse return ParserError.UndefinedReference;
            current_node = child_node;

            // If this is the last item in the chain and it's a variable, return its value
            const peek_next = self.peek() orelse {
                if (child_node.type == .Variable) {
                    if (child_node.value) |value| {
                        return value;
                    }
                }
                return ParserError.UndefinedReference;
            };

            if (peek_next.kind != .TKN_ARROW) {
                if (child_node.type == .Variable) {
                    if (child_node.value) |value| {
                        return value;
                    }
                }
                return ParserError.UndefinedReference;
            }
        }
    }
};
