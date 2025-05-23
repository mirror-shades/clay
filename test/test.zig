const std = @import("std");
const testing = std.testing;
const process = std.process;
const fs = std.fs;

fn runParaCommand(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const child_allocator = arena.allocator();

    // Verify test file exists and print contents
    const file = fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Failed to open test file {s}: {}\n", .{ path, err });
        return error.FileNotFound;
    };
    defer file.close();

    const file_contents = try file.readToEndAlloc(child_allocator, std.math.maxInt(usize));
    defer child_allocator.free(file_contents);

    // Get the path to the para executable
    const exe_path = try fs.path.join(allocator, &[_][]const u8{ "zig-out", "bin", "para.exe" });
    defer allocator.free(exe_path);

    var child = process.Child.init(&[_][]const u8{ exe_path, path }, child_allocator);
    child.cwd = ".";
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    const stdout = try child.stdout.?.reader().readAllAlloc(child_allocator, std.math.maxInt(usize));
    const term = try child.wait();

    if (term.Exited != 0) {
        return error.CommandFailed;
    }

    return try allocator.dupe(u8, stdout);
}

test "basic variable assignment" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Run the para command on our test file
    const output = try runParaCommand(allocator, "./test/build-checks/variable_assign.para");
    defer allocator.free(output);

    const outputs = try parseOutput(output, allocator);

    // Test the parsed values
    try testing.expectEqualStrings("int_assign", outputs.items[0].name);
    try testing.expectEqualStrings("int", outputs.items[0].type);
    try testing.expectEqualStrings("5", outputs.items[0].value);

    try testing.expectEqualStrings("expression_assign", outputs.items[1].name);
    try testing.expectEqualStrings("int", outputs.items[1].type);
    try testing.expectEqualStrings("10", outputs.items[1].value);

    try testing.expectEqualStrings("float_assign", outputs.items[2].name);
    try testing.expectEqualStrings("float", outputs.items[2].type);
    try testing.expectEqualStrings("5.5e0", outputs.items[2].value);

    try testing.expectEqualStrings("bool_assign", outputs.items[3].name);
    try testing.expectEqualStrings("bool", outputs.items[3].type);
    try testing.expectEqualStrings("TRUE", outputs.items[3].value);

    try testing.expectEqualStrings("string_assign", outputs.items[4].name);
    try testing.expectEqualStrings("string", outputs.items[4].type);
    try testing.expectEqualStrings("\"hello\"", outputs.items[4].value);
}

test "Group assignments" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const output = try runParaCommand(allocator, "./test/build-checks/groupings.para");
    defer allocator.free(output);

    const outputs = try parseOutput(output, allocator);

    try testing.expectEqualStrings("person-> age", outputs.items[0].name);
    try testing.expectEqualStrings("int", outputs.items[0].type);
    try testing.expectEqualStrings("50", outputs.items[0].value);

    try testing.expectEqualStrings("person-> job-> salary", outputs.items[1].name);
    try testing.expectEqualStrings("int", outputs.items[1].type);
    try testing.expectEqualStrings("50000", outputs.items[1].value);

    try testing.expectEqualStrings("newPersonAge", outputs.items[2].name);
    try testing.expectEqualStrings("int", outputs.items[2].type);
    try testing.expectEqualStrings("50", outputs.items[2].value);
}

test "big file" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const output = try runParaCommand(allocator, "./test/build-checks/big_file.para");
    defer allocator.free(output);

    const outputs = try parseOutput(output, allocator);

    try testing.expectEqualStrings("person-> age", outputs.items[0].name);
    try testing.expectEqualStrings("int", outputs.items[0].type);
    try testing.expectEqualStrings("51", outputs.items[0].value);

    try testing.expectEqualStrings("person-> job-> title", outputs.items[1].name);
    try testing.expectEqualStrings("string", outputs.items[1].type);
    try testing.expectEqualStrings("\"Painter\"", outputs.items[1].value);

    try testing.expectEqualStrings("person-> job-> salary", outputs.items[2].name);
    try testing.expectEqualStrings("float", outputs.items[2].type);
    try testing.expectEqualStrings("7e4", outputs.items[2].value);

    try testing.expectEqualStrings("person-> name", outputs.items[3].name);
    try testing.expectEqualStrings("string", outputs.items[3].type);
    try testing.expectEqualStrings("\"Bob\"", outputs.items[3].value);

    try testing.expectEqualStrings("person-> working", outputs.items[4].name);
    try testing.expectEqualStrings("bool", outputs.items[4].type);
    try testing.expectEqualStrings("TRUE", outputs.items[4].value);

    try testing.expectEqualStrings("y", outputs.items[5].name);
    try testing.expectEqualStrings("float", outputs.items[5].type);
    try testing.expectEqualStrings("7e4", outputs.items[5].value);

    try testing.expectEqualStrings("value", outputs.items[6].name);
    try testing.expectEqualStrings("int", outputs.items[6].type);
    try testing.expectEqualStrings("5", outputs.items[6].value);
}

const Output = struct {
    name: []const u8,
    type: []const u8,
    value: []const u8,
};

fn parseOutput(output: []const u8, allocator: std.mem.Allocator) !std.ArrayList(Output) {
    var outputs = std.ArrayList(Output).init(allocator);
    var toParse = output;
    while (toParse.len > 0) {
        // First get everything after the ]
        const after_bracket = grabBetween(toParse, "]", "\n");
        if (after_bracket.len == 0) break;

        // Now parse the parts
        const name = std.mem.trim(u8, grabBetween(after_bracket, " ", ":"), &std.ascii.whitespace);
        const typ = std.mem.trim(u8, grabBetween(after_bracket, ":", "="), &std.ascii.whitespace);
        const value = std.mem.trim(u8, grabBetween(after_bracket, "=", "\n"), &std.ascii.whitespace);

        outputs.append(Output{ .name = name, .type = typ, .value = value }) catch unreachable;

        // Find the next line by looking for the next [
        const next_line = std.mem.indexOf(u8, toParse, "\n[") orelse break;
        toParse = toParse[next_line + 1 ..];
    }
    return outputs;
}

fn grabBetween(output: []const u8, start: []const u8, end: []const u8) []const u8 {
    const start_index = std.mem.indexOf(u8, output, start) orelse return "";
    const end_index = std.mem.indexOf(u8, output[start_index + start.len ..], end) orelse {
        // If no end marker found, return everything after start to end of string
        return output[start_index + start.len ..];
    };
    return output[start_index + start.len .. start_index + start.len + end_index];
}
