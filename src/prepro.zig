const std = @import("std");
const ParsedToken = @import("parser.zig").ParsedToken;
const Token = @import("token.zig").Token;
const TokenKind = @import("token.zig").TokenKind;
const ValueType = @import("token.zig").ValueType;
const Value = @import("token.zig").Value;

pub const Preprocessor = struct {
    pub const Variable = struct {
        name: []const u8,
        value: Value,
        type: ValueType,
    };

    pub const Scope = struct {
        variables: std.StringHashMap(Variable),
        nested_scopes: std.StringHashMap(*Scope),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Scope {
            return Scope{
                .variables = std.StringHashMap(Variable).init(allocator),
                .nested_scopes = std.StringHashMap(*Scope).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Scope) void {
            var it = self.nested_scopes.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.*.deinit();
                self.allocator.destroy(entry.value_ptr.*);
            }
            self.nested_scopes.deinit();
            self.variables.deinit();
        }
    };

    allocator: std.mem.Allocator,
    root_scope: Scope,

    pub fn init(allocator: std.mem.Allocator) Preprocessor {
        return Preprocessor{
            .allocator = allocator,
            .root_scope = Scope.init(allocator),
        };
    }

    pub fn deinit(self: *Preprocessor) void {
        self.root_scope.deinit();
    }

    // Build lookup path for forward traversal (looking ahead from current position)
    pub fn buildLookupPathForward(self: *Preprocessor, tokens: []ParsedToken, start_index: usize) ![][]const u8 {
        var path = std.ArrayList([]const u8).init(self.allocator);
        defer path.deinit();

        var i = start_index;

        // Add the first token (identifier, group, or lookup)
        if (i < tokens.len and (tokens[i].token_type == .TKN_IDENTIFIER or
            tokens[i].token_type == .TKN_GROUP or
            tokens[i].token_type == .TKN_LOOKUP))
        {
            try path.append(tokens[i].literal);
            i += 1;
        } else {
            return error.InvalidLookupPath;
        }

        // Continue collecting tokens as long as there are more in the path
        while (i < tokens.len) {
            if (tokens[i].token_type == .TKN_GROUP or tokens[i].token_type == .TKN_IDENTIFIER or tokens[i].token_type == .TKN_LOOKUP) {
                try path.append(tokens[i].literal);
                i += 1;
            } else {
                break; // Stop at the first non-path token
            }
        }

        // Create a slice that will be owned by the caller
        const result = try self.allocator.alloc([]const u8, path.items.len);
        for (path.items, 0..) |item, idx| {
            result[idx] = item;
        }

        // Debug the path we're looking up
        std.debug.print("Looking up path: ", .{});
        for (result) |part| {
            std.debug.print("{s} -> ", .{part});
        }
        std.debug.print("\n", .{});

        return result;
    }

    // Build an array of lookup parts for backward traversal (for inspections or variable lookups)
    pub fn buildLookupPathBackward(self: *Preprocessor, tokens: []ParsedToken, index: usize) ![][]const u8 {
        var path = std.ArrayList([]const u8).init(self.allocator);
        defer path.deinit();

        // Improved approach to capture complete paths
        // Start at the token right before the inspect symbol
        if (index == 0 or index >= tokens.len) {
            return &[_][]const u8{};
        }

        var current_index: isize = @intCast(index - 1);

        // First get the variable name (identifier) that is being inspected
        if (tokens[@intCast(current_index)].token_type == .TKN_IDENTIFIER or
            tokens[@intCast(current_index)].token_type == .TKN_LOOKUP)
        {
            try path.append(tokens[@intCast(current_index)].literal);
            current_index -= 1;
        } else {
            // If not an identifier or lookup, just return an empty path
            return &[_][]const u8{};
        }

        // Now walk backward looking for groups and arrows
        var in_path = false;
        while (current_index >= 0) {
            const token = tokens[@intCast(current_index)];

            if (token.token_type == .TKN_ARROW) {
                in_path = true;
                current_index -= 1;
                continue;
            }

            if (in_path and (token.token_type == .TKN_GROUP or
                token.token_type == .TKN_IDENTIFIER or
                token.token_type == .TKN_LOOKUP))
            {
                try path.insert(0, token.literal);
                in_path = false;
                current_index -= 1;
                continue;
            }

            // If we see a newline or any non-path token, stop searching
            if (token.token_type == .TKN_NEWLINE or
                token.token_type == .TKN_VALUE_ASSIGN or
                token.token_type == .TKN_TYPE_ASSIGN)
            {
                break;
            }

            current_index -= 1;
        }

        // Debug the lookup path we found
        std.debug.print("Lookup path (backward): ", .{});
        for (path.items) |part| {
            std.debug.print("{s} -> ", .{part});
        }
        std.debug.print("\n", .{});

        // Create a slice that will be owned by the caller
        const result = try self.allocator.alloc([]const u8, path.items.len);
        for (path.items, 0..) |item, y| {
            result[y] = item;
        }
        return result;
    }

    // Build an array for assignment (similar to buildAssignmentArray in JS)
    pub fn buildAssignmentArray(self: *Preprocessor, tokens: []ParsedToken, index: usize) ![]Variable {
        var result = std.ArrayList(Variable).init(self.allocator);
        defer result.deinit();

        // First, collect any groups (scopes) that come before the identifier

        // Scan backward from the assignment operator to find groups
        var i: isize = @intCast(index - 1);
        while (i >= 0) : (i -= 1) {
            if (tokens[@intCast(i)].token_type == .TKN_GROUP) {
                try result.append(Variable{
                    .name = tokens[@intCast(i)].literal,
                    .value = Value{ .nothing = {} },
                    .type = .nothing,
                });
            } else if (tokens[@intCast(i)].token_type == .TKN_NEWLINE or
                tokens[@intCast(i)].token_type == .TKN_EOF)
            {
                break; // Stop at the beginning of the line
            }
        }

        // If we found groups, reverse their order to get the path correctly
        if (result.items.len > 0) {
            var left: usize = 0;
            var right: usize = result.items.len - 1;
            while (left < right) {
                const temp = result.items[left];
                result.items[left] = result.items[right];
                result.items[right] = temp;
                left += 1;
                right -= 1;
            }
        }

        // Look for the identifier after the last group
        var identifier_found = false;
        if (index > 0) {
            const id_pos: isize = @intCast(index - 1);

            if (tokens[@intCast(id_pos)].token_type == .TKN_IDENTIFIER) {
                // Identifier directly before assignment
                try result.append(Variable{
                    .name = tokens[@intCast(id_pos)].literal,
                    .value = Value{ .nothing = {} },
                    .type = .nothing,
                });
                identifier_found = true;
            } else if (id_pos > 0 and tokens[@intCast(id_pos)].token_type == .TKN_TYPE and
                tokens[@intCast(id_pos - 1)].token_type == .TKN_IDENTIFIER)
            {
                // Handle pattern: identifier -> type -> assignment
                try result.append(Variable{
                    .name = tokens[@intCast(id_pos - 1)].literal,
                    .value = Value{ .nothing = {} },
                    .type = .nothing,
                });
                identifier_found = true;
            }
        }

        if (!identifier_found) {
            std.debug.print("Error: No identifier found before assignment at token {d}\n", .{index});
            return error.InvalidAssignment;
        }

        // Add the value token if it exists
        var value_found = false;

        // Check for an expression token after the assignment
        if (index + 1 < tokens.len and tokens[index + 1].token_type == .TKN_EXPRESSION) {
            // For now, use a default value - in a real implementation, you'd evaluate the expression
            try result.append(Variable{
                .name = "value",
                .value = Value{ .int = 12 }, // Default value for expressions
                .type = .int,
            });
            value_found = true;
        }
        // Check for a regular value token
        else if (index + 1 < tokens.len and tokens[index + 1].token_type == .TKN_VALUE) {
            try result.append(Variable{
                .name = "value", // This name doesn't matter as it will be treated as value
                .value = tokens[index + 1].value,
                .type = tokens[index + 1].value_type,
            });
            value_found = true;
        }
        // Check for a variable lookup
        else if (index + 1 < tokens.len and (tokens[index + 1].token_type == .TKN_IDENTIFIER or
            tokens[index + 1].token_type == .TKN_GROUP or
            tokens[index + 1].token_type == .TKN_LOOKUP))
        {
            // Handle the case where the value is another variable lookup
            const lookup_path = try self.buildLookupPathForward(tokens, index + 1);
            defer self.allocator.free(lookup_path);

            if (self.getLookupValue(lookup_path)) |var_value| {
                try result.append(var_value);
                value_found = true;
            } else {
                // Instead of returning an error, append a variable with "not found" indicator
                std.debug.print("Warning: Value not found in lookup path, using default value\n", .{});
                try result.append(Variable{
                    .name = "value_not_found",
                    .value = Value{ .nothing = {} },
                    .type = .nothing,
                });
                value_found = true;
            }
        }

        // If no value was found, add a default value to ensure we have at least 2 elements
        if (!value_found) {
            std.debug.print("Warning: No value found after assignment, using default\n", .{});
            try result.append(Variable{
                .name = "value",
                .value = Value{ .int = 0 },
                .type = .int,
            });
        }

        // Debug: Print the assignment array
        std.debug.print("Assignment array: ", .{});
        for (result.items, 0..) |item, idx| {
            std.debug.print("[{d}]={s} ", .{ idx, item.name });
        }
        std.debug.print("\n", .{});

        // Create a slice that will be owned by the caller
        const array = try self.allocator.alloc(Variable, result.items.len);
        for (result.items, 0..) |item, y| {
            array[y] = item;
        }
        return array;
    }

    // Assigns a value using the assignment array
    pub fn assignValue(self: *Preprocessor, assignment_array: []Variable) !void {
        // The structure should match the JS code: groups, identifier, value
        if (assignment_array.len < 2) return error.InvalidAssignment;

        // Last item is the value
        const value_item = assignment_array[assignment_array.len - 1];
        // Second to last is the identifier
        const identifier = assignment_array[assignment_array.len - 2].name;
        // Everything before the identifier is groups
        const groups = assignment_array[0 .. assignment_array.len - 2];

        if (groups.len == 0) {
            // Top-level assignment
            const variable = Variable{
                .name = identifier,
                .value = value_item.value,
                .type = value_item.type,
            };

            try self.root_scope.variables.put(identifier, variable);
            return;
        }

        // Navigate to the correct scope, creating as needed
        var current_scope = &self.root_scope;

        for (groups) |group| {
            if (!current_scope.nested_scopes.contains(group.name)) {
                const new_scope = try self.allocator.create(Scope);
                new_scope.* = Scope.init(self.allocator);
                try current_scope.nested_scopes.put(group.name, new_scope);
            }

            current_scope = current_scope.nested_scopes.get(group.name).?;
        }

        // Create/update the variable
        const variable = Variable{
            .name = identifier,
            .value = value_item.value,
            .type = value_item.type,
        };

        try current_scope.variables.put(identifier, variable);
    }

    // Retrieves a value from the appropriate scope
    pub fn getLookupValue(self: *Preprocessor, path: [][]const u8) ?Variable {
        if (path.len < 1) return null;

        // Last element is the variable name
        const var_name = path[path.len - 1];

        // Debug: Print the path being looked up
        std.debug.print("getLookupValue path: ", .{});
        for (path) |part| {
            std.debug.print("{s} -> ", .{part});
        }
        std.debug.print("\n", .{});

        // Navigate to the correct scope
        var current_scope = &self.root_scope;

        // Debug: Print all variables in root scope
        std.debug.print("Root scope variables: ", .{});
        var root_it = current_scope.variables.iterator();
        while (root_it.next()) |entry| {
            std.debug.print("{s}, ", .{entry.key_ptr.*});
        }
        std.debug.print("\n", .{});

        // Debug: Print all nested scopes in root
        std.debug.print("Root nested scopes: ", .{});
        var nested_it = current_scope.nested_scopes.iterator();
        while (nested_it.next()) |entry| {
            std.debug.print("{s}, ", .{entry.key_ptr.*});
        }
        std.debug.print("\n", .{});

        for (path[0 .. path.len - 1], 0..) |scope_name, idx| {
            if (!current_scope.nested_scopes.contains(scope_name)) {
                std.debug.print("Scope not found: {s}\n", .{scope_name});
                return null; // Scope doesn't exist
            }

            current_scope = current_scope.nested_scopes.get(scope_name).?;

            // Debug: Print variables in current scope
            std.debug.print("Scope {s} variables: ", .{scope_name});
            var vars_it = current_scope.variables.iterator();
            while (vars_it.next()) |entry| {
                std.debug.print("{s}, ", .{entry.key_ptr.*});
            }
            std.debug.print("\n", .{});

            // If not at the last scope, print nested scopes
            if (idx < path.len - 2) {
                std.debug.print("Scope {s} nested scopes: ", .{scope_name});
                var next_nested_it = current_scope.nested_scopes.iterator();
                while (next_nested_it.next()) |entry| {
                    std.debug.print("{s}, ", .{entry.key_ptr.*});
                }
                std.debug.print("\n", .{});
            }
        }

        // Look up the variable
        const result = current_scope.variables.get(var_name);
        if (result) |val| {
            std.debug.print("Found variable {s} with type {s}\n", .{ var_name, val.type.toString() });
        } else {
            std.debug.print("Variable {s} not found in scope\n", .{var_name});
        }
        return result;
    }

    fn evaluateExpression(self: *Preprocessor, tokens: []Token) Value {
        if (tokens.len == 0) {
            std.debug.print("Warning: Empty expression\n", .{});
            return Value{ .int = 0 };
        }

        // Use the shunting yard algorithm to convert infix to postfix
        var stack = std.ArrayList(Token).init(self.allocator);
        defer stack.deinit();

        var output = std.ArrayList(Token).init(self.allocator);
        defer output.deinit();

        const getPrecedence = struct {
            fn get(token_type: TokenKind) u8 {
                return switch (token_type) {
                    .TKN_POWER => 3,
                    .TKN_STAR, .TKN_SLASH, .TKN_PERCENT => 2,
                    .TKN_PLUS, .TKN_MINUS => 1,
                    else => 0,
                };
            }
        }.get;

        // First, convert infix to postfix (shunting yard algorithm)
        std.debug.print("evaluating expression\n", .{});
        for (tokens) |token| {
            if (token.token_type == .TKN_VALUE) {
                output.append(token) catch unreachable;
            } else if (token.token_type == .TKN_IDENTIFIER) {
                // Handle variables by looking them up
                output.append(token) catch unreachable;
            } else if (token.token_type == .TKN_PLUS or token.token_type == .TKN_MINUS or
                token.token_type == .TKN_STAR or token.token_type == .TKN_SLASH or
                token.token_type == .TKN_PERCENT or token.token_type == .TKN_POWER)
            {
                while (stack.items.len > 0 and
                    getPrecedence(stack.items[stack.items.len - 1].token_type) >= getPrecedence(token.token_type))
                {
                    if (stack.items.len > 0) {
                        const last_op = stack.items[stack.items.len - 1];
                        output.append(last_op) catch unreachable;
                        _ = stack.orderedRemove(stack.items.len - 1);
                    }
                }
                stack.append(token) catch unreachable;
            } else if (token.token_type == .TKN_LPAREN) {
                stack.append(token) catch unreachable;
            } else if (token.token_type == .TKN_RPAREN) {
                while (stack.items.len > 0 and stack.items[stack.items.len - 1].token_type != .TKN_LPAREN) {
                    if (stack.items.len > 0) {
                        const last_op = stack.items[stack.items.len - 1];
                        output.append(last_op) catch unreachable;
                        _ = stack.orderedRemove(stack.items.len - 1);
                    }
                }
                if (stack.items.len > 0 and stack.items[stack.items.len - 1].token_type == .TKN_LPAREN) {
                    _ = stack.orderedRemove(stack.items.len - 1);
                }
            } else {
                // Skip tokens that aren't part of the expression
                continue;
            }
        }

        while (stack.items.len > 0) {
            const last_op = stack.items[stack.items.len - 1];
            output.append(last_op) catch unreachable;
            _ = stack.orderedRemove(stack.items.len - 1);
        }

        std.debug.print("output: ", .{});
        for (output.items) |token| {
            std.debug.print("{s} ", .{token.literal});
        }
        std.debug.print("\n", .{});

        // Now evaluate the postfix expression
        var result_stack = std.ArrayList(Value).init(self.allocator);
        defer result_stack.deinit();

        for (output.items) |token| {
            switch (token.token_type) {
                .TKN_VALUE => {
                    // Push the value onto the stack
                    const value: Value = switch (token.value_type) {
                        .int => Value{ .int = std.fmt.parseInt(i32, token.literal, 10) catch 0 },
                        .float => Value{ .float = std.fmt.parseFloat(f64, token.literal) catch 0 },
                        .string => Value{ .string = token.literal },
                        .bool => Value{ .bool = std.mem.eql(u8, token.literal, "true") },
                        .nothing => Value{ .nothing = {} },
                    };
                    result_stack.append(value) catch unreachable;
                },
                .TKN_IDENTIFIER => {
                    // Look up the variable value and push onto the stack
                    var found = false;
                    var it = self.root_scope.variables.iterator();
                    while (it.next()) |entry| {
                        if (std.mem.eql(u8, entry.key_ptr.*, token.literal)) {
                            result_stack.append(entry.value_ptr.*.value) catch unreachable;
                            found = true;
                            break;
                        }
                    }

                    if (!found) {
                        // Variable not found, use default value
                        std.debug.print("Warning: Variable '{s}' not found in expression, using 0\n", .{token.literal});
                        result_stack.append(Value{ .int = 0 }) catch unreachable;
                    }
                },
                .TKN_PLUS, .TKN_MINUS, .TKN_STAR, .TKN_SLASH, .TKN_PERCENT, .TKN_POWER => {
                    if (result_stack.items.len < 2) {
                        std.debug.print("Error: Not enough operands for operator {s}\n", .{token.literal});
                        return Value{ .int = 0 }; // Return a default value in case of error
                    }

                    // Get the operands (but don't remove them yet)
                    const b_index = result_stack.items.len - 1;
                    const a_index = result_stack.items.len - 2;

                    const b = result_stack.items[b_index];
                    const a = result_stack.items[a_index];

                    // For simplicity, we'll assume all values are integers for now
                    var a_val: i32 = 0;
                    var b_val: i32 = 0;

                    // Extract integer values
                    switch (a) {
                        .int => |val| a_val = val,
                        .float => |val| a_val = @intFromFloat(val),
                        .string, .bool, .nothing => {
                            std.debug.print("Warning: Non-numeric value in expression, using 0\n", .{});
                        },
                    }

                    switch (b) {
                        .int => |val| b_val = val,
                        .float => |val| b_val = @intFromFloat(val),
                        .string, .bool, .nothing => {
                            std.debug.print("Warning: Non-numeric value in expression, using 0\n", .{});
                        },
                    }

                    var result: i32 = 0;

                    switch (token.token_type) {
                        .TKN_PLUS => result = a_val + b_val,
                        .TKN_MINUS => result = a_val - b_val,
                        .TKN_STAR => result = a_val * b_val,
                        .TKN_SLASH => {
                            if (b_val == 0) {
                                std.debug.print("Error: Division by zero\n", .{});
                                result = 0;
                            } else {
                                result = @divTrunc(a_val, b_val);
                            }
                        },
                        .TKN_PERCENT => {
                            if (b_val == 0) {
                                std.debug.print("Error: Modulo by zero\n", .{});
                                result = 0;
                            } else {
                                result = @mod(a_val, b_val);
                            }
                        },
                        .TKN_POWER => {
                            // Simple power implementation
                            result = 1;
                            var exp = b_val;
                            while (exp > 0) : (exp -= 1) {
                                result *= a_val;
                            }
                        },
                        else => {},
                    }

                    // Remove the two operands
                    _ = result_stack.orderedRemove(b_index);
                    _ = result_stack.orderedRemove(a_index);

                    // Push the result
                    result_stack.append(Value{ .int = result }) catch unreachable;
                },
                else => {},
            }
        }

        // Return the final result
        if (result_stack.items.len > 0) {
            const final_result = result_stack.items[result_stack.items.len - 1];
            std.debug.print("Expression result: {any}\n", .{final_result});
            return final_result;
        } else {
            std.debug.print("Error: Empty expression result\n", .{});
            return Value{ .int = 0 };
        }
    }

    // Main interpret function
    pub fn interpret(self: *Preprocessor, tokens: []ParsedToken) !void {
        var i: usize = 0;

        while (i < tokens.len) : (i += 1) {
            const current_token = tokens[i];

            switch (current_token.token_type) {
                .TKN_VALUE_ASSIGN => {
                    const assignment = try self.buildAssignmentArray(tokens, i);
                    defer self.allocator.free(assignment);

                    // Check if the next token is an expression
                    if (i + 1 < tokens.len and tokens[i + 1].token_type == .TKN_EXPRESSION) {
                        // Skip the expression token in the next iteration since we're handling it now
                        defer i += 1;

                        if (tokens[i + 1].expression) |expression| {
                            // Safely evaluate the expression
                            const result = self.evaluateExpression(expression);

                            // Update the assignment with the expression result
                            if (assignment.len >= 2) {
                                var modified_assignment = try self.allocator.dupe(Variable, assignment);
                                defer self.allocator.free(modified_assignment);

                                // Replace the value part with our calculated result
                                modified_assignment[modified_assignment.len - 1].value = result;
                                modified_assignment[modified_assignment.len - 1].type = .int; // Assuming int for now

                                try self.assignValue(modified_assignment);
                            } else {
                                try self.assignValue(assignment);
                            }
                        } else {
                            try self.assignValue(assignment);
                        }
                    } else {
                        try self.assignValue(assignment);
                    }
                },
                .TKN_EXPRESSION => {
                    // Expression tokens are handled alongside VALUE_ASSIGN tokens
                    continue;
                },
                .TKN_INSPECT => {
                    if (i > 0) {
                        // Handle direct values
                        if (i > 0 and tokens[i - 1].token_type == .TKN_VALUE) {
                            const value_type_str = tokens[i - 1].value_type.toString();
                            std.debug.print("[{d}:{d}] value  :{s} = ", .{
                                current_token.line_number,
                                current_token.token_number,
                                value_type_str,
                            });

                            // Print the value based on its type
                            switch (tokens[i - 1].value_type) {
                                .int => std.debug.print("{d}\n", .{tokens[i - 1].value.int}),
                                .float => std.debug.print("{any}\n", .{tokens[i - 1].value.float}),
                                .string => std.debug.print("\"{s}\"\n", .{tokens[i - 1].value.string}),
                                .bool => std.debug.print("{s}\n", .{if (tokens[i - 1].value.bool) "TRUE" else "FALSE"}),
                                .nothing => std.debug.print("(nothing)\n", .{}),
                            }
                            continue;
                        }

                        // Handle variable lookups
                        const path = try self.buildLookupPathForInspection(tokens, i);
                        defer self.allocator.free(path);

                        // Build a formatted path string for display
                        var path_str: []u8 = undefined;
                        if (path.len > 0) {
                            var buffer = std.ArrayList(u8).init(self.allocator);
                            defer buffer.deinit();

                            for (path, 0..) |part, idx| {
                                if (idx > 0) {
                                    try buffer.appendSlice("->");
                                }
                                try buffer.appendSlice(part);
                            }

                            path_str = try self.allocator.dupe(u8, buffer.items);
                            // Don't free yet: defer self.allocator.free(path_str);
                        } else {
                            path_str = try self.allocator.dupe(u8, "undefined");
                            // Don't free yet: defer self.allocator.free(path_str);
                        }

                        if (self.getLookupValue(path)) |var_value| {
                            std.debug.print("[{d}:{d}] {s} :{s} = ", .{
                                current_token.line_number,
                                current_token.token_number,
                                path_str,
                                var_value.type.toString(),
                            });

                            switch (var_value.type) {
                                .int => std.debug.print("{d}\n", .{var_value.value.int}),
                                .float => std.debug.print("{any}\n", .{var_value.value.float}),
                                .string => std.debug.print("\"{s}\"\n", .{var_value.value.string}),
                                .bool => std.debug.print("{s}\n", .{if (var_value.value.bool) "TRUE" else "FALSE"}),
                                .nothing => std.debug.print("(nothing)\n", .{}),
                            }
                        } else {
                            unreachable;
                        }

                        // Free after using
                        self.allocator.free(path_str);
                    }
                },
                else => {},
            }
        }
    }

    // Process tokens and execute the script
    pub fn process(self: *Preprocessor, tokens: []ParsedToken) !void {
        try self.interpret(tokens);
    }

    // Dump all variables to a writer
    pub fn dumpVariables(self: *Preprocessor, writer: anytype, allocator: std.mem.Allocator) !void {
        // Write root scope variables
        try writer.print("// Root scope variables\n", .{});
        var root_it = self.root_scope.variables.iterator();
        while (root_it.next()) |entry| {
            const var_value = entry.value_ptr.*;
            try writeVariableToWriter(writer, "", entry.key_ptr.*, var_value);
        }

        // Write nested scopes recursively
        try self.dumpNestedScopes(writer, self.root_scope, "", allocator);
    }

    fn writeVariableToWriter(writer: anytype, prefix: []const u8, name: []const u8, var_value: Variable) !void {
        try writer.print("{s}{s} : {s} = ", .{ prefix, name, var_value.type.toString() });

        switch (var_value.type) {
            .int => try writer.print("{d}\n", .{var_value.value.int}),
            .float => try writer.print("{d:.2}\n", .{var_value.value.float}),
            .string => try writer.print("\"{s}\"\n", .{var_value.value.string}),
            .bool => try writer.print("{s}\n", .{if (var_value.value.bool) "TRUE" else "FALSE"}),
            .nothing => try writer.print("(nothing)\n", .{}),
        }
    }

    fn dumpNestedScopes(self: *Preprocessor, writer: anytype, scope: Scope, prefix: []const u8, allocator: std.mem.Allocator) !void {
        var nested_it = scope.nested_scopes.iterator();
        while (nested_it.next()) |entry| {
            const scope_name = entry.key_ptr.*;
            const new_prefix = try std.fmt.allocPrint(allocator, "{s}{s}->", .{ prefix, scope_name });
            defer allocator.free(new_prefix);

            try writer.print("\n// {s} scope variables\n", .{new_prefix});

            const nested_scope = entry.value_ptr.*;
            var vars_it = nested_scope.variables.iterator();
            while (vars_it.next()) |var_entry| {
                const var_value = var_entry.value_ptr.*;
                try writeVariableToWriter(writer, new_prefix, var_entry.key_ptr.*, var_value);
            }

            // Recursively write sub-scopes
            try self.dumpNestedScopes(writer, nested_scope.*, new_prefix, allocator);
        }
    }

    // Handle inspection tokens (?) more accurately -
    // we need to fix the path order for inspection tokens
    pub fn buildLookupPathForInspection(self: *Preprocessor, tokens: []ParsedToken, index: usize) ![][]const u8 {
        var path = std.ArrayList([]const u8).init(self.allocator);
        defer path.deinit();

        // If the token is not an inspection token, return empty path
        if (index >= tokens.len or tokens[index].token_type != .TKN_INSPECT) {
            return &[_][]const u8{};
        }

        // We need to look backwards starting from the inspect token to find all parts
        // of the path. The tokens before the inspect should include:
        // 1. The variable name (identifier)
        // 2. Possibly group tokens representing nested scopes

        // Start with the token right before the inspect symbol
        if (index == 0) {
            return &[_][]const u8{};
        }

        // Working backward from the inspect token to construct the path
        var current_pos: isize = @intCast(index - 1);
        const start_line_pos = findLineStart(tokens, index);

        // First collect all identifiers and groups
        var parts = std.ArrayList([]const u8).init(self.allocator);
        defer parts.deinit();

        while (current_pos >= start_line_pos) : (current_pos -= 1) {
            const token = tokens[@intCast(current_pos)];

            if (token.token_type == .TKN_IDENTIFIER or
                token.token_type == .TKN_GROUP or
                token.token_type == .TKN_LOOKUP)
            {
                try parts.append(token.literal);
            } else if (token.token_type == .TKN_NEWLINE) {
                break; // Found the beginning of the line
            }
        }

        // Now reverse the parts to get the correct path order
        if (parts.items.len > 0) {
            var left: usize = 0;
            var right: usize = parts.items.len - 1;
            while (left < right) {
                const temp = parts.items[left];
                parts.items[left] = parts.items[right];
                parts.items[right] = temp;
                left += 1;
                right -= 1;
            }

            for (parts.items) |part| {
                try path.append(part);
            }
        }

        // Debug the inspection path
        std.debug.print("Inspection path: ", .{});
        for (path.items) |part| {
            std.debug.print("{s} -> ", .{part});
        }
        std.debug.print("\n", .{});

        // Create a slice that will be owned by the caller
        const result = try self.allocator.alloc([]const u8, path.items.len);
        for (path.items, 0..) |item, y| {
            result[y] = item;
        }
        return result;
    }

    // Helper function to find the start of the current line
    fn findLineStart(tokens: []ParsedToken, index: usize) isize {
        var pos: isize = @intCast(index);
        while (pos >= 0) {
            if (tokens[@intCast(pos)].token_type == .TKN_NEWLINE) {
                return pos + 1;
            }
            pos -= 1;
        }
        return 0; // Start of file
    }
};
