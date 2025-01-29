const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const fs = std.fs;

// getValues parses /proc/net/dev and returns the total received and transmitted bytes
// for the given interfaces. If no interfaces are given, all interfaces excluding loopback
// are considered.
pub fn getValues(interfaces: []const []const u8) !struct { u64, u64 } {
    var reader = if (builtin.is_test) blk: {
        var test_fs = TestFs.init(mock_content);
        var buf_reader = std.io.bufferedReader(test_fs.reader());
        break :blk buf_reader.reader();
    } else blk: {
        const file = try fs.openFileAbsolute("/proc/net/dev", .{ .mode = .read_only });
        var buf_reader = std.io.bufferedReader(file.reader());
        break :blk buf_reader.reader();
    };

    var buf: [1024]u8 = undefined;
    var total_rx: u64 = 0;
    var total_tx: u64 = 0;

    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        //std.debug.print("Processing line: {s}\n", .{line});
        if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
            const iface = std.mem.trim(u8, line[0..colon_pos], " \t");
            if (std.mem.eql(u8, iface, "lo")) continue;

            if (interfaces.len > 0) {
                var found = false;
                for (interfaces) |target_iface| {
                    if (std.mem.eql(u8, iface, target_iface)) {
                        found = true;
                        break;
                    }
                }
                if (!found) continue;
            }

            // Split the line into fields
            var fields = std.ArrayList([]const u8).init(std.heap.page_allocator);
            defer fields.deinit();

            var stats_iter = std.mem.tokenize(u8, line[colon_pos + 1 ..], " \t");
            while (stats_iter.next()) |field| {
                try fields.append(field);
            }

            // First field is RX bytes
            if (fields.items.len > 0) {
                const rx = try std.fmt.parseInt(u64, fields.items[0], 10);
                total_rx += rx;
            }

            // TX bytes is the 9th field (index 8)
            if (fields.items.len > 8) {
                const tx = try std.fmt.parseInt(u64, fields.items[8], 10);
                total_tx += tx;
            }
        }
    }
    //std.debug.print("Final totals - RX: {d}, TX: {d}\n", .{ total_rx, total_tx });
    return .{ total_rx, total_tx };
}

// getValues parses /proc/net/dev and returns the total received and transmitted bytes
// for the given interfaces. If no interfaces are given, all interfaces excluding loopback
// are considered.
pub fn getValuesOld(interfaces: []const []const u8) !struct { u64, u64 } {
    // const file = try fs.openFileAbsolute("/proc/net/dev", .{ .mode = .read_only });
    // defer file.close();
    // var buf_reader = std.io.bufferedReader(file.reader());
    // var reader = buf_reader.reader();
    var reader = if (builtin.is_test) blk: {
        var test_fs = TestFs.init(mock_content);
        var buf_reader = std.io.bufferedReader(test_fs.reader());
        break :blk buf_reader.reader();
    } else blk: {
        const file = try fs.openFileAbsolute("/proc/net/dev", .{ .mode = .read_only });
        var buf_reader = std.io.bufferedReader(file.reader());
        break :blk buf_reader.reader();
    };

    var buf: [1024]u8 = undefined;
    var total_rx: u64 = 0;
    var total_tx: u64 = 0;

    // Format of /proc/net/dev:
    // Inter-|   Receive                                                |  Transmit
    // face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        std.debug.print("Processing line: {s}\n", .{line});

        if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
            const iface = std.mem.trim(u8, line[0..colon_pos], " \t");

            // Skip loopback
            if (std.mem.eql(u8, iface, "lo")) continue;

            // Check if interface is in our list
            if (interfaces.len > 0) {
                var found = false;
                for (interfaces) |target_iface| {
                    if (std.mem.eql(u8, iface, target_iface)) {
                        found = true;
                        break;
                    }
                }
                if (!found) continue;
            }

            var stats_iter = std.mem.tokenize(u8, line[colon_pos + 1 ..], " \t");
            if (stats_iter.next()) |rx_str| {
                total_rx += try std.fmt.parseInt(u64, rx_str, 10);
            }

            // Skip 7 fields to get to transmit bytes
            var i: usize = 0;
            while (i < 8) : (i += 1) {
                _ = stats_iter.next();
            }

            if (stats_iter.next()) |tx_str| {
                total_tx += try std.fmt.parseInt(u64, tx_str, 10);
            }
        }
    }

    std.debug.print("Final totals - RX: {d}, TX: {d}\n", .{ total_rx, total_tx });
    return .{ total_rx, total_tx };
}

// Mock data available during testing
const mock_content =
    \\Inter-|   Receive                                                |  Transmit
    \\ face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    \\    lo: 100        10    0    0    0     0          0         0   100        10    0    0    0     0       0          0
    \\  eth0: 1000       50    0    0    0     0          0         0  2000        60    0    0    0     0       0          0
    \\  eth1: 500        30    0    0    0     0          0         0  1500        40    0    0    0     0       0          0
    \\
;

const TestFs = struct {
    const Self = @This();

    contents: []const u8,
    position: usize,

    fn init(contents: []const u8) Self {
        return .{
            .contents = contents,
            .position = 0,
        };
    }

    fn reader(self: *Self) Reader {
        return .{ .context = self };
    }

    const Reader = std.io.Reader(*Self, error{}, readFn);

    fn readFn(context: *Self, buffer: []u8) error{}!usize {
        if (context.position >= context.contents.len) return 0;

        // Find either newline or end of content
        var end_pos = context.position;
        while (end_pos < context.contents.len and context.contents[end_pos] != '\n') {
            end_pos += 1;
        }
        if (end_pos < context.contents.len) end_pos += 1; // include the newline

        const size = @min(buffer.len, end_pos - context.position);
        @memcpy(buffer[0..size], context.contents[context.position..][0..size]);
        context.position += size;

        return size;
    }
};

test "getValues with specific interfaces" {
    // Test selection of specific interfaces
    {
        const interfaces = [_][]const u8{ "eth0", "eth1" };
        const result = try getValues(&interfaces);
        try testing.expectEqual(@as(u64, 1500), result[0]); // Total RX: 1000 + 500
        try testing.expectEqual(@as(u64, 3500), result[1]); // Total TX: 2000 + 1500
    }

    // Test single interface
    {
        const interfaces = [_][]const u8{"eth0"};
        const result = try getValues(&interfaces);
        try testing.expectEqual(@as(u64, 1000), result[0]);
        try testing.expectEqual(@as(u64, 2000), result[1]);
    }

    // Empty interface list
    {
        const interfaces = [_][]const u8{};
        const result = try getValues(&interfaces);
        try testing.expectEqual(@as(u64, 1500), result[0]);
        try testing.expectEqual(@as(u64, 3500), result[1]);
    }
}
