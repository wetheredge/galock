const std = @import("std");

is_eof: bool = false,
r: *std.io.Reader,
w: std.io.Writer.Allocating,

pub fn init(allocator: std.mem.Allocator, r: *std.io.Reader) @This() {
    return .{ .r = r, .w = .init(allocator) };
}

pub fn deinit(self: *@This()) void {
    self.w.deinit();
}

pub fn next(self: *@This()) !?[]const u8 {
    if (self.is_eof) return null;

    _ = try self.r.streamDelimiterEnding(&self.w.writer, '\n');
    if (self.r.end == 0) {
        self.is_eof = true;
        return null;
    }

    _ = try self.r.takeByte();

    return try self.w.toOwnedSlice();
}
