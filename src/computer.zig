const std = @import("std");
const testing = std.testing;

const panchanga = @import("panchanga.zig");
const event = @import("event.zig");
const time = @import("time.zig");

const ephemeris = @import("ephemeris/ephemeris.zig");

const ComputeOptions = struct {
    begin: time.Time,
    end: time.Time,
    lon: f64 = 0,
    lat: f64 = 0,
};

const FilterOptions = struct {
    dosha_options: panchanga.DoshaOptions = .{},
    remove_dushit: bool = false,
};

pub fn Computer(T: type) type {
    return struct {
        const Self = @This();
        alloc: std.mem.Allocator,
        eph: T,
        events: std.ArrayList(event.Span),
        spans: std.ArrayList(panchanga.Span),
        spans_buf: std.ArrayList(panchanga.Span),
        comp_opts: ComputeOptions,

        pub fn init(eph: T, alloc: std.mem.Allocator) Self {
            return .{
                .alloc = alloc,
                .eph = eph,
                .events = .init(alloc),
                .spans = .init(alloc),
                .spans_buf = .init(alloc),
                .comp_opts = .{ .begin = time.Time.fromJdn(0, 0), .end = time.Time.fromJdn(0, 0) },
            };
        }

        pub fn deinit(self: *Self) void {
            self.events.deinit();
            self.spans.deinit();
            self.spans_buf.deinit();
        }

        fn getTithi(self: Self, jd: f64) !panchanga.Tithi {
            const pos = try self.eph.getPosition(.{ .ptype = .moon_minus_sun }, jd);
            //std.debug.print("pos: {}\n", .{pos});
            const tithi: u5 = @intFromFloat(@divTrunc(pos.lon, 360.0 / 30.0));
            return @enumFromInt(tithi);
        }

        // If a date is given, we need to convert to sunrise-based timestamps.
        pub fn dateToTimestamp(self: Self, opts: ComputeOptions) !ComputeOptions {
            const sr1 = try self.eph.getNextSunrise(opts.begin.jdn(), opts.lon, opts.lat);
            const sr2 = try self.eph.getNextSunrise(opts.end.jdn(), opts.lon, opts.lat);
            const sr3 = try self.eph.getNextSunrise(sr2 + 0.5, opts.lon, opts.lat);

            var out = opts;
            out.begin = time.Time.fromJdn(sr1, opts.begin.tz);
            out.end = time.Time.fromJdn(sr3, opts.begin.tz);
            return out;
        }

        pub fn compute(self: *Self, date_opts: ComputeOptions) !void {
            const opts = try self.dateToTimestamp(date_opts);
            self.comp_opts = opts;

            self.spans.clearRetainingCapacity();
            self.events.clearRetainingCapacity();

            var wara_opts = opts;
            wara_opts.begin = time.Time.fromJdn(opts.begin.jdn() - 1.0 / 24.0, opts.begin.tz);
            wara_opts.end = time.Time.fromJdn(opts.end.jdn() + 1.0 / 24.0, opts.end.tz);

            try self.addWaraEvents(wara_opts);
            try self.addTithiKaranaEvents(opts);
            try self.addYogaEvents(opts);
            try self.addNakshatraEvents(opts);
            try self.addEkargalaEvents(opts);
            try self.addSuryaRashiEvents(opts);
            try self.addChandraRashiEvents(opts);
            try self.addLagnaEvents(opts);
            try event.apply(self.alloc, self.events.items, &self.spans);
        }

        pub fn results(self: *Self, filter_opts: FilterOptions) ![]panchanga.Span {
            self.spans_buf.clearRetainingCapacity();

            for (self.spans.items) |item| {
                //std.debug.print("{any}\n", .{item});

                if (item.end.jdn() < self.comp_opts.begin.jdn() or std.math.approxEqAbs(f64, item.end.jdn(), self.comp_opts.begin.jdn(), 1.0 / 86400.0)) {
                    continue;
                }

                //std.debug.print("{d}  -- {d}\n", .{ item.begin.jdn(), self.comp_opts.end.jdn() });

                if (item.begin.jdn() > self.comp_opts.end.jdn() or std.math.approxEqAbs(f64, item.begin.jdn(), self.comp_opts.end.jdn(), 1.0 / 86400.0)) {
                    continue;
                }

                var x = item;
                x.panchanga.computeDosha(filter_opts.dosha_options);
                const d = x.panchanga.dosha;
                //std.debug.print("{any}\n", .{x});

                var is_valid = true;

                inline for (std.meta.fields(@TypeOf(d))) |field| {
                    if (field.type == bool) {
                        const value = @field(d, field.name);
                        if (value) {
                            is_valid = false;
                            break;
                        }
                    }
                }

                if (!filter_opts.remove_dushit or is_valid) {
                    try self.spans_buf.append(x);
                }
            }
            return self.spans_buf.items;
        }

        fn addWaraEvents(self: *Self, opts: ComputeOptions) !void {
            var jd = opts.begin.jdn();
            var prev_sunrise: ?f64 = null;
            var prev_wara: panchanga.Wara = undefined;
            var prev_tithi: panchanga.Tithi = undefined;

            while (jd < opts.end.jdn()) {
                const next_sunrise = try self.eph.getNextSunrise(jd, opts.lon, opts.lat);
                if (prev_sunrise) |p| {
                    try self.events.append(.{
                        .begin = time.Time.fromJdn(p, opts.begin.tz),
                        .end = time.Time.fromJdn(next_sunrise, opts.begin.tz),
                        .event = .{ .wara = .{ .wara = prev_wara, .tithi = prev_tithi } },
                    });
                }

                prev_sunrise = next_sunrise;

                const dow = @as(u4, time.Time.fromJdn(prev_sunrise.?, 0).dayOfWeek());
                prev_wara = @enumFromInt(@mod(1 + dow, 7));
                prev_tithi = try self.getTithi(prev_sunrise.?);

                jd = next_sunrise + 0.5;

                //std.debug.print("{} {} {}\n", .{ dow, prev_tithi, prev_wara });
            }
        }

        fn addTithiKaranaEvents(self: *Self, opts: ComputeOptions) !void {
            var iter = self.eph.splitPosition(opts.begin.jdn(), opts.end.jdn(), 360.0 / 60.0, .{ .ptype = .moon_minus_sun });

            while (try iter.next()) |e| {
                //std.debug.print("{d} {d} {d}\n", .{ e.idx, e.idx / 2, 0 });
                const cur_tithi: panchanga.Tithi = @enumFromInt(@as(u5, @intFromFloat(e.idx / 2)));
                const cur_karana = panchanga.Karana.fromIdx(@as(u6, @intFromFloat(e.idx)));

                try self.events.append(
                    .{
                        .begin = time.Time.fromJdn(e.jd_start, opts.begin.tz),
                        .end = time.Time.fromJdn(e.jd_end, opts.begin.tz),
                        .event = .{ .tithi_karana = event.TithiKarana{ .tithi = cur_tithi, .karana = cur_karana } },
                    },
                );
            }
        }

        fn addYogaEvents(self: *Self, opts: ComputeOptions) !void {
            var iter = self.eph.splitPosition(opts.begin.jdn(), opts.end.jdn(), 360.0 / 27.0, .{ .ptype = .moon_plus_sun });

            while (try iter.next()) |e| {
                const cur_yoga: panchanga.Yoga = @enumFromInt(@as(u5, @intFromFloat(e.idx)));

                try self.events.append(.{
                    .begin = time.Time.fromJdn(e.jd_start, opts.begin.tz),
                    .end = time.Time.fromJdn(e.jd_end, opts.begin.tz),
                    .event = .{ .yoga = event.Yoga{ .yoga = cur_yoga } },
                });
            }
        }
        fn addNakshatraEvents(self: *Self, opts: ComputeOptions) !void {
            // For nakshatra vish/ushna ghati, we need to know full span of
            // nakshtara, therefore, begin the calculation 2 days before the
            // original start date and include the full length of the first
            // nakshatra in calculation.
            var iter = self.eph.splitPosition(opts.begin.jdn() - 2, opts.end.jdn(), 360.0 / 27.0, .{ .ptype = .moon });

            while (try iter.next()) |e| {
                const cur_nakshatra: panchanga.Nakshatra = @enumFromInt(@as(u5, @intFromFloat(e.idx)));
                if (e.jd_end < opts.begin.jdn()) continue;

                try self.events.append(.{
                    .begin = time.Time.fromJdn(e.jd_start, opts.begin.tz),
                    .end = time.Time.fromJdn(e.jd_end, opts.begin.tz),
                    .event = .{ .nakshatra = event.Nakshatra{ .nakshatra = cur_nakshatra } },
                });

                const cur_nakshatra_dur = e.jd_end - e.jd_start;
                const cur_ghati_dur = cur_nakshatra_dur / 60.0;
                const cur_ghati_map = cur_nakshatra.getGhatiBoundaries();

                {
                    const cur_vish_begin = e.jd_start + (cur_ghati_map.vish[0] * cur_ghati_dur);
                    const cur_vish_end = e.jd_start + (cur_ghati_map.vish[1] * cur_ghati_dur);
                    try self.events.append(.{
                        .begin = time.Time.fromJdn(cur_vish_begin, opts.begin.tz),
                        .end = time.Time.fromJdn(cur_vish_end, opts.begin.tz),
                        .event = .{ .nakshatra = event.Nakshatra{ .vish_ghati = true } },
                    });
                }

                {
                    const cur_ushna_begin = e.jd_start + (cur_ghati_map.ushna[0] * cur_ghati_dur);
                    const cur_ushna_end = e.jd_start + (cur_ghati_map.ushna[1] * cur_ghati_dur);
                    try self.events.append(.{
                        .begin = time.Time.fromJdn(cur_ushna_begin, opts.begin.tz),
                        .end = time.Time.fromJdn(cur_ushna_end, opts.begin.tz),
                        .event = .{ .nakshatra = event.Nakshatra{ .ushna_ghati = true } },
                    });
                }
            }
        }

        fn addEkargalaEvents(self: *Self, opts: ComputeOptions) !void {
            var iter = self.eph.splitPosition(opts.begin.jdn(), opts.end.jdn(), 360.0 / 27.0, .{ .ptype = .sun });

            while (try iter.next()) |e| {
                const sun_lon = 5 + e.idx * 360.0 / 27.0; // 5 is added because otherwise the truncated division rounds down incorrectly.
                const ekargala_lon = 360.0 - sun_lon;
                const ekargala_idx = @divTrunc(ekargala_lon, 360.0 / 27.0);

                const cur_ekargala: panchanga.Nakshatra = @enumFromInt(@as(u5, @intFromFloat(ekargala_idx)));

                try self.events.append(.{
                    .begin = time.Time.fromJdn(e.jd_start, opts.begin.tz),
                    .end = time.Time.fromJdn(e.jd_end, opts.begin.tz),
                    .event = .{ .ekargala = .{ .ekargala = cur_ekargala } },
                });
            }
        }

        fn addSuryaRashiEvents(self: *Self, opts: ComputeOptions) !void {
            var iter = self.eph.splitPosition(opts.begin.jdn(), opts.end.jdn(), 360.0 / 12.0, .{ .ptype = .sun });

            while (try iter.next()) |e| {
                const cur_rashi: panchanga.Rashi = @enumFromInt(@as(u4, @intFromFloat(e.idx)));

                try self.events.append(.{
                    .begin = time.Time.fromJdn(e.jd_start, opts.begin.tz),
                    .end = time.Time.fromJdn(e.jd_end, opts.begin.tz),
                    .event = .{ .rashi = .{ .surya = cur_rashi } },
                });
            }
        }

        fn addChandraRashiEvents(self: *Self, opts: ComputeOptions) !void {
            var iter = self.eph.splitPosition(opts.begin.jdn(), opts.end.jdn(), 360.0 / 12.0, .{ .ptype = .moon });

            while (try iter.next()) |e| {
                const cur_rashi: panchanga.Rashi = @enumFromInt(@as(u4, @intFromFloat(e.idx)));

                try self.events.append(.{
                    .begin = time.Time.fromJdn(e.jd_start, opts.begin.tz),
                    .end = time.Time.fromJdn(e.jd_end, opts.begin.tz),
                    .event = .{ .rashi = .{ .chandra = cur_rashi } },
                });
            }
        }

        fn addLagnaEvents(self: *Self, opts: ComputeOptions) !void {
            var iter = self.eph.splitPosition(opts.begin.jdn(), opts.end.jdn(), 360.0 / 12.0, .{ .ptype = .asc, .lon = opts.lon, .lat = opts.lat });

            while (try iter.next()) |e| {
                const cur_rashi: panchanga.Rashi = @enumFromInt(@as(u4, @intFromFloat(e.idx)));

                try self.events.append(.{
                    .begin = time.Time.fromJdn(e.jd_start, opts.begin.tz),
                    .end = time.Time.fromJdn(e.jd_end, opts.begin.tz),
                    .event = .{ .lagna = .{ .rashi = cur_rashi } },
                });
            }
        }
    };
}

test "wara events" {
    const eph = try ephemeris.Swe.init("");
    defer eph.deinit();
    var comp = Computer(ephemeris.Swe).init(eph, testing.allocator);
    defer comp.deinit();

    const pune_lat = 18 + 31.0 / 60.0;
    const pune_lon = 73 + 51.0 / 60.0;

    try comp.addWaraEvents(.{
        .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .tz = 5.5 }),
        .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 26, .tz = 5.5 }),
        .lon = pune_lon,
        .lat = pune_lat,
    });

    const truth = &[_]event.Span{
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 6, .mm = 13, .ss = 1, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .hh = 6, .mm = 13, .ss = 22, .tz = 5.5 }),
            .event = .{ .wara = .{ .wara = .budhawara, .tithi = .krishna_14 } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .hh = 6, .mm = 13, .ss = 22, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 25, .hh = 6, .mm = 13, .ss = 42, .tz = 5.5 }),
            .event = .{ .wara = .{ .wara = .guruwara, .tithi = .amavasya } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 25, .hh = 6, .mm = 13, .ss = 42, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 26, .hh = 6, .mm = 14, .ss = 2, .tz = 5.5 }),
            .event = .{ .wara = .{ .wara = .shukrawara, .tithi = .shukla_1 } },
        },
    };

    try testing.expectEqual(truth.len, comp.events.items.len);

    for (truth, comp.events.items) |e, a| {
        try testing.expectApproxEqRel(e.begin.jdn(), a.begin.jdn(), 1.0 / 86400.0);
        try testing.expectEqualDeep(e.event, a.event);
    }
}

test "tithi events" {
    const eph = try ephemeris.Swe.init("");
    defer eph.deinit();
    var comp = Computer(ephemeris.Swe).init(eph, testing.allocator);
    defer comp.deinit();

    try comp.addTithiKaranaEvents(.{
        .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .tz = 5.5 }),
        .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 25, .tz = 5.5 }),
    });

    //std.debug.print("{any}\n", .{comp.events.items});

    const truth = &[_]event.Span{
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 0, .mm = 0, .ss = 0, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 4, .mm = 40, .ss = 44, .tz = 5.5 }),
            .event = .{ .tithi_karana = .{ .tithi = .krishna_13, .karana = .vanija } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 4, .mm = 40, .ss = 44, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 15, .mm = 32, .ss = 56, .tz = 5.5 }),
            .event = .{ .tithi_karana = .{ .tithi = .krishna_14, .karana = .vishti } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 15, .mm = 32, .ss = 56, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .hh = 2, .mm = 29, .ss = 51, .tz = 5.5 }),
            .event = .{ .tithi_karana = .{ .tithi = .krishna_14, .karana = .shakuni } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .hh = 2, .mm = 29, .ss = 51, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .hh = 13, .mm = 32, .ss = 29, .tz = 5.5 }),
            .event = .{ .tithi_karana = .{ .tithi = .amavasya, .karana = .chatushpada } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .hh = 13, .mm = 32, .ss = 29, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 25, .hh = 0, .mm = 41, .ss = 48, .tz = 5.5 }),
            .event = .{ .tithi_karana = .{ .tithi = .amavasya, .karana = .naga } },
        },
    };

    try testing.expectEqual(truth.len, comp.events.items.len);

    for (truth, comp.events.items) |e, a| {
        try testing.expectApproxEqRel(e.begin.jdn(), a.begin.jdn(), 1.0 / 86400.0);
        try testing.expectEqualDeep(e.event, a.event);
    }
}

test "yoga events" {
    const eph = try ephemeris.Swe.init("");
    defer eph.deinit();
    var comp = Computer(ephemeris.Swe).init(eph, testing.allocator);
    defer comp.deinit();

    try comp.addYogaEvents(.{
        .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .tz = 5.5 }),
        .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 25, .tz = 5.5 }),
    });

    //std.debug.print("{any}\n", .{comp.events.items});

    const truth = &[_]event.Span{
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 0, .mm = 0, .ss = 0, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 12, .mm = 33, .ss = 34, .tz = 5.5 }),
            .event = .{ .yoga = .{ .yoga = .vyaghata } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 12, .mm = 33, .ss = 34, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .hh = 9, .mm = 50, .ss = 11, .tz = 5.5 }),
            .event = .{ .yoga = .{ .yoga = .harshana } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .hh = 9, .mm = 50, .ss = 11, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 25, .hh = 7, .mm = 27, .ss = 32, .tz = 5.5 }),
            .event = .{ .yoga = .{ .yoga = .vajra } },
        },
    };

    try testing.expectEqual(truth.len, comp.events.items.len);

    for (truth, comp.events.items) |e, a| {
        try testing.expectApproxEqRel(e.begin.jdn(), a.begin.jdn(), 1.0 / 86400.0);
        try testing.expectEqualDeep(e.event, a.event);
    }
}

test "nakshatra events" {
    const eph = try ephemeris.Swe.init("");
    defer eph.deinit();
    var comp = Computer(ephemeris.Swe).init(eph, testing.allocator);
    defer comp.deinit();

    try comp.addNakshatraEvents(.{
        .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .tz = 5.5 }),
        .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .tz = 5.5 }),
    });

    //std.debug.print("{any}\n", .{comp.events.items});

    const truth = &[_]event.Span{
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 22, .hh = 19, .mm = 24, .ss = 58, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 17, .mm = 54, .ss = 32, .tz = 5.5 }),
            .event = .{ .nakshatra = .{ .nakshatra = .ardra } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 22, .hh = 23, .mm = 32, .ss = 23, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 1, .mm = 2, .ss = 21, .tz = 5.5 }),
            .event = .{ .nakshatra = .{ .vish_ghati = true } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 3, .mm = 17, .ss = 19, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 6, .mm = 39, .ss = 45, .tz = 5.5 }),
            .event = .{ .nakshatra = .{ .ushna_ghati = true } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 17, .mm = 54, .ss = 32, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .hh = 16, .mm = 43, .ss = 52, .tz = 5.5 }),
            .event = .{ .nakshatra = .{ .nakshatra = .punarvasu } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .hh = 5, .mm = 19, .ss = 12, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 24, .hh = 6, .mm = 50, .ss = 30, .tz = 5.5 }),
            .event = .{ .nakshatra = .{ .vish_ghati = true } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 20, .mm = 45, .ss = 42, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 23, .mm = 36, .ss = 52, .tz = 5.5 }),
            .event = .{ .nakshatra = .{ .ushna_ghati = true } },
        },
    };

    try testing.expectEqual(truth.len, comp.events.items.len);

    for (truth, comp.events.items) |e, a| {
        try testing.expectApproxEqRel(e.begin.jdn(), a.begin.jdn(), 1.0 / 86400.0);
        try testing.expectEqualDeep(e.event, a.event);
    }
}

test "ekargala events" {
    const eph = try ephemeris.Swe.init("");
    defer eph.deinit();
    var comp = Computer(ephemeris.Swe).init(eph, testing.allocator);
    defer comp.deinit();

    try comp.addEkargalaEvents(.{
        .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 6, .mm = 10, .ss = 0, .tz = 5.5 }),
        .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 7, .hh = 6, .mm = 10, .ss = 0, .tz = 5.5 }),
    });

    //std.debug.print("{any}\n", .{comp.events.items});

    const truth = &[_]event.Span{
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 0, .mm = 0, .ss = 0, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 23, .hh = 12, .mm = 33, .ss = 34, .tz = 5.5 }),
            .event = .{ .ekargala = .{ .ekargala = .uttara_ashadha } },
        },
    };

    try testing.expectEqual(truth.len, comp.events.items.len);

    for (truth, comp.events.items) |e, a| {
        try testing.expectApproxEqRel(e.begin.jdn(), a.begin.jdn(), 1.0 / 86400.0);
        try testing.expectEqualDeep(e.event, a.event);
    }
}

test "surya rashi events" {
    const eph = try ephemeris.Swe.init("");
    defer eph.deinit();
    var comp = Computer(ephemeris.Swe).init(eph, testing.allocator);
    defer comp.deinit();

    try comp.addSuryaRashiEvents(.{
        .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .tz = 5.5 }),
        .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 8, .d = 7, .tz = 5.5 }),
    });

    //std.debug.print("{any}\n", .{comp.events.items});

    const truth = &[_]event.Span{
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 0, .mm = 0, .ss = 0, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 16, .hh = 17, .mm = 23, .ss = 55, .tz = 5.5 }),
            .event = .{ .rashi = .{ .surya = .gemini } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 16, .hh = 17, .mm = 23, .ss = 55, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 8, .d = 17, .hh = 1, .mm = 44, .ss = 29, .tz = 5.5 }),
            .event = .{ .rashi = .{ .surya = .cancer } },
        },
    };

    try testing.expectEqual(truth.len, comp.events.items.len);

    for (truth, comp.events.items) |e, a| {
        try testing.expectApproxEqRel(e.begin.jdn(), a.begin.jdn(), 1.0 / 86400.0);
        try testing.expectEqualDeep(e.event, a.event);
    }
}

test "chandra rashi events" {
    const eph = try ephemeris.Swe.init("");
    defer eph.deinit();
    var comp = Computer(ephemeris.Swe).init(eph, testing.allocator);
    defer comp.deinit();

    try comp.addChandraRashiEvents(.{
        .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .tz = 5.5 }),
        .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 10, .tz = 5.5 }),
    });

    //std.debug.print("{any}\n", .{comp.events.items});

    const truth = &[_]event.Span{
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 0, .mm = 0, .ss = 0, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 16, .mm = 0, .ss = 59, .tz = 5.5 }),
            .event = .{ .rashi = .{ .chandra = .libra } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 16, .mm = 0, .ss = 59, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 9, .hh = 3, .mm = 15, .ss = 16, .tz = 5.5 }),
            .event = .{ .rashi = .{ .chandra = .scorpio } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 9, .hh = 3, .mm = 15, .ss = 16, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 11, .hh = 12, .mm = 8, .ss = 40, .tz = 5.5 }),
            .event = .{ .rashi = .{ .chandra = .sagittarius } },
        },
    };

    try testing.expectEqual(truth.len, comp.events.items.len);

    for (truth, comp.events.items) |e, a| {
        try testing.expectApproxEqRel(e.begin.jdn(), a.begin.jdn(), 1.0 / 86400.0);
        try testing.expectEqualDeep(e.event, a.event);
    }
}

test "lagna events" {
    const eph = try ephemeris.Swe.init("");
    defer eph.deinit();
    var comp = Computer(ephemeris.Swe).init(eph, testing.allocator);
    defer comp.deinit();

    const pune_lat = 18 + 31.0 / 60.0;
    const pune_lon = 73 + 51.0 / 60.0;

    try comp.addLagnaEvents(.{
        .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 0, .mm = 0, .ss = 0, .tz = 5.5 }),
        .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 8, .mm = 0, .ss = 0, .tz = 5.5 }),
        .lon = pune_lon,
        .lat = pune_lat,
    });

    //std.debug.print("{any}\n", .{comp.events.items});

    const truth = &[_]event.Span{
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 0, .mm = 0, .ss = 0, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 0, .mm = 18, .ss = 22, .tz = 5.5 }),
            .event = .{ .lagna = .{ .rashi = .pisces } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 0, .mm = 18, .ss = 22, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 2, .mm = 19, .ss = 40, .tz = 5.5 }),
            .event = .{ .lagna = .{ .rashi = .aries } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 2, .mm = 19, .ss = 40, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 4, .mm = 12, .ss = 2, .tz = 5.5 }),
            .event = .{ .lagna = .{ .rashi = .taurus } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 4, .mm = 12, .ss = 2, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 6, .mm = 2, .ss = 40, .tz = 5.5 }),
            .event = .{ .lagna = .{ .rashi = .gemini } },
        },
        .{
            .begin = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 6, .mm = 2, .ss = 40, .tz = 5.5 }),
            .end = time.Time.fromTimestamp(.{ .y = 2025, .m = 7, .d = 6, .hh = 8, .mm = 0, .ss = 2, .tz = 5.5 }),
            .event = .{ .lagna = .{ .rashi = .cancer } },
        },
    };

    try testing.expectEqual(truth.len, comp.events.items.len);

    for (truth, comp.events.items) |e, a| {
        try testing.expectApproxEqRel(e.begin.jdn(), a.begin.jdn(), 1.0 / 86400.0);
        try testing.expectEqualDeep(e.event, a.event);
    }
}
