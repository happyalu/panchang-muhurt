const std = @import("std");
const panchanga = @import("panchanga.zig");
const time = @import("time.zig");

pub const Span = struct {
    begin: time.Time,
    end: time.Time,
    event: Event,
};

pub const Event = union(enum) {
    wara: Wara,
    nakshatra: Nakshatra,
    tithi_karana: TithiKarana,
    yoga: Yoga,
    rashi: Rashi,
    lagna: Lagna,
    ekargala: Ekargala,

    pub fn apply(self: *const Event, p: *panchanga.Panchanga) void {
        switch (self.*) {
            inline else => |*case| return case.apply(p),
        }
    }
};

pub const Wara = struct {
    wara: panchanga.Wara,
    tithi: panchanga.Tithi,

    fn apply(self: Wara, p: *panchanga.Panchanga) void {
        p.wara = self.wara;
        p.uday_tithi = self.tithi;
    }
};

pub const Nakshatra = struct {
    nakshatra: ?panchanga.Nakshatra = null,
    vish_ghati: ?bool = null,
    ushna_ghati: ?bool = null,

    fn apply(self: *const Nakshatra, p: *panchanga.Panchanga) void {
        if (self.nakshatra) |x| p.nakshatra = x;
        if (self.vish_ghati) |x| p.nakshatra_vish_ghati = x;
        if (self.ushna_ghati) |x| p.nakshatra_ushna_ghati = x;
    }
};

pub const Ekargala = struct {
    ekargala: ?panchanga.Nakshatra = null,

    fn apply(self: *const Ekargala, p: *panchanga.Panchanga) void {
        if (self.ekargala) |e| p.ekargala = e;
    }
};

pub const TithiKarana = struct {
    tithi: panchanga.Tithi,
    karana: panchanga.Karana,

    fn apply(self: *const TithiKarana, p: *panchanga.Panchanga) void {
        p.true_tithi = self.tithi;
        p.karana = self.karana;
    }
};

pub const Yoga = struct {
    yoga: panchanga.Yoga,

    fn apply(self: *const Yoga, p: *panchanga.Panchanga) void {
        p.yoga = self.yoga;
    }
};

pub const Rashi = struct {
    chandra: ?panchanga.Rashi = null,
    surya: ?panchanga.Rashi = null,

    fn apply(self: *const Rashi, p: *panchanga.Panchanga) void {
        if (self.chandra) |x| p.chandra_rashi = x;
        if (self.surya) |x| p.surya_rashi = x;
    }
};

pub const Lagna = struct {
    rashi: panchanga.Rashi,

    fn apply(self: *const Lagna, p: *panchanga.Panchanga) void {
        p.lagna = self.rashi;
    }
};

pub fn apply(alloc: std.mem.Allocator, events: []Span, out: *std.ArrayList(panchanga.Span)) !void {
    if (events.len == 0) return;

    var times = std.AutoArrayHashMap(i64, void).init(alloc);
    defer times.deinit();

    const dt: time.Time = events[0].begin;

    for (events) |e| {
        try times.put(@as(i64, @intFromFloat(e.begin.jdn() * 86400.0)), {});
        try times.put(@as(i64, @intFromFloat(e.end.jdn() * 86400.0)), {});
    }

    const keys = times.keys();
    std.mem.sort(i64, keys, {}, std.sort.asc(i64));

    var i: usize = 0;
    while (i < keys.len - 1) : (i += 1) {
        const t1 = @as(f64, @floatFromInt(keys[i])) / 86400.0;
        const t2 = @as(f64, @floatFromInt(keys[i + 1])) / 86400.0;

        var dt1 = dt;
        dt1.jd_utc = t1;

        var dt2 = dt;
        dt2.jd_utc = t2;

        try out.append(.{
            .begin = dt1,
            .end = dt2,
            .panchanga = .{},
        });
    }

    for (out.items) |*item| {
        for (events) |e| {
            if ((std.math.approxEqAbs(f64, item.begin.jdn(), e.begin.jdn(), 1.0 / 86400.0) or item.begin.jdn() >= e.begin.jdn()) and
                (std.math.approxEqAbs(f64, item.end.jdn(), e.end.jdn(), 1.0 / 86400.0) or (item.end.jdn() <= e.end.jdn())))
            {
                e.event.apply(&item.panchanga);
            }
        }
    }
}
