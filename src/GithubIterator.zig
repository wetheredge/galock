const std = @import("std");
const Dir = std.fs.Dir;
const File = std.fs.File;

open: File.OpenFlags,
actions: ?DirIter,
workflows: ?DirIter,

pub const Entry = struct {
    file: File,
    kind: EntryKind,
    name: []const u8,
};

pub const EntryKind = enum {
    action,
    workflow,
};

pub fn init(root: Dir, open: File.OpenFlags) Dir.OpenError!@This() {
    const github = try root.openDir(".github", .{});
    return .{
        .open = open,
        .actions = try .init(github, "actions"),
        .workflows = try .init(github, "workflows"),
    };
}

pub fn next(self: *@This()) !?Entry {
    if (self.actions) |*actions| {
        while (try actions.iter.next()) |entry| {
            if (entry.kind != .directory) continue;
            const dir = try actions.dir.openDir(entry.name, .{});

            const file = dir.openFile("action.yaml", self.open) catch |err|
                if (err == error.FileNotFound)
                    try dir.openFile("action.yml", self.open)
                else
                    return err;

            return .{
                .file = file,
                .kind = .action,
                .name = entry.name,
            };
        }
    }

    if (self.workflows) |*workflows| {
        while (try workflows.iter.next()) |entry| {
            if (entry.kind != .file) continue;

            return .{
                .file = try workflows.dir.openFile(entry.name, self.open),
                .kind = .workflow,
                .name = entry.name,
            };
        }
    }

    return null;
}

const DirIter = struct {
    dir: Dir,
    iter: Dir.Iterator,

    fn init(parent: Dir, sub_path: []const u8) Dir.OpenError!?@This() {
        const dir = parent.openDir(sub_path, .{ .iterate = true }) catch |err|
            if (err == error.FileNotFound) {
                return null;
            } else {
                return err;
            };

        return .{ .dir = dir, .iter = dir.iterate() };
    }
};
