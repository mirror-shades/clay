const std = @import("std");
const ParsedToken = @import("parser.zig").ParsedToken;
const Token = @import("token.zig").Token;
const TokenKind = @import("token.zig").TokenKind;
const ValueType = @import("token.zig").ValueType;
const Value = @import("token.zig").Value;
const printError = std.debug.print;
const printDebug = std.debug.print;
const printInspect = std.debug.print;

pub const Preprocessor = struct {
    pub const Variable = struct {
        name: []const u8,
        value: Value,
        type: ValueType,
        mutable: bool,
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
                    .mutable = false,
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

        // Find the identifier by scanning the entire line up to assignment
        var identifier_found = false;

        // Find the start of the current line
        var line_start: isize = 0;
        i = @intCast(index - 1);
        while (i >= 0) {
            if (tokens[@intCast(i)].token_type == .TKN_NEWLINE) {
                line_start = i + 1;
                break;
            }
            i -= 1;
        }

        // Scan forward from start of line to assignment looking for identifier
        i = line_start;
        var identifier_pos: isize = -1;
        var is_mutable = false;

        while (i < index) : (i += 1) {
            if (tokens[@intCast(i)].token_type == .TKN_IDENTIFIER) {
                identifier_pos = i;
                // Check for muta tokens after the identifier
                var j: isize = i + 1;
                while (j < index) : (j += 1) {
                    if (tokens[@intCast(j)].token_type == .TKN_MUTA) {
                        is_mutable = true;
                    }
                    if (tokens[@intCast(j)].token_type == .TKN_VALUE_ASSIGN) {
                        break;
                    }
                }
            }
        }

        if (identifier_pos >= 0) {
            try result.append(Variable{
                .name = tokens[@intCast(identifier_pos)].literal,
                .value = Value{ .nothing = {} },
                .type = .nothing,
                .mutable = is_mutable,
            });
            identifier_found = true;
        }

        if (!identifier_found) {
            printError("Error: No identifier found before assignment at token {d}\n", .{index});
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
                .mutable = false,
            });
            value_found = true;
        }
        // Check for a regular value token
        else if (index + 1 < tokens.len and tokens[index + 1].token_type == .TKN_VALUE) {
            try result.append(Variable{
                .name = "value", // This name doesn't matter as it will be treated as value
                .value = tokens[index + 1].value,
                .type = tokens[index + 1].value_type,
                .mutable = false, // Default value for literals
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

            if (try self.getLookupValue(lookup_path)) |var_value| {
                try result.append(var_value);
                value_found = true;
            } else {
                // Instead of returning an error, append a variable with "not found" indicator
                printError("Warning: Value not found in lookup path, using default value\n", .{});
                return error.ValueNotFoundInLookupPath;
            }
        }

        // If no value was found, add a default value to ensure we have at least 2 elements
        if (!value_found) {
            printError("Warning: No value found after assignment, using default\n", .{});
            return error.NoValueFoundAfterAssignment;
        }

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
        // Extract mutability from the identifier
        const is_mutable = assignment_array[assignment_array.len - 2].mutable;
        // Everything before the identifier is groups
        const groups = assignment_array[0 .. assignment_array.len - 2];

        if (groups.len == 0) {
            // Top-level assignment

            // Check if variable already exists
            if (self.root_scope.variables.contains(identifier)) {
                const existing_var = self.root_scope.variables.get(identifier).?;

                // If variable exists and is not mutable, return error
                if (!existing_var.mutable) {
                    printError("Error: Cannot reassign immutable variable '{s}'\n", .{identifier});
                    return error.CannotReassignImmutableVariable;
                }

                // Update existing variable but keep its mutability status
                var updated_var = existing_var;
                updated_var.value = value_item.value;
                updated_var.type = value_item.type;

                try self.root_scope.variables.put(identifier, updated_var);
                return;
            }

            // New variable assignment
            const variable = Variable{
                .name = identifier,
                .value = value_item.value,
                .type = value_item.type,
                .mutable = is_mutable,
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

        // Check if variable already exists in this scope
        if (current_scope.variables.contains(identifier)) {
            const existing_var = current_scope.variables.get(identifier).?;

            // If variable exists and is not mutable, return error
            if (!existing_var.mutable) {
                printError("Error: Cannot reassign immutable variable '{s}'\n", .{identifier});
                return error.CannotReassignImmutableVariable;
            }

            // Update existing variable but keep its mutability status
            var updated_var = existing_var;
            updated_var.value = value_item.value;
            updated_var.type = value_item.type;

            try current_scope.variables.put(identifier, updated_var);
            return;
        }

        // Create new variable
        const variable = Variable{
            .name = identifier,
            .value = value_item.value,
            .type = value_item.type,
            .mutable = is_mutable,
        };

        try current_scope.variables.put(identifier, variable);
    }

    // Retrieves a value from the appropriate scope
    pub fn getLookupValue(self: *Preprocessor, path: [][]const u8) !?Variable {
        if (path.len < 1) return error.InvalidLookupPath;

        // Last element is the variable name
        const var_name = path[path.len - 1];

        // Navigate to the correct scope
        var current_scope = &self.root_scope;

        for (path[0 .. path.len - 1]) |scope_name| {
            if (!current_scope.nested_scopes.contains(scope_name)) {
                printError("Scope not found: {s}\n", .{scope_name});
                return error.ScopeNotFound; // Scope doesn't exist
            }

            current_scope = current_scope.nested_scopes.get(scope_name).?;
        }

        // Look up the variable
        const result = current_scope.variables.get(var_name);
        if (result == null) {
            printError("Variable {s} not found in scope\n", .{var_name});
            return error.VariableNotFoundInScope;
        }
        return result;
    }

    fn evaluateExpression(self: *Preprocessor, tokens: []Token) !Value {
        if (tokens.len == 0) {
            printError("Warning: Empty expression\n", .{});
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
            } else if (token.token_type == .TKN_ARROW) {
                printError("No arrow allowed in expression[{d}:{d}] {s}\n", .{ token.line_number, token.token_number, token.literal });
                return error.InvalidExpression;
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
                        printError("Warning: Variable '{s}' not found in expression, using 0\n", .{token.literal});
                        return error.VariableNotFoundInExpression;
                    }
                },
                .TKN_PLUS, .TKN_MINUS, .TKN_STAR, .TKN_SLASH, .TKN_PERCENT, .TKN_POWER => {
                    if (result_stack.items.len < 2) {
                        printError("Error: Not enough operands for operator {s}\n", .{token.literal});
                        return error.NotEnoughOperands;
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
                            printError("Warning: Non-numeric value in expression, using 0\n", .{});
                            return error.NonNumericValue;
                        },
                    }

                    switch (b) {
                        .int => |val| b_val = val,
                        .float => |val| b_val = @intFromFloat(val),
                        .string, .bool, .nothing => {
                            printError("Warning: Non-numeric value in expression, using 0\n", .{});
                            return error.NonNumericValue;
                        },
                    }

                    var result: i32 = 0;

                    switch (token.token_type) {
                        .TKN_PLUS => result = a_val + b_val,
                        .TKN_MINUS => result = a_val - b_val,
                        .TKN_STAR => result = a_val * b_val,
                        .TKN_SLASH => {
                            if (b_val == 0) {
                                printError("Error: Division by zero\n", .{});
                                return error.DivisionByZero;
                            } else {
                                result = @divTrunc(a_val, b_val);
                            }
                        },
                        .TKN_PERCENT => {
                            if (b_val == 0) {
                                printError("Error: Modulo by zero\n", .{});
                                return error.ModuloByZero;
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
            return final_result;
        } else {
            printError("Error: Empty expression result\n", .{});
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
                                modified_assignment[modified_assignment.len - 1].value = try result;
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
                            printInspect("[{d}:{d}] value  :{s} = ", .{
                                current_token.line_number,
                                current_token.token_number,
                                value_type_str,
                            });

                            // Print the value based on its type
                            switch (tokens[i - 1].value_type) {
                                .int => printInspect("{d}\n", .{tokens[i - 1].value.int}),
                                .float => printInspect("{any}\n", .{tokens[i - 1].value.float}),
                                .string => printInspect("\"{s}\"\n", .{tokens[i - 1].value.string}),
                                .bool => printInspect("{s}\n", .{if (tokens[i - 1].value.bool) "TRUE" else "FALSE"}),
                                .nothing => printInspect("(nothing)\n", .{}),
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
                                    try buffer.appendSlice("-> ");
                                }
                                try buffer.appendSlice(part);
                            }

                            path_str = try self.allocator.dupe(u8, buffer.items);
                            // Don't free yet: defer self.allocator.free(path_str);
                        } else {
                            path_str = try self.allocator.dupe(u8, "undefined");
                            // Don't free yet: defer self.allocator.free(path_str);
                        }

                        if (try self.getLookupValue(path)) |var_value| {
                            printInspect("[{d}:{d}] {s} :{s} = ", .{
                                current_token.line_number,
                                current_token.token_number,
                                path_str,
                                var_value.type.toString(),
                            });

                            switch (var_value.type) {
                                .int => printInspect("{d}\n", .{var_value.value.int}),
                                .float => printInspect("{any}\n", .{var_value.value.float}),
                                .string => printInspect("\"{s}\"\n", .{var_value.value.string}),
                                .bool => printInspect("{s}\n", .{if (var_value.value.bool) "TRUE" else "FALSE"}),
                                .nothing => printInspect("(nothing)\n", .{}),
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
