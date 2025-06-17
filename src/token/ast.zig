const std = @import("std");
const token = @import("token.zig");

pub const NodeType = enum {
    Program,
    Variable,
    Group,
    Reference,
};

pub const Node = struct {
    type: NodeType,
    name: []const u8,
    value: ?token.Value = null,
    value_type: ?token.ValueType = null,
    is_const: bool = false,
    children: ?std.ArrayList(*Node) = null,
    parent: ?*Node = null,

    pub fn init(allocator: std.mem.Allocator, node_type: NodeType, name: []const u8) !*Node {
        var node = try allocator.create(Node);
        node.* = .{
            .type = node_type,
            .name = name,
        };
        if (node_type == .Group) {
            node.children = std.ArrayList(*Node).init(allocator);
        }
        return node;
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        if (self.children) |*children| {
            for (children.items) |child| {
                child.deinit(allocator);
            }
            children.deinit();
        }
        allocator.destroy(self);
    }
};
