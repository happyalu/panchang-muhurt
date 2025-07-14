const std = @import("std");
const testing = std.testing;

const time = @import("time.zig");

pub const Rashi = enum {
    aries,
    taurus,
    gemini,
    cancer,
    leo,
    virgo,
    libra,
    scorpio,
    sagittarius,
    capricorn,
    aquarius,
    pisces,

    pub fn swabhav(self: Rashi) RashiSwabhav {
        return switch (self) {
            .aries, .cancer, .libra, .capricorn => RashiSwabhav.char,
            .taurus, .leo, .scorpio, .aquarius => RashiSwabhav.sthir,
            .gemini, .virgo, .sagittarius, .pisces => RashiSwabhav.dvi,
        };
    }
};

pub const RashiSwabhav = enum { char, sthir, dvi };

pub const Tithi = enum {
    shukla_1,
    shukla_2,
    shukla_3,
    shukla_4,
    shukla_5,
    shukla_6,
    shukla_7,
    shukla_8,
    shukla_9,
    shukla_10,
    shukla_11,
    shukla_12,
    shukla_13,
    shukla_14,
    pournima,
    krishna_1,
    krishna_2,
    krishna_3,
    krishna_4,
    krishna_5,
    krishna_6,
    krishna_7,
    krishna_8,
    krishna_9,
    krishna_10,
    krishna_11,
    krishna_12,
    krishna_13,
    krishna_14,
    amavasya,
};

pub const Nakshatra = enum {
    ashwini,
    bharani,
    krittika,
    rohini,
    mrigashira,
    ardra,
    punarvasu,
    pushya,
    ashlesha,
    magha,
    purva_phalguni,
    uttara_phalguni,
    hasta,
    chitra,
    swati,
    vishaka,
    anuradha,
    jyeshtha,
    mool,
    purva_ashadha,
    uttara_ashadha,
    shravana,
    dhanishtha,
    shatabisha,
    purva_bhadrapada,
    uttara_bhadrapada,
    revati,

    pub fn getGhatiBoundaries(self: Nakshatra) struct { vish: [2]f64, ushna: [2]f64 } {
        const ghati_array = [_]@TypeOf(getGhatiBoundaries(self)){
            .{ .vish = .{ 50, 54 }, .ushna = .{ 7.5, 15 } }, // 1
            .{ .vish = .{ 24, 28 }, .ushna = .{ 55, 60 } }, // 2
            .{ .vish = .{ 30, 34 }, .ushna = .{ 21, 30 } }, // 3
            .{ .vish = .{ 40, 44 }, .ushna = .{ 7.5, 15 } }, // 4
            .{ .vish = .{ 14, 18 }, .ushna = .{ 55, 60 } }, // 5
            .{ .vish = .{ 11, 15 }, .ushna = .{ 21, 30 } }, // 6
            .{ .vish = .{ 30, 34 }, .ushna = .{ 7.5, 15 } }, // 7
            .{ .vish = .{ 20, 24 }, .ushna = .{ 55, 60 } }, // 8
            .{ .vish = .{ 32, 36 }, .ushna = .{ 21, 30 } }, // 9
            .{ .vish = .{ 30, 34 }, .ushna = .{ 7.5, 15 } }, // 10
            .{ .vish = .{ 20, 24 }, .ushna = .{ 55, 60 } }, // 11
            .{ .vish = .{ 18, 22 }, .ushna = .{ 21, 30 } }, // 12
            .{ .vish = .{ 22, 26 }, .ushna = .{ 7.5, 15 } }, // 13
            .{ .vish = .{ 20, 24 }, .ushna = .{ 55, 60 } }, // 14
            .{ .vish = .{ 14, 18 }, .ushna = .{ 21, 30 } }, // 15
            .{ .vish = .{ 14, 18 }, .ushna = .{ 1, 8 } }, // 16
            .{ .vish = .{ 10, 14 }, .ushna = .{ 52, 60 } }, // 17
            .{ .vish = .{ 14, 18 }, .ushna = .{ 20, 30 } }, // 18
            .{ .vish = .{ 20, 24 }, .ushna = .{ 1, 8 } }, // 19
            .{ .vish = .{ 24, 28 }, .ushna = .{ 52, 60 } }, // 20
            .{ .vish = .{ 20, 24 }, .ushna = .{ 20, 30 } }, // 21
            .{ .vish = .{ 10, 14 }, .ushna = .{ 1, 8 } }, // 22
            .{ .vish = .{ 10, 14 }, .ushna = .{ 52, 60 } }, // 23
            .{ .vish = .{ 18, 22 }, .ushna = .{ 20, 30 } }, // 24
            .{ .vish = .{ 16, 20 }, .ushna = .{ 1, 8 } }, // 25
            .{ .vish = .{ 24, 28 }, .ushna = .{ 52, 60 } }, // 26
            .{ .vish = .{ 30, 34 }, .ushna = .{ 20, 30 } }, // 27
        };

        return ghati_array[@intFromEnum(self)];
    }
};

pub const Yoga = enum {
    vishkambha,
    preeti,
    ayushman,
    saubhagya,
    shobhana,
    atiganda,
    sukarma,
    dhriti,
    shoola,
    ganda,
    vriddhi,
    dhruva,
    vyaghata,
    harshana,
    vajra,
    siddhi,
    vyatipata,
    variyan,
    parigha,
    shiva,
    siddha,
    sadhya,
    shubha,
    shukla,
    brahma,
    indra,
    vaidhriti,
};

pub const Karana = enum {
    bava,
    balava,
    kaulava,
    taitila,
    gara,
    vanija,
    vishti,
    shakuni,
    chatushpada,
    naga,
    kimstughna,

    // There are 60 Karana for the 0--360 moon-sun difference. Based on this index, identify the Karana.
    pub fn fromIdx(idx: u6) Karana {
        switch (idx) {
            57 => return Karana.shakuni,
            58 => return Karana.chatushpada,
            59 => return Karana.naga,
            0 => return Karana.kimstughna,
            else => {},
        }

        return @enumFromInt((idx - 1) % 7);
    }
};

test "karana" {
    try testing.expectEqual(Karana.kimstughna, Karana.fromIdx(0));
    try testing.expectEqual(Karana.balava, Karana.fromIdx(9));
    try testing.expectEqual(Karana.kaulava, Karana.fromIdx(24));
    try testing.expectEqual(Karana.vishti, Karana.fromIdx(28));
    try testing.expectEqual(Karana.taitila, Karana.fromIdx(46));
    try testing.expectEqual(Karana.taitila, Karana.fromIdx(53));
    try testing.expectEqual(Karana.vishti, Karana.fromIdx(56));
}

pub const Wara = enum {
    raviwara,
    somawara,
    mangalawara,
    budhawara,
    guruwara,
    shukrawara,
    shaniwara,
};

pub const Panchanga = struct {
    uday_tithi: Tithi = .shukla_1,
    nakshatra: Nakshatra = .ashwini,
    yoga: Yoga = .vishkambha,
    karana: Karana = .bava,
    wara: Wara = .raviwara,

    true_tithi: Tithi = .shukla_1,

    nakshatra_vish_ghati: bool = false,
    nakshatra_ushna_ghati: bool = false,

    lagna: Rashi = .aries,
    chandra_rashi: Rashi = .aries,

    surya_rashi: Rashi = .aries,
    ekargala: Nakshatra = .ashwini,

    dosha: Dosha = .{},

    pub fn computeDosha(self: *Panchanga, options: DoshaOptions) void {
        self.dosha = .{};

        if (options.no_krakach_yoga) {
            const t: u5 = @intFromEnum(self.uday_tithi);
            const w: u4 = @intFromEnum(self.wara);
            if ((t % 15) + w + 2 == 13) self.dosha.krakacha_yoga = true;
        }

        if (options.no_rikta_tithi) {
            if ((self.uday_tithi == .amavasya) or (@mod(@as(u5, @intFromEnum(self.uday_tithi)) + 1, 5) == 4)) self.dosha.rikta_tithi = true;
        }

        if (options.no_sthir_karan) {
            switch (self.karana) {
                .kimstughna, .naga, .chatushpada, .shakuni => self.dosha.sthir_karana = true,
                else => {},
            }
        }

        if (options.no_vishti_karan) {
            if (self.karana == .vishti) self.dosha.vishti_karana = true;
        }

        {
            const n_idx: u6 = @intFromEnum(self.nakshatra);
            for (options.good_tarabala_for) |natal| {
                const natal_idx: u5 = @intFromEnum(natal);
                switch (@mod(n_idx + 27 - natal_idx, 9)) {
                    0, 2, 4, 6 => self.dosha.bad_tarabala = true,
                    else => {},
                }
            }
        }

        {
            for (options.prohibited_nakshatra) |n| {
                if (self.nakshatra == n) {
                    self.dosha.prohibited_nakshatra = true;
                }
            }
        }

        // chandrabala computation
        {
            var houses = std.bit_set.IntegerBitSet(12).initEmpty();
            for (options.bad_chandrabala_houses) |h| {
                houses.set(h - 1);
            }

            const r_idx: u5 = @intFromEnum(self.chandra_rashi);
            for (options.good_chandrabala_for) |natal| {
                const natal_idx: u5 = @intFromEnum(natal);
                const diff = @mod(r_idx + 12 - natal_idx, 12);
                //std.debug.print("{} {} {} {}\n", .{ houses, natal_idx, r_idx, diff });
                if (houses.isSet(diff)) self.dosha.bad_chandrabala = true;
            }
        }

        if (options.no_nakshatra_ushna_ghati) self.dosha.nakshatra_ushna_ghati = self.nakshatra_ushna_ghati;
        if (options.no_nakshatra_vish_ghati) self.dosha.nakshatra_vish_ghati = self.nakshatra_vish_ghati;

        if (options.no_sthir_lagna and self.lagna.swabhav() == .sthir) self.dosha.bad_lagna = true;
        if (options.no_chara_lagna and self.lagna.swabhav() == .char) self.dosha.bad_lagna = true;
        if (options.no_dvi_lagna and self.lagna.swabhav() == .dvi) self.dosha.bad_lagna = true;

        if (options.sun_not_in_jup_sign and (self.surya_rashi == .sagittarius or self.surya_rashi == .pisces)) self.dosha.sun_in_jup_sign = true;

        if (options.no_ekargala) {
            const n1 = @as(u6, @intFromEnum(self.ekargala));
            const n2 = @as(u6, @intFromEnum(self.nakshatra));

            switch (@mod(27 + n2 - n1, 27)) {
                0, 1, 6, 9, 13, 15, 17, 19, 20 => self.dosha.ekargala = true,
                else => {},
            }
        }
    }
};

const Dosha = packed struct {
    krakacha_yoga: bool = false,
    rikta_tithi: bool = false,
    sthir_karana: bool = false,
    vishti_karana: bool = false,
    bad_tarabala: bool = false,
    prohibited_nakshatra: bool = false,
    bad_chandrabala: bool = false,
    nakshatra_vish_ghati: bool = false,
    nakshatra_ushna_ghati: bool = false,
    sun_in_jup_sign: bool = false,
    bad_lagna: bool = false,
    ekargala: bool = false,
};

pub const DoshaOptions = struct {
    no_krakach_yoga: bool = false,
    no_rikta_tithi: bool = false,
    no_sthir_karan: bool = false,
    no_vishti_karan: bool = false,

    good_tarabala_for: []const Nakshatra = &[_]Nakshatra{},
    prohibited_nakshatra: []const Nakshatra = &[_]Nakshatra{},
    no_nakshatra_vish_ghati: bool = false,
    no_nakshatra_ushna_ghati: bool = false,

    good_chandrabala_for: []const Rashi = &[_]Rashi{},
    bad_chandrabala_houses: []const u4 = &[_]u4{ 4, 8, 12 },

    no_sthir_lagna: bool = false,
    no_chara_lagna: bool = false,
    no_dvi_lagna: bool = false,
    sun_not_in_jup_sign: bool = false,

    no_ekargala: bool = false,
};

test "panchanga dosha" {
    var p = Panchanga{};

    {
        p.wara = .somawara;
        p.uday_tithi = .krishna_11;
        p.computeDosha(.{ .no_krakach_yoga = true });
        try testing.expect(p.dosha.krakacha_yoga);

        p.wara = .shaniwara;
        p.uday_tithi = .shukla_6;
        p.computeDosha(.{ .no_krakach_yoga = true });
        try testing.expect(p.dosha.krakacha_yoga);
    }

    {
        p.uday_tithi = .shukla_9;
        p.computeDosha(.{ .no_rikta_tithi = true });
        try testing.expect(p.dosha.rikta_tithi);
    }

    {
        p.karana = .shakuni;
        p.computeDosha(.{ .no_sthir_karan = true });
        try testing.expect(p.dosha.sthir_karana);
    }

    {
        p.karana = .vishti;
        p.computeDosha(.{ .no_vishti_karan = true });
        try testing.expect(p.dosha.vishti_karana);
    }

    {
        p.nakshatra = .vishaka;
        const bad_list = [_]Nakshatra{ .ashwini, .krittika, .mrigashira, .punarvasu, .magha, .uttara_phalguni, .chitra, .vishaka, .mool, .uttara_ashadha, .dhanishtha, .purva_bhadrapada };
        const good_list = [_]Nakshatra{ .bharani, .rohini, .ardra, .pushya, .ashlesha, .purva_phalguni, .hasta, .swati, .anuradha, .jyeshtha, .purva_ashadha, .shravana, .shatabisha, .uttara_bhadrapada, .revati };

        for (bad_list) |bad| {
            p.computeDosha(.{ .good_tarabala_for = &[_]Nakshatra{bad} });
            try testing.expect(p.dosha.bad_tarabala);
        }
        for (good_list) |good| {
            p.computeDosha(.{ .good_tarabala_for = &[_]Nakshatra{good} });
            try testing.expect(!p.dosha.bad_tarabala);
        }
    }

    {
        p.chandra_rashi = .pisces;
        const bad_list = [_]Rashi{ .aries, .leo, .sagittarius };
        const good_list = [_]Rashi{ .taurus, .gemini, .cancer, .virgo, .libra, .scorpio, .capricorn, .aquarius, .pisces };

        for (bad_list) |bad| {
            p.computeDosha(.{ .good_chandrabala_for = &[_]Rashi{bad} });
            try testing.expect(p.dosha.bad_chandrabala);
        }
        for (good_list) |good| {
            p.computeDosha(.{ .good_chandrabala_for = &[_]Rashi{good} });
            try testing.expect(!p.dosha.bad_tarabala);
        }
    }

    {
        p.ekargala = .uttara_ashadha;

        const bad_list = [_]Nakshatra{ .krittika, .punarvasu, .ashlesha, .purva_phalguni, .hasta, .chitra, .uttara_ashadha, .shravana, .revati };
        const good_list = [_]Nakshatra{ .ashwini, .bharani, .rohini, .mrigashira, .ardra, .pushya, .magha, .uttara_phalguni, .swati, .vishaka, .anuradha, .jyeshtha, .mool, .purva_ashadha, .dhanishtha, .shatabisha, .purva_bhadrapada, .uttara_bhadrapada };

        for (bad_list) |bad| {
            p.nakshatra = bad;
            p.computeDosha(.{ .no_ekargala = true });
            try testing.expect(p.dosha.ekargala);
        }

        for (good_list) |good| {
            p.nakshatra = good;
            p.computeDosha(.{ .no_ekargala = true });
            try testing.expect(!p.dosha.ekargala);
        }
    }
}

pub const Span = struct {
    begin: time.Time,
    end: time.Time,
    panchanga: Panchanga,
};
