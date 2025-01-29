const std = @import("std");
const fs = std.fs;
const heap = std.heap;
const process = std.process;
const time = std.time;
const clap = @import("clap");
const netdev = @import("netdev.zig");

const RED = "#FF7373";
const ORANGE = "#FFA500";

const State = enum(u8) {
    ok = 0,
    warning = 1,
    critical = 2,
    unknown = 3,
};

const Config = struct {
    unit: u8 = 'B',
    refresh_time: u32 = 1,
    interfaces: [][]const u8 = &[_][]const u8{},
    warning_rx: u64 = 0,
    warning_tx: u64 = 0,
    warning_color: []const u8 = ORANGE,
    critical_rx: u64 = 0,
    critical_tx: u64 = 0,
    critical_color: []const u8 = RED,
    use_si: bool = false,
    label: []const u8 = "",
    allocator: std.mem.Allocator = undefined,

    pub fn deinit(self: *Config) void {
        if (self.interfaces.len > 0) {
            for (self.interfaces) |iface| {
                self.allocator.free(iface);
            }
            self.allocator.free(self.interfaces);
        }
    }
};

fn display(
    writer: anytype,
    unit: u8,
    divisor: u64,
    bytes_per_sec: f64,
    warning: u64,
    critical: u64,
    warning_color: []const u8,
    critical_color: []const u8,
) !void {
    if (critical != 0 and bytes_per_sec > @as(f64, @floatFromInt(critical))) {
        try writer.print("<span fallback='true' color='{s}'>", .{critical_color});
    } else if (warning != 0 and bytes_per_sec > @as(f64, @floatFromInt(warning))) {
        try writer.print("<span fallback='true' color='{s}'>", .{warning_color});
    } else {
        try writer.print("<span fallback='true'>", .{});
    }

    var value = bytes_per_sec;
    if (unit == 'b') value *= 8;

    if (value < @as(f64, @floatFromInt(divisor))) {
        try writer.print("{d:.1} {c}/s", .{ value, unit });
    } else if (value < @as(f64, @floatFromInt(divisor * divisor))) {
        try writer.print("{d:.1}K{c}/s", .{ value / @as(f64, @floatFromInt(divisor)), unit });
    } else if (value < @as(f64, @floatFromInt(divisor * divisor * divisor))) {
        try writer.print("{d:.1}M{c}/s", .{ value / @as(f64, @floatFromInt(divisor * divisor)), unit });
    } else {
        try writer.print("{d:.1}G{c}/s", .{ value / @as(f64, @floatFromInt(divisor * divisor * divisor)), unit });
    }

    try writer.writeAll("</span>");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut();
    var config = Config{ .allocator = allocator };
    defer config.deinit();

    // Parse environment variables
    var env_map = try process.getEnvMap(allocator);
    defer env_map.deinit();

    if (env_map.get("USE_BITS")) |val| {
        if (val.len > 0 and val[0] == '1') config.unit = 'b';
    }
    if (env_map.get("USE_BYTES")) |val| {
        if (val.len > 0 and val[0] == '1') config.unit = 'B';
    }
    if (env_map.get("USE_SI")) |val| {
        if (val.len > 0 and val[0] == '1') config.use_si = true;
    }

    // Parse command line arguments and override environment variables
    // Compile-time parsing of command line arguments, very nice!
    const params = comptime clap.parseParamsComptime(
        \\-b, --bits                    use bits/s
        \\-B, --bytes                   use bytes/s (default)
        \\-t, --seconds <usize>         refresh time (default is 1)
        \\-i, --interfaces <string>     interfaces to monitor, comma separated (default all except lo)
        \\-w, --warning <string>        set warning (default orange) for Rx:Tx bandwidth
        \\-W, --warningcolor <string>   set warning color (#RRGGBB)
        \\-c, --critical <string>       set critical (default red) for Rx:Tx bandwidth
        \\-C, --criticalcolor <string>  set critical color (#RRGGBB)
        \\-s, --si                      use SI units (default is IEC)
        \\-h, --help                    print this help message
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        // Output a useful error and exit.
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    // Print help message and exit
    if (res.args.help != 0) return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    // Set bits or bytes unit
    config.unit = if (res.args.bits != 0) 'b' else 'B';

    // Set refresh time
    if (res.args.seconds) |seconds| config.refresh_time = @truncate(seconds);

    // Set interfaces delimiter , separated
    if (res.args.interfaces) |ifaces| {
        var it = std.mem.split(u8, ifaces, ",");
        var interfaces = std.ArrayList([]const u8).init(allocator);
        defer interfaces.deinit();

        while (it.next()) |iface| {
            try interfaces.append(try allocator.dupe(u8, std.mem.trim(u8, iface, " ")));
        }

        config.interfaces = try interfaces.toOwnedSlice();
    }
    if (res.args.warning) |warn_str| {
        var it = std.mem.split(u8, warn_str, ":");
        if (it.next()) |rx| {
            config.warning_rx = try std.fmt.parseInt(u64, rx, 10);
        }
        if (it.next()) |tx| {
            config.warning_tx = try std.fmt.parseInt(u64, tx, 10);
        }
    }
    if (res.args.critical) |crit_str| {
        var it = std.mem.split(u8, crit_str, ":");
        if (it.next()) |rx| {
            config.critical_rx = try std.fmt.parseInt(u64, rx, 10);
        }
        if (it.next()) |tx| {
            config.critical_tx = try std.fmt.parseInt(u64, tx, 10);
        }
    }
    config.use_si = (res.args.si != 0);
    config.warning_color = try allocator.dupe(u8, res.args.warningcolor orelse ORANGE);
    config.critical_color = try allocator.dupe(u8, res.args.criticalcolor orelse RED);

    const divisor: u64 = if (config.use_si) 1000 else 1024;

    var prev_time = std.time.timestamp();
    var prev_stats = try netdev.getValues(config.interfaces);

    while (true) {
        std.time.sleep(@as(u64, config.refresh_time) * std.time.ns_per_s);

        const current_time = std.time.timestamp();
        const current_stats = try netdev.getValues(config.interfaces);

        // Convert integer differences to floating point
        // Divide by time difference to get bytes per second
        const time_diff = @as(f64, @floatFromInt(current_time - prev_time));
        const rx = @as(f64, @floatFromInt(current_stats[0] - prev_stats[0])) / time_diff;
        const tx = @as(f64, @floatFromInt(current_stats[1] - prev_stats[1])) / time_diff;

        try stdout.writer().print("{s}", .{config.label});
        try display(stdout.writer(), config.unit, divisor, rx, config.warning_rx, config.critical_rx, config.warning_color, config.critical_color);
        try stdout.writer().writeAll(" ");
        try display(stdout.writer(), config.unit, divisor, tx, config.warning_tx, config.critical_tx, config.warning_color, config.critical_color);
        try stdout.writer().writeAll("\n");
        try stdout.flush();

        prev_time = current_time;
        prev_stats = current_stats;
    }
}
