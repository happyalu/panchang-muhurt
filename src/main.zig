const panchang_html = @embedFile("ui/panchang.html");

var panchang_window: webui = undefined;
var muhurt_window: webui = undefined;

var alloc: std.mem.Allocator = undefined;

var binary_path_buf: [255]u8 = undefined;
var binary_path: []const u8 = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        _ = gpa.deinit();
    }

    alloc = gpa.allocator();

    const exe_path = try std.fs.selfExeDirPathAlloc(alloc);
    const ephe_path = try std.fs.path.join(alloc, &[_][]const u8{ exe_path, "ephe" });
    std.mem.copyForwards(u8, &binary_path_buf, ephe_path);
    binary_path = binary_path_buf[0..ephe_path.len];
    alloc.free(exe_path);
    alloc.free(ephe_path);

    panchang_window = webui.newWindow();
    muhurt_window = webui.newWindow();

    var win = webui.newWindow();
    _ = try win.binding("getPanchanga", getPanchanga);
    _ = try win.binding("isSwiephAvailable", isSwiephAvailable);
    //_ = try win.showBrowser(panchang_html, .AnyBrowser);
    _ = try win.show(panchang_html);

    //std.debug.print("{d}\n", .{try webui.getPort(win)});

    webui.wait();
}

fn isSwiephAvailable(e: *webui.Event) void {
    const eph = ephemeris.Swe.init(binary_path) catch {
        return e.returnBool(false);
    };
    defer eph.deinit();
    e.returnBool(!eph.isMoshierFallback());
}

const UserInput = struct {
    lat: f64,
    lon: f64,
    start_date: []const u8,
    end_date: []const u8,
    tz: f64,
    max_results: u32,
    mode: u1,
    filters: panchanga.DoshaOptions,
};

fn getPanchangaWrapped(input_json: [:0]const u8, sb: anytype) !void {
    //std.debug.print("{s}\n", .{input_json});
    const input = try std.json.parseFromSlice(UserInput, alloc, input_json, .{});
    defer input.deinit();

    const date_str = input.value.start_date;
    var parts = std.mem.splitAny(u8, date_str, "-");
    const year_str = parts.next() orelse return;
    const month_str = parts.next() orelse return;
    const day_str = parts.next() orelse return;

    const year = try std.fmt.parseInt(i32, year_str, 10);
    const month = try std.fmt.parseInt(u4, month_str, 10);
    const day = try std.fmt.parseInt(u5, day_str, 10);

    const d1 = time.Time.fromTimestamp(.{ .y = year, .m = month, .d = day, .tz = input.value.tz });

    const eph = try ephemeris.Swe.init(binary_path);
    defer eph.deinit();

    var comp = computer.Computer(ephemeris.Swe).init(eph, alloc);
    defer comp.deinit();

    if (input.value.mode == 0) {
        try comp.compute(.{ .begin = d1, .end = d1, .lat = input.value.lat, .lon = input.value.lon });
        const p = try comp.results(.{ .remove_dushit = false, .dosha_options = input.value.filters });
        try std.json.stringify(.{ .data = p, .err = false }, .{}, sb);
        try sb.writeByte(0);
        return;
    }

    const end_date_str = input.value.end_date;
    parts = std.mem.splitAny(u8, end_date_str, "-");
    const end_year_str = parts.next() orelse return;
    const end_month_str = parts.next() orelse return;
    const end_day_str = parts.next() orelse return;

    const end_year = try std.fmt.parseInt(i32, end_year_str, 10);
    const end_month = try std.fmt.parseInt(u4, end_month_str, 10);
    const end_day = try std.fmt.parseInt(u5, end_day_str, 10);

    const d2 = time.Time.fromTimestamp(.{ .y = end_year, .m = end_month, .d = end_day, .tz = input.value.tz });

    var s = d1;
    var e = d2;
    if (s.jdn() > e.jdn()) {
        s = d2;
        e = d1;
    }

    try comp.compute(.{ .begin = s, .end = e, .lat = input.value.lat, .lon = input.value.lon });
    const p = try comp.results(.{ .remove_dushit = true, .dosha_options = input.value.filters });

    try std.json.stringify(.{ .data = p, .err = false }, .{}, sb);
    try sb.writeByte(0);
}

fn getPanchanga(e: *webui.Event, input_json: [:0]const u8) void {
    var string = std.ArrayList(u8).init(alloc);
    defer string.deinit();

    getPanchangaWrapped(input_json, string.writer()) catch {
        //std.debug.print("{any}", .{err});
        e.returnString("{\"err\": true}");
        return;
    };

    e.returnString(string.items[0 .. string.items.len - 1 :0]);
}

const std = @import("std");
const panchanga = @import("panchanga.zig");
const ephemeris = @import("ephemeris/ephemeris.zig");
const time = @import("time.zig");
const computer = @import("computer.zig");
const webui = @import("webui");
