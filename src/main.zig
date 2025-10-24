const std = @import("std");

const cli = @import("cli.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    switch (cli.parse(&args)) {
        .usage => |usage| {
            std.debug.print("{s}\n", .{cli.usage});

            if (usage == .invalid) {
                std.process.exit(1);
            }
        },
        .check => {
            std.debug.print("TODO: check\n", .{});
        },
        .fix => {
            std.debug.print("TODO: fix\n", .{});
        },
        .set => |set| {
            std.debug.print("TODO: set '{s}' = '{s}'\n", .{ set.action, set.tag });
        },
    }
}
