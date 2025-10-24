const std = @import("std");

pub const usage =
    \\usage:
    \\  galock help                # print this usage
    \\  galock check               # check that all workflows match the lockfile
    \\  galock fix                 # update all workflows to match the lockfile
    \\  galock set <action> <tag>  # set the tag used for an action and update workflows
;

const Cli = union(enum) {
    usage: CommandUsage,
    check,
    fix,
    set: CommandSet,
};

const CommandUsage = enum {
    valid,
    invalid,
};

const CommandSet = struct {
    action: []const u8,
    tag: []const u8,
};

pub fn parse(args: *std.process.ArgIterator) Cli {
    _ = args.skip();

    if (args.next()) |cmd| {
        if (std.mem.eql(u8, cmd, "check")) {
            return .check;
        } else if (std.mem.eql(u8, cmd, "fix")) {
            return .fix;
        } else if (std.mem.eql(u8, cmd, "set")) {
            if (args.next()) |action| {
                if (args.next()) |tag| {
                    return .{ .set = .{ .action = action, .tag = tag } };
                }
            }
        } else if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help")) {
            return .{ .usage = .valid };
        }
    }

    return .{ .usage = .invalid };
}
