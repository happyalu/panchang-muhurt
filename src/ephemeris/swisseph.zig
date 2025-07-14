// This provides zig bindings to some functions of Swiss Ephemeris.

const std = @import("std");
const testing = std.testing;

const c = @cImport({
    @cInclude("swephexp.h");
});

const ephemeris = @import("ephemeris.zig");

const SweErr = error{
    Unknown,
    CalcFailure,
};

const planet_map = blk: {
    var map: [@typeInfo(ephemeris.Planet).@"enum".fields.len]c_int = undefined;
    map[
        @intFromEnum(ephemeris.Planet.sun)
    ] = c.SE_SUN;
    map[
        @intFromEnum(ephemeris.Planet.mercury)
    ] = c.SE_MERCURY;
    map[
        @intFromEnum(ephemeris.Planet.venus)
    ] = c.SE_VENUS;
    map[
        @intFromEnum(ephemeris.Planet.mars)
    ] = c.SE_MARS;
    map[
        @intFromEnum(ephemeris.Planet.jupiter)
    ] = c.SE_JUPITER;
    map[
        @intFromEnum(ephemeris.Planet.saturn)
    ] = c.SE_SATURN;
    map[
        @intFromEnum(ephemeris.Planet.moon)
    ] = c.SE_MOON;
    map[
        @intFromEnum(ephemeris.Planet.rahu)
    ] = c.SE_MEAN_NODE;
    map[
        @intFromEnum(ephemeris.Planet.ketu)
    ] = c.SE_MEAN_NODE;

    break :blk map;
};

pub const Swe = struct {
    is_swieph_available: bool,
    iflags: c_int,

    pub fn init(ephe_path: []const u8) !@This() {
        // set path to the ephemeris files and initialize swieph.
        var buf = [_]u8{0} ** c.AS_MAXCH;
        const ephe_path_z = try std.fmt.bufPrintZ(&buf, "{s}", .{ephe_path});
        c.swe_set_ephe_path(ephe_path_z);

        // set sidereal mode with Lahiri Ayanamsh
        const reference_epoch = 0;
        const initial_ayanamsh = 0;
        c.swe_set_sid_mode(c.SE_SIDM_LAHIRI, reference_epoch, initial_ayanamsh);

        // check if swieph is available
        var result: [6]f64 = undefined;
        var errmsg: [c.AS_MAXCH]u8 = undefined;
        var iflags = c.SEFLG_SWIEPH | c.SEFLG_SIDEREAL;
        const ignore_param = 0;
        const retcode = c.swe_calc_ut(ignore_param, c.SE_MOON, iflags, result[0..], &errmsg);
        const is_swieph_available = retcode > 0 and (retcode & iflags != 0);

        if (!is_swieph_available) iflags = c.SEFLG_MOSEPH | c.SEFLG_SIDEREAL;

        return .{
            .is_swieph_available = is_swieph_available,
            .iflags = iflags,
        };
    }

    pub fn deinit(_: *const @This()) void {
        c.swe_close();
    }

    pub fn isMoshierFallback(self: *const @This()) bool {
        return !self.is_swieph_available;
    }

    pub fn calcNextSunrise(self: *const @This(), jd_start: f64, lon: f64, lat: f64) !f64 {
        var jd_sunrise: f64 = 0;

        var lon_lat = [3]f64{ lon, lat, 0 };
        var errmsg: [c.AS_MAXCH]u8 = undefined;

        const ignore_param = 0;
        const retcode = c.swe_rise_trans(jd_start, c.SE_SUN, null, self.iflags, c.SE_CALC_RISE | c.SE_BIT_HINDU_RISING, lon_lat[0..].ptr, ignore_param, ignore_param, &jd_sunrise, &errmsg);

        if (retcode == 0) return jd_sunrise;
        return SweErr.CalcFailure;
    }

    pub fn getPlanetPosition(self: *const @This(), planet: ephemeris.Planet, jd: f64) !ephemeris.Position {
        const p = planet_map[@intFromEnum(planet)];

        var result: [6]f64 = undefined;
        var errmsg: [c.AS_MAXCH]u8 = undefined;
        const retcode = c.swe_calc_ut(jd, p, self.iflags | c.SEFLG_SPEED | c.SEFLG_TRUEPOS | c.SE_BIT_NO_REFRACTION, result[0..], &errmsg);
        if (retcode < 0) {
            return SweErr.CalcFailure;
        }

        if (planet == .ketu) {
            result[0] = @mod(180.0 + result[0], 360);
        }

        return .{ .lon = result[0], .speed = result[3] };
    }

    pub fn getAscendantPosition(self: *const @This(), lon: f64, lat: f64, jd: f64) !ephemeris.Position {
        var cusps: [13]f64 = undefined;
        var cusps_speed: [13]f64 = undefined;
        var ascmc: [10]f64 = undefined;
        var ascmc_speed: [10]f64 = undefined;
        var errmsg: [c.AS_MAXCH]u8 = undefined;

        const retcode = c.swe_houses_ex2(jd, self.iflags, lat, lon, 'W', cusps[0..], ascmc[0..], cusps_speed[0..], ascmc_speed[0..], &errmsg);
        if (retcode < 0) return SweErr.CalcFailure;

        return .{ .lon = ascmc[0], .speed = ascmc_speed[0] };
    }
};

test "calcNextSunrise" {
    const swe = try Swe.init("");
    try testing.expect(!swe.isMoshierFallback());

    const tolerance_1_second = 1.0 / 86400.0;

    // Test Sunrise in Pune on 23 July 2025
    const pune_lon = 73 + 51.0 / 60.0;
    const pune_lat = 18 + 31.0 / 60.0;
    const jd_start = 2460879.5; // midnight UTC on Jul 23.
    const jd_expected = 2460879.529872685; // 06:13:01 local time, as produced by JyotishApp
    const jd_actual = try swe.calcNextSunrise(jd_start, pune_lon, pune_lat);
    try testing.expectApproxEqAbs(jd_expected, jd_actual, tolerance_1_second); // accurate to a second

    // verify that an error occurs if sun is circumpolar
    try testing.expectError(SweErr.CalcFailure, swe.calcNextSunrise(jd_start, 0, 89));
}

test "getPlanetPosition" {
    const swe = try Swe.init("");
    try testing.expect(!swe.isMoshierFallback());

    const tolerance_lon = 1.0 / 36000.0;
    const tolerance_speed = 1.0 / 100.0;

    // Test Planet Position on 23 July 2025
    const jd = 2460879.5; // midnight UTC on Jul 23.

    const TestCase = struct {
        planet: ephemeris.Planet,
        position: ephemeris.Position,
    };

    // These values are taken from Jyotish App unless specified otherwise.
    const cases = [_]TestCase{
        .{ .planet = .sun, .position = .{ .lon = 96.2101, .speed = 0.9547 } },
        .{ .planet = .moon, .position = .{ .lon = 72.6651, .speed = 14.3096 } },
        .{ .planet = .mars, .position = .{ .lon = 146.5947, .speed = 0.6051 } },
        .{ .planet = .mercury, .position = .{ .lon = 110.4281, .speed = -0.38 } }, // jyotish app speed: -0.345, this value taken from drik
        .{ .planet = .jupiter, .position = .{ .lon = 75.5508, .speed = 0.2202 } },
        .{ .planet = .venus, .position = .{ .lon = 56.4071, .speed = 1.1415 } },
        .{ .planet = .saturn, .position = .{ .lon = 337.6371, .speed = -0.0167 } }, // jyotish app speed: -0.0158, this value taken from drik
        .{ .planet = .rahu, .position = .{ .lon = 326.5334, .speed = -0.053 } },
        .{ .planet = .ketu, .position = .{ .lon = 146.5334, .speed = -0.053 } },
    };

    for (cases) |case| {
        const actual = try swe.getPlanetPosition(case.planet, jd);
        try std.testing.expectApproxEqRel(case.position.lon, actual.lon, tolerance_lon);
        try std.testing.expectApproxEqRel(case.position.speed, actual.speed, tolerance_speed);
    }
}

test "getAscendantPosition" {
    const swe = try Swe.init("");
    try testing.expect(!swe.isMoshierFallback());

    const tolerance_lon = 1.0 / 100.0;
    const tolerance_speed = 1.0 / 100.0;

    // Test Position in Pune on 23 July 2025
    const pune_lon = 73 + 51.0 / 60.0;
    const pune_lat = 18 + 31.0 / 60.0;

    const jd = 2460879.5; // midnight UTC on Jul 23.

    const actual = try swe.getAscendantPosition(pune_lon, pune_lat, jd);
    try std.testing.expectApproxEqRel(86.635, actual.lon, tolerance_lon);
    try std.testing.expectApproxEqRel(321.05, actual.speed, tolerance_speed);
}
