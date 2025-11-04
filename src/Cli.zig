const std = @import("std");

cwd: ?[]const u8,
action: Action,

pub const usage =
    \\usage:
    \\  galock [options] help                # print this usage
    \\  galock [options] list [--json]       # list all actions in the lockfile and their tags
    \\  galock [options] check               # check that all workflows match the lockfile
    \\  galock [options] set <action> <tag>  # set the tag used for an action and update workflows
    \\  galock [options] rm <action> <tag>   # remove an action from the lockfile
    \\
    \\options:
    \\  --cwd <path>  # set the working directory
;

const Action = union(enum) {
    usage: CommandUsage,
    list: Format,
    check,
    set: CommandSet,
    remove: []const u8,
};

const CommandUsage = enum {
    valid,
    invalid,
};

const Format = enum {
    human,
    json,
};

const CommandSet = struct {
    action: []const u8,
    tag: []const u8,
};

pub fn parse(args: *std.process.ArgIterator) @This() {
    _ = args.skip();

    var pargs = PeekableArgs{ .iter = args, .peeked = null };

    var cli = @This(){
        .cwd = null,
        .action = .{ .usage = .invalid },
    };

    if (pargs.peek()) |token| {
        if (std.mem.startsWith(u8, token, "--")) {
            pargs.consume();

            var arg: []const u8 = token[2..];
            var value: ?[]const u8 = null;

            if (std.mem.indexOf(u8, arg, "=")) |equal| {
                value = arg[(equal + 1)..];
                arg = arg[0..equal];
            } else {
                value = pargs.next();
            }

            if (std.mem.eql(u8, arg, "cwd")) {
                cli.cwd = value;
            } else {
                return cli;
            }
        }
    }

    if (pargs.next()) |cmd| {
        if (std.mem.eql(u8, cmd, "check")) {
            cli.action = .check;
        } else if (std.mem.eql(u8, cmd, "list")) {
            if (pargs.next()) |format| {
                if (std.mem.eql(u8, format, "--json")) {
                    cli.action = .{ .list = .json };
                }
            } else {
                cli.action = .{ .list = .human };
            }
        } else if (std.mem.eql(u8, cmd, "set")) {
            if (pargs.next()) |action| {
                if (pargs.next()) |tag| {
                    cli.action = .{ .set = .{ .action = action, .tag = tag } };
                }
            }
        } else if (std.mem.eql(u8, cmd, "rm")) {
            if (pargs.next()) |action| {
                cli.action = .{ .remove = action };
            }
        } else if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help")) {
            cli.action.usage = .valid;
        }
    }

    return cli;
}

const PeekableArgs = struct {
    iter: *std.process.ArgIterator,
    peeked: ?[:0]const u8,

    fn next(self: *PeekableArgs) ?[:0]const u8 {
        if (self.peeked) |peeked| {
            self.peeked = null;
            return peeked;
        }

        return self.iter.next();
    }

    fn peek(self: *PeekableArgs) ?[:0]const u8 {
        if (self.peeked == null) {
            self.peeked = self.iter.next();
        }

        return self.peeked;
    }

    fn consume(self: *PeekableArgs) void {
        self.peeked = null;
    }
};
