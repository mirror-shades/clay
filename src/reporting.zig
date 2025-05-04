const std = @import("std");

pub fn underline(line: []const u8, column: usize, length: usize) void {
    std.debug.print("{s}\n", .{line});
    for (0..column) |_| {
        std.debug.print(" ", .{});
    }
    for (0..length) |_| {
        std.debug.print("^", .{});
    }
    std.debug.print("\n", .{});
}
