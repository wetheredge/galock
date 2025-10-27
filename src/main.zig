const builtin = @import("builtin");
const std = @import("std");

const Regex = @import("regex").Regex;

const ActionRegex = @import("ActionRegex.zig");
const Cli = @import("Cli.zig");
const GithubIterator = @import("GithubIterator.zig");
const LineIterator = @import("LineIterator.zig");
const lockfile = @import("lockfile.zig");

const lockfile_path = ".github/galock.toml";

pub fn main() !u8 {
    var allocator_choice = Allocator.init();
    defer allocator_choice.deinit();
    const allocator = allocator_choice.allocator();

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
                return 1;
            }
        },
        .list => {
            var lock = try lockfile.fromPath(allocator, lockfile_path);
            defer lock.deinit(allocator);

            var stdout_buffer: [1024]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;

            for (lock.actions.items) |action| {
                try stdout.print("{s}@{s}\n", .{ action.repo, action.tag });
            }

            try stdout.flush();
        },
        .check => {
            var lock = try lockfile.fromPath(allocator, lockfile_path);
            defer lock.deinit(allocator);

            var re = try ActionRegex.init(allocator);
            defer re.deinit();

            var any_errors = false;
            var iter = try GithubIterator.init(std.fs.cwd(), .{});
            while (try iter.next()) |entry| {
                defer entry.file.close();

                var buf: [4096]u8 = undefined;
                var r = entry.file.reader(&buf);
                var lines = LineIterator.init(allocator, &r.interface);
                defer lines.deinit();
                var i: usize = 1;
                while (try lines.next()) |line| : (i += 1) {
                    defer allocator.free(line);

                    var maybe_captures = try re.matchLine(line);
                    if (maybe_captures) |*captures| {
                        defer captures.deinit();

                        const repo = captures.repo();

                        if (captures.revision()) |rev| {
                            std.log.debug("{s}({any}):{d}: found '{s}' @ '{s}'", .{ entry.name, entry.kind, i, repo, rev });
                        } else {
                            std.log.debug("{s}({any}):{d}: found '{s}' without revision", .{ entry.name, entry.kind, i, repo });
                        }

                        if (lock.get(repo)) |action| {
                            if (captures.revision()) |rev| {
                                if (std.mem.eql(u8, action.commit, rev)) {
                                    std.log.debug("{s}({any}):{d}: '{s}' is correct", .{ entry.name, entry.kind, i, repo });
                                    continue;
                                } else {
                                    std.log.err("{s}({any}):{d}: '{s}' is at '{s}', but should be '{s}'", .{
                                        entry.name,
                                        entry.kind,
                                        i,
                                        repo,
                                        rev,
                                        action.commit,
                                    });
                                }
                            } else {
                                std.log.err("{s}({any}):{d}: '{s}' is not pinned", .{ entry.name, entry.kind, i, repo });
                            }
                        } else {
                            std.log.err("{s}({any}):{d}: '{s}' is not in the lockfile", .{ entry.name, entry.kind, i, repo });
                        }

                        any_errors = true;
                    }
                }
            }

            if (any_errors)
                return 1;
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
        .remove => |action| {
            var lock = try lockfile.fromPath(allocator, lockfile_path);
            defer lock.deinit(allocator);

            _ = lock.remove(action);
            try lock.write();
        },
    }

    return 0;
}

const Allocator = union(enum) {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    arena: std.heap.ArenaAllocator,

    fn init() Allocator {
        return if (builtin.mode == .Debug)
            .{ .gpa = .init }
        else
            .{ .arena = .init(std.heap.page_allocator) };
    }

    fn deinit(self: *Allocator) void {
        switch (self.*) {
            .gpa => |*gpa| {
                _ = gpa.detectLeaks();
                _ = gpa.deinit();
            },
            .arena => |*arena| arena.deinit(),
        }
    }

    fn allocator(self: *Allocator) std.mem.Allocator {
        switch (self.*) {
            .gpa => |*gpa| return gpa.allocator(),
            .arena => |*arena| return arena.allocator(),
        }
    }
};
