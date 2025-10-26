const std = @import("std");

const Cli = @import("Cli.zig");
const GithubIterator = @import("GithubIterator.zig");
const lockfile = @import("lockfile.zig");

const lockfile_path = ".github/galock.toml";

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const cli = Cli.parse(&args);

    if (cli.cwd) |path| {
        const dir = try std.fs.cwd().openDir(path, .{});
        try dir.setAsCwd();
    }

    switch (cli.action) {
        .usage => |usage| {
            std.debug.print("{s}\n", .{Cli.usage});

            if (usage == .invalid) {
                std.process.exit(1);
            }
        },
        .check => {
            var iter = try GithubIterator.init(std.fs.cwd(), .{});
            while (try iter.next()) |entry| {
                defer entry.file.close();
                std.debug.print("{s}: {any}\n", .{ entry.name, entry.kind });
            }
        },
        .fix => {
            std.debug.print("TODO: fix\n", .{});
        },
        .set => |set| {
            var lock = try lockfile.fromPath(allocator, lockfile_path);
            defer lock.deinit(allocator);

            _ = try lock.set(allocator, set.action, set.tag);
            try lock.write();

            // TODO: update workflows & actions
        },
    }
}
