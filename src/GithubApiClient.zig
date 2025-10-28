const std = @import("std");

allocator: std.mem.Allocator,
http: std.http.Client,
auth: ?[]const u8,

pub fn init(allocator: std.mem.Allocator, token: ?[]const u8) !@This() {
    var self: @This() = .{
        .allocator = allocator,
        .http = .{ .allocator = allocator },
        .auth = null,
    };

    if (token) |tok| {
        self.auth = try std.fmt.allocPrint(allocator, "Bearer {s}", .{tok});
    }

    try self.http.initDefaultProxies(allocator);

    return self;
}

pub fn deinit(self: *@This()) void {
    self.http.deinit();
    if (self.auth) |auth| self.allocator.free(auth);
}

pub fn getJson(
    self: *@This(),
    comptime T: type,
    path: []const []const u8,
) !?std.json.Parsed(T) {
    const url = try joinWithPrefix(u8, self.allocator, "https://api.github.com/", path, "/");
    defer self.allocator.free(url);
    std.log.debug("sending GET request to '{s}'", .{url});

    var resp = std.io.Writer.Allocating.init(self.allocator);
    defer resp.deinit();

    const result = try self.http.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .headers = .{
            .authorization = if (self.auth) |auth| .{ .override = auth } else .default,
            .user_agent = .{ .override = "wetheredge/galock" },
        },
        .extra_headers = &.{
            .{ .name = "X-GitHub-Api-Version", .value = "2022-11-28" },
        },
        .response_writer = &resp.writer,
    });

    switch (result.status) {
        .ok => {},
        .not_found => return null,
        else => return error.NotOk,
    }

    return try std.json.parseFromSlice(T, self.allocator, resp.written(), .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

fn joinWithPrefix(
    comptime T: type,
    allocator: std.mem.Allocator,
    prefix: []const T,
    strings: []const []const T,
    separator: []const T,
) ![]const T {
    var len = prefix.len;
    for (strings, 0..) |string, i| {
        if (i != 0) len += separator.len;
        len += string.len;
    }

    var buf = try allocator.alloc(u8, len);

    var offset: usize = 0;
    extend(T, &buf, &offset, prefix);
    for (strings, 0..) |string, i| {
        if (i != 0) extend(T, &buf, &offset, separator);
        extend(T, &buf, &offset, string);
    }

    return buf;
}

fn extend(
    comptime T: type,
    buf: *[]T,
    offset: *usize,
    item: []const T,
) void {
    const buf_end = offset.* + item.len;
    @memmove(buf.*[(offset.*)..buf_end], item);
    offset.* += item.len;
}
