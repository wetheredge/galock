const builtin = @import("builtin");
const std = @import("std");

const Regex = @import("regex").Regex;

const ActionRegex = @import("ActionRegex.zig");
const Cli = @import("Cli.zig");
const GithubApiClient = @import("GithubApiClient.zig");
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
        .set => |set| {
            var lock = try lockfile.fromPath(allocator, lockfile_path);
            defer lock.deinit(allocator);

            var api = try GithubApiClient.init(allocator, null);
            defer api.deinit();

            if (try resolveTag(allocator, &api, set.action, set.tag)) |commit| {
                defer allocator.free(commit);

                std.log.info("resolved {s}@{s} to commit {s}", .{ set.action, set.tag, commit });

                _ = try lock.set(allocator, set.action, set.tag, commit);
                try lock.write();

                var re = try ActionRegex.init(allocator);
                defer re.deinit();

                var iter = try GithubIterator.init(std.fs.cwd(), .{ .mode = .read_write });
                while (try iter.next()) |entry| {
                    defer entry.file.close();

                    var w = std.io.Writer.Allocating.init(allocator);
                    defer w.deinit();

                    var buf: [4096]u8 = undefined;
                    var r = entry.file.reader(&buf);
                    var lines = LineIterator.init(allocator, &r.interface);
                    defer lines.deinit();
                    var i: usize = 0;
                    while (try lines.next()) |line| : (i += 1) {
                        defer allocator.free(line);

                        if (i > 0) try w.writer.writeByte('\n');

                        var maybe_captures = try re.matchLine(line);
                        if (maybe_captures) |*captures| {
                            defer captures.deinit();

                            if (std.mem.eql(u8, captures.repo(), set.action)) {
                                std.log.debug("{s}({any}): updating line {d}", .{ entry.name, entry.kind, i });

                                var vec: [5][]const u8 = .{
                                    captures.head(),
                                    set.action,
                                    "@",
                                    commit,
                                    captures.tail(),
                                };
                                try w.writer.writeVecAll(&vec);
                                continue;
                            }
                        }

                        try w.writer.writeAll(line);
                    }

                    try entry.file.writeAll(w.writer.buffered());
                }
            } else {
                std.log.err("failed to resolve {s}@{s}", .{ set.action, set.tag });
            }
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

fn resolveTag(
    allocator: std.mem.Allocator,
    api: *GithubApiClient,
    repo: []const u8,
    tag: []const u8,
) !?[]const u8 {
    const Ref = struct {
        object: struct {
            type: []const u8,
            sha: []const u8,
        },
    };
    const Tag = Ref;

    const ref_json = try api.getJson(Ref, &.{ "repos", repo, "git/ref/tags", tag }) orelse return null;
    defer ref_json.deinit();
    const ref_obj = ref_json.value.object;

    if (std.mem.eql(u8, ref_obj.type, "commit")) {
        return try allocator.dupe(u8, ref_obj.sha);
    } else if (std.mem.eql(u8, ref_obj.type, "tag")) {
        const tag_json = try api.getJson(Tag, &.{ "repos", repo, "git/tags", ref_obj.sha }) orelse return null;
        defer tag_json.deinit();
        const tag_obj = tag_json.value.object;

        if (std.mem.eql(u8, tag_obj.type, "commit")) {
            return try allocator.dupe(u8, tag_obj.sha);
        }
    }

    std.log.err("invalid ref type when getting {s}@{s}", .{ repo, tag });
    return error.InvalidRefType;
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
