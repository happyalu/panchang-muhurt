const std = @import("std");
const testing = std.testing;

const Timestamp = struct {
    y: i32 = 0,
    m: u4 = 0,
    d: u5 = 0,
    hh: u5 = 0,
    mm: u6 = 0,
    ss: u6 = 0,
    tz: f64 = 0,
};

pub const Time = struct {
    jd_utc: f64,
    tz: f64,

    pub fn fromTimestamp(ts: Timestamp) Time {
        const jd = getJdn(ts);

        return .{ .jd_utc = jd, .tz = ts.tz };
    }

    pub fn fromJdn(jd: f64, tz: f64) Time {
        return .{ .jd_utc = jd, .tz = tz };
    }

    pub fn jdn(self: *const @This()) f64 {
        return self.jd_utc;
    }

    pub fn dayOfWeek(self: *const @This()) u3 {
        return @intFromFloat(@mod(self.jd_utc + 1, 7));
    }

    pub fn format(self: *const Time, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        // subtract timezone (hours) to convert to local time.
        const jd_local = self.jd_utc + (self.tz / 24.0);

        const ts = getTimestamp(jd_local);

        try writer.print("{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{ ts.y, ts.m, ts.d, ts.hh, ts.mm, ts.ss });

        if (self.tz == 0.0) return;

        try writer.print("Z", .{});

        if (self.tz > 0) {
            try writer.print("+", .{});
        }

        const tz_hh: u4 = @intFromFloat(@trunc(self.tz));
        const tz_mm: u6 = @intFromFloat(@trunc(@mod(self.tz * 60, 60)));

        try writer.print("{d:0>2}:{d:0>2}", .{ tz_hh, tz_mm });
    }
};

// Reference for jdn conversion functions: https://quasar.as.utexas.edu/BillInfo/JulianDatesG.html

fn getJdn(ts: Timestamp) f64 {
    var y: f64 = @floatFromInt(ts.y);
    var m: f64 = @floatFromInt(ts.m);
    const d: f64 = @floatFromInt(ts.d);

    // January and February are taken as months of the previous year.
    if (m < 3) {
        y -= 1;
        m += 12;
    }

    const a = @floor(y / 100.0);
    const b = @floor(a / 4.0);
    const c = 2 - a + b;
    const e = @floor(365.25 * (y + 4716.0));
    const f = @floor(30.6001 * (m + 1));

    var jdn: f64 = c + d + e + f - 1524.5;

    // add fractional day
    jdn += (@as(f64, @floatFromInt(ts.hh)) + @as(f64, @floatFromInt(ts.mm)) / 60.0 + @as(f64, @floatFromInt(ts.ss)) / 3600.0) / 24.0;

    // remove timezone component.
    jdn -= (ts.tz / 24.0);

    return jdn;
}

fn getTimestamp(jd: f64) Timestamp {
    const q = jd + 0.5;
    const z = @floor(q);
    const w = @trunc((z - 1867216.25) / 36524.25);
    const x = @trunc(w / 4.0);
    const a = z + 1 + w - x;
    const b = a + 1524;
    const c = @trunc((b - 122.1) / 365.25);
    const d = @trunc(365.25 * c);
    const e = @trunc((b - d) / 30.6001);
    const f = @trunc(30.6001 * e);

    var ts = Timestamp{};
    ts.d = @intFromFloat(b - d - f + (q - z));
    ts.y = @intFromFloat(c - 4716);
    const m: u8 = @intFromFloat(e - 1);

    if (m > 12) {
        ts.m = @intCast(m - 12);
        ts.y += 1;
    } else {
        ts.m = @intCast(m);
    }

    ts.hh = @intFromFloat(@mod(q * 24, 24));
    ts.mm = @intFromFloat(@mod(q * 24 * 60, 60));
    ts.ss = @intFromFloat(@mod(q * 24 * 60 * 60, 60));

    return ts;
}

test "time" {
    const tolerance_microsecond = (1.0 / 86400.0) / 1000000.0;

    const dt1 = Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 15, .hh = 10, .mm = 45, .ss = 20, .tz = 0.0 });
    try testing.expectApproxEqRel(2460871.948148148, dt1.jdn(), tolerance_microsecond);

    const dt2 = Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 15, .hh = 10, .mm = 45, .ss = 20, .tz = 5.5 });
    try testing.expectApproxEqRel(2460871.7189814816, dt2.jdn(), tolerance_microsecond);
    try testing.expectEqual(dt2.tz, 5.5);
    try testing.expectFmt("2025-07-15T10:45:20Z+05:30", "{any}", .{dt2});

    // test january, since jdn treats that and february differently.
    const dt3 = Time.fromTimestamp(.{ .y = 2025, .m = 1, .d = 15, .hh = 10, .mm = 45, .ss = 20, .tz = 5.5 });
    try testing.expectFmt("2025-01-15T10:45:20Z+05:30", "{any}", .{dt3});
}
