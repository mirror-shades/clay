const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const process = std.process;
const fs = std.fs;
const printf = std.debug.print;

fn print(comptime format: []const u8) void {
    printf(format, .{});
}

// update this when adding tests
const TEST_TOTAL = 3;

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

// Test result tracking
const TestResult = struct {
    name: []const u8,
    passed: bool,
    duration_ms: u64,
    error_msg: ?[]const u8 = null,
};

const TestRunner = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(TestResult),
    total_tests: u32 = 0,
    passed_tests: u32 = 0,
    start_time: i64,

    fn init(allocator: std.mem.Allocator) TestRunner {
        return TestRunner{
            .allocator = allocator,
            .results = std.ArrayList(TestResult).init(allocator),
            .start_time = std.time.milliTimestamp(),
        };
    }

    fn deinit(self: *TestRunner) void {
        for (self.results.items) |result| {
            if (result.error_msg) |msg| {
                self.allocator.free(msg);
            }
        }
        self.results.deinit();
    }

    fn runTest(self: *TestRunner, name: []const u8, test_fn: fn (std.mem.Allocator) anyerror!void) void {
        self.total_tests += 1;
        const test_start = std.time.milliTimestamp();

        printf("[{d}/{d}] Running: {s}... \t", .{ self.total_tests, 3, name }); // Update 3 to total when you know it

        const result = test_fn(self.allocator);
        const duration = @as(u64, @intCast(std.time.milliTimestamp() - test_start));

        if (result) {
            printf("✅ PASSED ({d}ms)\n", .{duration});
            self.passed_tests += 1;
            self.results.append(TestResult{
                .name = name,
                .passed = true,
                .duration_ms = duration,
            }) catch {};
        } else |err| {
            const error_msg = std.fmt.allocPrint(self.allocator, "{}", .{err}) catch "Unknown error";
            printf("❌ FAILED ({d}ms) - {s}\n", .{ duration, error_msg });
            self.results.append(TestResult{
                .name = name,
                .passed = false,
                .duration_ms = duration,
                .error_msg = error_msg,
            }) catch {};
        }
    }

    fn generateReport(self: *TestRunner) void {
        const total_duration = @as(u64, @intCast(std.time.milliTimestamp() - self.start_time));

        print("\n" ++ "=" ** 50 ++ "\n");
        print("TEST REPORT\n");
        print("=" ** 50 ++ "\n");
        printf("Total tests: {d}\n", .{self.total_tests});
        printf("Passed: {d}\n", .{self.passed_tests});
        printf("Failed: {d}\n", .{self.total_tests - self.passed_tests});
        printf("Total time: {d}ms\n", .{total_duration});
        print("\n");

        if (self.passed_tests == self.total_tests) {
            print("\n🎉 All tests passed!\n");
        } else {
            printf("\n💥 {d} test(s) failed!\n", .{self.total_tests - self.passed_tests});
        }
    }
};

// Convert to regular functions (no test keyword)
fn testBasicVariableAssignment(allocator: std.mem.Allocator) !void {
    const output = try runParaCommand(allocator, "./test/build-checks/variable_assign.para");
    defer allocator.free(output);

    const outputs = try parseOutput(output, allocator);

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

fn testGroupAssignments(allocator: std.mem.Allocator) !void {
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

fn testBigFile(allocator: std.mem.Allocator) !void {
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

// Single test function that Zig will run
test "para language tests" {
    // Set UTF-8 console output on Windows
    if (builtin.os.tag == .windows) {
        _ = std.os.windows.kernel32.SetConsoleOutputCP(65001); // UTF-8
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    print("\n🚀 Starting Para Language Test Suite\n");
    print("=" ** 50 ++ "\n");

    var runner = TestRunner.init(allocator);
    defer runner.deinit();

    // Run tests in whatever order/loop you want
    runner.runTest("Variable Assignment", testBasicVariableAssignment);
    runner.runTest("Group Assignments", testGroupAssignments);
    runner.runTest("Big File Processing", testBigFile);

    // Generate the report
    runner.generateReport();

    // Fail the overall test if any individual test failed
    if (runner.passed_tests != runner.total_tests) {
        return error.TestsFailed;
    }
}
