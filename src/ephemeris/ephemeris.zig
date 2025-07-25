const std = @import("std");
const testing = std.testing;
const time = @import("../time.zig");

pub const Planet = enum { sun, mercury, venus, mars, jupiter, saturn, moon, rahu, ketu };
pub const Position = struct { lon: f64, speed: f64 };
const lon_precision = 1.0 / 3600000.00;

const PositionType = enum {
    asc,
    moon,
    sun,
    moon_minus_sun,
    moon_plus_sun,

    fn averageSpeed(self: PositionType) f64 {
        return switch (self) {
            .moon => 13.1766,
            .sun => 0.9855,
            .moon_minus_sun => 12.1911,
            .moon_plus_sun => 14.1621,
            .asc => 360.0,
        };
    }
};

const PositionContext = struct { ptype: PositionType, lat: f64 = 0, lon: f64 = 0 };

pub const Swe = Ephemeris(@import("swisseph.zig").Swe);

fn circularDifference(angle1: f64, angle2: f64) f64 {
    return @mod(angle1 - angle2 + 540.0, 360.0) - 180.0;
}

pub fn Ephemeris(comptime T: type) type {
    return struct {
        inner: T,

        const Self = @This();

        pub fn TypeOf(_: Self) type {
            return T;
        }

        pub fn init(args: anytype) !@This() {
            return .{ .inner = try T.init(args) };
        }

        pub fn deinit(self: Self) void {
            return self.inner.deinit();
        }

        pub fn isMoshierFallback(self: Self) bool {
            return self.inner.isMoshierFallback();
        }

        pub fn getNextSunrise(self: Self, jd_start: f64, lon: f64, lat: f64) !f64 {
            return self.inner.calcNextSunrise(jd_start, lon, lat);
        }

        pub fn getPlanetPosition(self: Self, planet: Planet, jd: f64) !Position {
            return self.inner.getPlanetPosition(planet, jd);
        }

        pub fn getAscendantPosition(self: Self, lon: f64, lat: f64, jd: f64) !Position {
            return self.inner.getAscendantPosition(lon, lat, jd);
        }

        pub fn getPosition(self: Self, ctx: PositionContext, jd: f64) !Position {
            switch (ctx.ptype) {
                .moon => return self.getPlanetPosition(.moon, jd),
                .sun => return self.getPlanetPosition(.sun, jd),
                .moon_minus_sun => {
                    const m = try self.getPlanetPosition(.moon, jd);
                    const s = try self.getPlanetPosition(.sun, jd);
                    const p = Position{ .lon = @mod(m.lon - s.lon, 360), .speed = m.speed - s.speed };
                    return p;
                },
                .moon_plus_sun => {
                    const m = try self.getPlanetPosition(.moon, jd);
                    const s = try self.getPlanetPosition(.sun, jd);
                    const p = Position{ .lon = @mod(m.lon + s.lon, 360), .speed = m.speed + s.speed };
                    return p;
                },
                .asc => {
                    return self.getAscendantPosition(ctx.lon, ctx.lat, jd);
                },
            }
        }

        pub fn getCrossing(self: Self, cross_lon: f64, jd_start: f64, ctx: PositionContext) !f64 {
            // get the current position and iteratively find the time for next crossing.
            var jd = jd_start;
            var pos = try self.getPosition(ctx, jd);
            var diff = circularDifference(cross_lon, pos.lon);
            var speed = ctx.ptype.averageSpeed();

            if (diff < 0) diff += 360;

            //std.debug.print("pos: {d}  lon: {d}  diff: {d}\n", .{ pos.lon, cross_lon, diff });
            var iters: i32 = 0;
            while (!std.math.approxEqAbs(f64, diff, 0, lon_precision)) : (iters += 1) {
                if (iters > 1000) return error.CalcFailure;
                // the current speed is pos.speed, and we need to cover a distance of diff; therefore time taken would be t = dist/speed
                const t = (diff / speed);
                jd += t;
                pos = try self.getPosition(ctx, jd);
                diff = circularDifference(cross_lon, pos.lon);
                speed = pos.speed;
                //std.debug.print("jd: {d} diff: {d} t: {d} pos: {d} speed:{d}\n", .{ jd, diff, t, pos.lon, pos.speed });
            }
            return jd;
        }

        // Provide an iterator that returns the time of next crossing with span boundary
        pub fn splitPosition(self: Self, jd_start: f64, jd_stop: f64, span: f64, ctx: PositionContext) PositionSpanIterator(Self) {
            return .{
                .eph = self,
                .prev_jd = jd_start,
                .stop_jd = jd_stop,
                .span = span,
                .ctx = ctx,
            };
        }
    };
}

const PositionSpan = struct { idx: f64, jd_start: f64, jd_end: f64 };

fn PositionSpanIterator(T: type) type {
    return struct {
        eph: T,
        stop_jd: f64,
        prev_jd: f64,
        prev_val: ?f64 = null,
        prev_idx: f64 = 0,
        span: f64,
        ctx: PositionContext,

        pub fn next(self: *PositionSpanIterator(T)) !?PositionSpan {
            if (self.prev_jd > self.stop_jd) return null;

            if (self.prev_val == null) {
                const p = try self.eph.getPosition(self.ctx, self.prev_jd);
                self.prev_val = p.lon;
                self.prev_idx = @mod(@divTrunc(p.lon, self.span), 360.0 / self.span);
            }

            const next_val = @mod((1.0 + self.prev_idx) * self.span, 360);
            //std.debug.print("seeking value {d}\n", .{next_val});

            const p = try self.eph.getCrossing(next_val, self.prev_jd, self.ctx);

            defer {
                self.prev_jd = p;
                self.prev_val = next_val;
                self.prev_idx += 1;
            }

            return .{ .idx = @mod(self.prev_idx, 360.0 / self.span), .jd_start = self.prev_jd, .jd_end = p };
        }
    };
}

test "getCrossing" {
    const x = try Swe.init("");
    defer x.deinit();
    const t = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .tz = 5.5 });
    const jd = t.jdn();

    const pune_lat = 18 + 31.0 / 60.0;
    const pune_lon = 73 + 51.0 / 60.0;

    var buf: [255]u8 = undefined;

    try testing.expectEqualStrings("2025-07-26T15:52:19Z+05:30", try std.fmt.bufPrint(&buf, "{s}", .{time.Time.fromJdn(try x.getCrossing(120, jd, .{ .ptype = .moon }), 5.5)}));
    try testing.expectEqualStrings("2025-08-17T01:44:29Z+05:30", try std.fmt.bufPrint(&buf, "{s}", .{time.Time.fromJdn(try x.getCrossing(120, jd, .{ .ptype = .sun }), 5.5)}));
    try testing.expectEqualStrings("2025-08-04T11:42:55Z+05:30", try std.fmt.bufPrint(&buf, "{s}", .{time.Time.fromJdn(try x.getCrossing(120, jd, .{ .ptype = .moon_minus_sun }), 5.5)}));
    try testing.expectEqualStrings("2025-08-14T13:11:39Z+05:30", try std.fmt.bufPrint(&buf, "{s}", .{time.Time.fromJdn(try x.getCrossing(120, jd, .{ .ptype = .moon_plus_sun }), 5.5)}));
    try testing.expectEqualStrings("2025-07-23T07:57:57Z+05:30", try std.fmt.bufPrint(&buf, "{s}", .{time.Time.fromJdn(try x.getCrossing(120, jd, .{ .ptype = .asc, .lat = pune_lat, .lon = pune_lon }), 5.5)}));

    try testing.expectEqualStrings("2025-08-14T09:06:04Z+05:30", try std.fmt.bufPrint(&buf, "{s}", .{time.Time.fromJdn(try x.getCrossing(0, jd, .{ .ptype = .moon }), 5.5)}));
    try testing.expectEqualStrings("2026-04-14T09:24:18Z+05:30", try std.fmt.bufPrint(&buf, "{s}", .{time.Time.fromJdn(try x.getCrossing(0, jd, .{ .ptype = .sun }), 5.5)}));
    try testing.expectEqualStrings("2025-07-25T00:41:48Z+05:30", try std.fmt.bufPrint(&buf, "{s}", .{time.Time.fromJdn(try x.getCrossing(0, jd, .{ .ptype = .moon_minus_sun }), 5.5)}));
    try testing.expectEqualStrings("2025-08-06T07:17:00Z+05:30", try std.fmt.bufPrint(&buf, "{s}", .{time.Time.fromJdn(try x.getCrossing(0, jd, .{ .ptype = .moon_plus_sun }), 5.5)}));
    try testing.expectEqualStrings("2025-07-23T23:44:38Z+05:30", try std.fmt.bufPrint(&buf, "{s}", .{time.Time.fromJdn(try x.getCrossing(0, jd, .{ .ptype = .asc, .lat = pune_lat, .lon = pune_lon }), 5.5)}));
}

test "split position" {
    const x = try Swe.init("");
    defer x.deinit();
    const t = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .tz = 5.5 });
    const jd = t.jdn();

    // Find the karana for next 3 days

    const truth = &[_]PositionSpan{
        .{ .idx = 55, .jd_start = 2460879.2708333335, .jd_end = 2460879.4657932227 },
        .{ .idx = 56, .jd_start = 2460879.4657932227, .jd_end = 2460879.9187042895 },
        .{ .idx = 57, .jd_start = 2460879.9187042895, .jd_end = 2460880.3749009036 },
        .{ .idx = 58, .jd_start = 2460880.3749009036, .jd_end = 2460880.8350659553 },
        .{ .idx = 59, .jd_start = 2460880.8350659553, .jd_end = 2460881.299868836 },
        .{ .idx = 0, .jd_start = 2460881.299868836, .jd_end = 2460881.7699494716 },
        .{ .idx = 1, .jd_start = 2460881.7699494716, .jd_end = 2460882.2459005318 },
        .{ .idx = 2, .jd_start = 2460882.2459005318, .jd_end = 2460882.728247857 },
    };

    var iter = x.splitPosition(jd, jd + 3, 360.0 / 60.0, .{ .ptype = .moon_minus_sun });
    var idx: u32 = 0;
    while (try iter.next()) |p| : (idx += 1) {
        try testing.expectEqualDeep(truth[idx], p);
        //std.debug.print(".idx = {d}, .jd_start={d}, .jd_end={d}\n", .{ p.idx, p.jd_start, p.jd_end });
    }
    try testing.expectEqual(8, idx);
}
