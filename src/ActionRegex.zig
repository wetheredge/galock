const std = @import("std");

const regex = @import("regex");
const Regex = regex.Regex;

re: Regex,

pub fn init(allocator: std.mem.Allocator) !@This() {
    const raw =
        \\^[^#]*\buses:\s*([\w-_]+/[\w-_]+)(@([\w-_./]+\b))?[\s#]
    ;
    return .{ .re = try Regex.compile(allocator, raw) };
}

pub fn deinit(self: *@This()) void {
    self.re.deinit();
}

pub fn matchLine(self: *@This(), line: []const u8) !?Captures {
    return if (try self.re.captures(line)) |captures|
        .{ .captures = captures }
    else
        null;
}

pub const Captures = struct {
    captures: regex.Captures,

    pub fn repo(self: *const @This()) []const u8 {
        return self.captures.sliceAt(1).?;
    }

    pub fn revision(self: *const @This()) ?[]const u8 {
        return self.captures.sliceAt(3);
    }
};
