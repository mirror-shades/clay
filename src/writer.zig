const std = @import("std");
const ParsedToken = @import("parser.zig").ParsedToken;
const Preprocessor = @import("prepro.zig").Preprocessor;
const Value = @import("token.zig").Value;
const ValueType = @import("token.zig").ValueType;

pub fn writeFlatFile(tokens: []ParsedToken) !void {
    var file = try std.fs.cwd().createFile("build/output.f.para", .{});
    defer file.close();

    var writer = file.writer();
    var new_line_needed: bool = false;
    for (tokens) |token| {
        if (token.token_type == .TKN_NEWLINE) {
            if (new_line_needed == true) {
                try writer.writeAll("\n");
                new_line_needed = false;
            }
            continue;
        }
        new_line_needed = true;

        switch (token.token_type) {
            .TKN_GROUP => {
                try writer.print("{s}-> ", .{token.literal});
            },
            .TKN_TYPE => {
                try writer.print(":{s} ", .{token.literal});
            },
            .TKN_VALUE => {
                switch (token.value_type) {
                    .string => {
                        try writer.print("\"{s}\" ", .{token.value.string});
                    },
                    .bool => {
                        try writer.print("{s} ", .{if (token.value.bool) "TRUE" else "FALSE"});
                    },
                    .int => {
                        try writer.print("{d} ", .{token.value.int});
                    },
                    .float => {
                        try writer.print("{d} ", .{token.value.float});
                    },
                    .nothing => {
                        try writer.writeAll("(nothing) ");
                    },
                }
            },
            .TKN_VALUE_ASSIGN, .TKN_MUTA, .TKN_TEMP, .TKN_INSPECT, .TKN_IDENTIFIER, .TKN_PLUS, .TKN_LOOKUP, .TKN_EXPRESSION, .TKN_MINUS, .TKN_STAR, .TKN_SLASH, .TKN_PERCENT, .TKN_POWER, .TKN_LPAREN, .TKN_RPAREN, .TKN_COMMA, .TKN_LBRACKET, .TKN_RBRACKET => {
                try writer.print("{s} ", .{token.literal});
            },
            else => try writer.print("UNUSED TOKEN ENCOUNTERED:  {s} \n", .{token.literal}),
        }
    }
}

// Writes a baked down version of the file with lookups replaced by their actual values
pub fn writeBakedFile(tokens: []ParsedToken, preprocessor: *Preprocessor, allocator: std.mem.Allocator) !void {
    var file = try std.fs.cwd().createFile("build/output.f.para", .{});
    defer file.close();

    var writer = file.writer();

    std.debug.print("Writing baked file\n", .{});

    // Create a buffered writer for better performance
    var i: usize = 0;
    var current_line_scopes = std.ArrayList([]const u8).init(allocator);
    defer current_line_scopes.deinit();

    // Track if the current line contains a temp identifier
    var current_line_identifier: ?[]const u8 = null;
    var skip_current_line: bool = false;
    var line_start_index: usize = 0;

    while (i < tokens.len) {
        const current_token = tokens[i];

        // If we hit a newline, reset for the next line
        if (current_token.token_type == .TKN_NEWLINE) {
            // Only write a newline if we're not skipping the current line
            if (!skip_current_line) {
                try writer.print("\n", .{});
            }

            // Reset for next line
            current_line_scopes.clearRetainingCapacity();
            current_line_identifier = null;
            skip_current_line = false;
            line_start_index = i + 1;
            i += 1;
            continue;
        }

        // Check for identifiers at the start of a statement
        if (current_token.token_type == .TKN_IDENTIFIER) {
            // Track the current line's main identifier
            if (current_line_identifier == null) {
                current_line_identifier = current_token.literal;

                // Check if this identifier is temporary in the preprocessor
                const path = try findFullPath(current_token.literal, tokens, line_start_index, i, allocator);
                defer allocator.free(path);

                if (try preprocessor.getLookupValue(path)) |variable| {
                    // If the variable is marked as temp, skip this line
                    if (variable.temp) {
                        skip_current_line = true;
                    }
                }

                // Also check if the token itself is marked temp
                if (current_token.temp) {
                    skip_current_line = true;
                }
            }
        }

        // Skip printing this token if we're skipping the current line
        if (skip_current_line) {
            i += 1;
            continue;
        }

        // If not skipping, print the token
        switch (current_token.token_type) {
            .TKN_GROUP => {
                try current_line_scopes.append(current_token.literal);
                try writer.print("{s}-> ", .{current_token.literal});
            },
            .TKN_IDENTIFIER => {
                try writer.print("{s} ", .{current_token.literal});
            },
            .TKN_TYPE => {
                try writer.print(":{s} ", .{current_token.literal});
            },
            .TKN_VALUE_ASSIGN => {
                try writer.print("= ", .{});

                // If next token is a lookup, resolve it and write the value
                if (i + 1 < tokens.len and (tokens[i + 1].token_type == .TKN_IDENTIFIER or
                    tokens[i + 1].token_type == .TKN_GROUP or
                    tokens[i + 1].token_type == .TKN_LOOKUP))
                {
                    // This is a variable lookup
                    const lookup_path = try preprocessor.buildLookupPathForward(tokens, i + 1);
                    defer allocator.free(lookup_path);

                    if (preprocessor.getLookupValue(lookup_path)) |var_value| {
                        // Found the lookup value - write it directly
                        switch (var_value.type) {
                            .int => try writer.print("{d}", .{var_value.value.int}),
                            .float => try writer.print("{d:.2}", .{var_value.value.float}),
                            .string => try writer.print("\"{s}\"", .{var_value.value.string}),
                            .bool => try writer.print("{s}", .{if (var_value.value.bool) "TRUE" else "FALSE"}),
                            .nothing => try writer.print("UNDEFINED", .{}),
                        }

                        // Skip over the tokens used in the lookup
                        const skip_count: usize = lookup_path.len;
                        i += skip_count;
                    } else {
                        try writer.print("UNUSED TOKEN ENCOUNTERED: ", .{});
                        // Just write the first token (we can't resolve it anyway)
                        try writer.print(" {s}", .{tokens[i + 1].literal});
                        i += 1;
                    }
                }
            },
            .TKN_VALUE => {
                // Write literal value
                switch (current_token.value_type) {
                    .int => try writer.print("{d}", .{current_token.value.int}),
                    .float => try writer.print("{d:.2}", .{current_token.value.float}),
                    .string => try writer.print("\"{s}\"", .{current_token.value.string}),
                    .bool => try writer.print("{s}", .{if (current_token.value.bool) "TRUE" else "FALSE"}),
                    .nothing => try writer.print("UNDEFINED", .{}),
                }
            },
            .TKN_INSPECT => {
                try writer.print("? ", .{});
            },
            .TKN_LOOKUP => {
                try writer.print("{s} ", .{current_token.literal});
            },
            else => {},
        }

        i += 1;
    }
}

// Helper function to find the full path of an identifier
fn findFullPath(identifier: []const u8, tokens: []ParsedToken, line_start: usize, pos: usize, allocator: std.mem.Allocator) ![][]const u8 {
    var path = std.ArrayList([]const u8).init(allocator);
    defer path.deinit();

    // Add any scope prefixes
    for (tokens[line_start..pos]) |token| {
        if (token.token_type == .TKN_GROUP) {
            try path.append(token.literal);
        }
    }

    // Add the identifier itself
    try path.append(identifier);

    // Create the return array
    var result = try allocator.alloc([]const u8, path.items.len);
    for (path.items, 0..) |item, idx| {
        result[idx] = item;
    }

    return result;
}

// Writes a file with the final variable state from all scopes
pub fn writeVariableState(preprocessor: *Preprocessor, file_path: []const u8, allocator: std.mem.Allocator) !void {
    const base_name = std.fs.path.basename(file_path);
    const output_path = try std.fmt.allocPrint(allocator, "build/{s}", .{base_name});
    defer allocator.free(output_path);

    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    // Create a buffered writer for better performance
    var buffered_writer = std.io.bufferedWriter(output_file.writer());
    const writer = buffered_writer.writer();

    // Use the preprocessor's dumpVariables function to output all variables
    try preprocessor.dumpVariables(writer, allocator);

    // Flush the remaining buffered data
    try buffered_writer.flush();
}
