import Foundation
import Testing
@testable import ToolchordCore

@Suite struct TimeToolsTests {
    let utc = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func command(_ id: String) throws -> ToolCommand {
        try #require(TimeTools.commands.first { $0.id == id })
    }

    func result(_ id: String, _ text: String, unit: String = "s", timeZone: TimeZone? = nil, clock: Date? = nil) throws -> ToolResult {
        try command(id).run(ToolRequest(input: .text(text), options: ToolOptions(["unit": unit]), now: clock ?? now, timeZone: timeZone ?? utc))
    }

    func output(_ id: String, _ text: String, unit: String = "s", timeZone: TimeZone? = nil, clock: Date? = nil) throws -> ToolOutput {
        let value = try result(id, text, unit: unit, timeZone: timeZone, clock: clock)
        return try #require(value.output, "Expected success, got \(value)")
    }

    func diagnostic(_ id: String, _ text: String, unit: String = "s") throws -> ToolDiagnostic {
        let value = try result(id, text, unit: unit)
        guard case .invalid(let diagnostic) = value else {
            Issue.record("Expected invalid, got \(value)")
            throw ToolDiagnostic("Expected invalid.")
        }
        return diagnostic
    }

    @Test(arguments: [
        ("1700000000", "2023-11-14T22:13:20.000Z", "Read as seconds"),
        ("1700000000000", "2023-11-14T22:13:20.000Z", "Read as milliseconds"),
        ("1700000000.5", "2023-11-14T22:13:20.500Z", "Read as seconds"),
        ("-1", "1969-12-31T23:59:59.000Z", "Read as seconds"),
        ("253402300799", "9999-12-31T23:59:59.000Z", "Read as seconds"),
        ("253402300800", "1978-01-11T21:31:40.800Z", "Read as milliseconds"),
        ("-62135596801", "1968-01-12T20:06:43.199Z", "Read as milliseconds"),
    ])
    func autoUnixFixtures(_ fixture: (String, String, String)) throws {
        let tool = try command("time.fromUnix")
        for options in [ToolOptions(), ToolOptions(["unit": "auto"])] {
            let result = tool.run(ToolRequest(input: .text(fixture.0), options: options, now: now, timeZone: utc))
            let value = try #require(result.output, "Expected success, got \(result)")
            #expect(value.primaryText == fixture.1)
            #expect(value.status == fixture.2)
        }
    }

    @Test(arguments: ["1700000000000.5", "253402300800000", "-62135596800001", "9223372036854775808", "1.2345", "1.0000", "1e3"])
    func autoUnixPreservesSecondsErrors(_ input: String) throws {
        #expect(try result("time.fromUnix", input, unit: "auto") == result("time.fromUnix", input, unit: "s"))
    }

    @Test(arguments: [
        ("0", "s", "1970-01-01T00:00:00.000Z"),
        ("-1", "s", "1969-12-31T23:59:59.000Z"),
        ("1700000000", "s", "2023-11-14T22:13:20.000Z"),
        ("1700000000000", "ms", "2023-11-14T22:13:20.000Z"),
        ("1700000000", "ms", "1970-01-20T16:13:20.000Z"),
        ("1.5", "s", "1970-01-01T00:00:01.500Z"),
        ("253402300799.999", "s", "9999-12-31T23:59:59.999Z"),
        ("-62135596800", "s", "0001-01-01T00:00:00.000Z"),
        ("951782400", "s", "2000-02-29T00:00:00.000Z"),
        ("-0.5", "s", "1969-12-31T23:59:59.500Z"),
        ("-1", "ms", "1969-12-31T23:59:59.999Z"),
        (" \r\n\t1.050\u{2003}", "s", "1970-01-01T00:00:01.050Z"),
        ("-0.000", "s", "1970-01-01T00:00:00.000Z"),
        ("0000001", "ms", "1970-01-01T00:00:00.001Z"),
        ("-62135596800000", "ms", "0001-01-01T00:00:00.000Z"),
        ("253402300799999", "ms", "9999-12-31T23:59:59.999Z"),
    ])
    func unixFixtures(_ fixture: (String, String, String)) throws {
        let value = try output("time.fromUnix", fixture.0, unit: fixture.1)
        #expect(value.primaryText == fixture.2)
        #expect(value.status == (fixture.1 == "s" ? "Read as seconds" : "Read as milliseconds"))
    }

    @Test(arguments: [
        ("1700000000000.5", "auto", "Out of range. Toolchord supports dates from year 0001 to 9999."),
        ("1700000000000", "s", "Out of range. Toolchord supports dates from year 0001 to 9999. If this is a millisecond timestamp, set Unit to Milliseconds."),
        // Read as milliseconds, this is in 1968: the hint is required.
        ("-62135596801", "s", "Out of range. Toolchord supports dates from year 0001 to 9999. If this is a millisecond timestamp, set Unit to Milliseconds."),
        ("1.2345", "s", "Unix seconds support up to millisecond precision (three decimal places)."),
        ("1.0000", "s", "Unix seconds support up to millisecond precision (three decimal places)."),
        ("12.5", "ms", "Milliseconds must be a whole number."),
        ("12.0", "ms", "Milliseconds must be a whole number."),
        ("253402300800000", "ms", "Out of range. Toolchord supports dates from year 0001 to 9999."),
        ("-62135596800001", "ms", "Out of range. Toolchord supports dates from year 0001 to 9999."),
        ("253402300800.001", "s", "Out of range. Toolchord supports dates from year 0001 to 9999."),
        ("99999999999999999999999999999999", "s", "Out of range. Toolchord supports dates from year 0001 to 9999."),
        ("9223372036854775807", "ms", "Out of range. Toolchord supports dates from year 0001 to 9999."),
        ("-9223372036854775808", "ms", "Out of range. Toolchord supports dates from year 0001 to 9999."),
    ])
    func unixErrors(_ fixture: (String, String, String)) throws {
        #expect(try diagnostic("time.fromUnix", fixture.0, unit: fixture.1).message == fixture.2)
    }

    @Test(arguments: ["abc", "", " \n ", "+1", "1e3", "1_000", "1,000", "1.", ".5", "--1", "1.2.3", "1 2", "１２", "-", "nan"])
    func malformedUnix(_ input: String) throws {
        #expect(try diagnostic("time.fromUnix", input).message == "Enter a Unix time such as 1700000000.")
    }

    @Test(arguments: [
        ("2024-01-01T01:00:00+01:00", "s", "1704067200"),
        ("2024-01-01T01:00:00+01:00", "ms", "1704067200000"),
        ("2024-01-01T00:00:00.5Z", "s", "1704067200.5"),
        ("2024-01-01T00:00:00.1230Z", "s", "1704067200.123"),
        ("1970-01-01T00:00:00Z", "s", "0"),
        ("1969-12-31T23:59:59Z", "s", "-1"),
        ("2024-01-01 00:00:00z", "s", "1704067200"),
        ("1969-12-31T23:59:59.500Z", "s", "-0.5"),
        ("1970-01-01t00:00:00.001000Z", "ms", "1"),
        ("1970-01-01T00:00:00-00:01", "s", "60"),
        ("1970-01-01T00:00:00+23:59", "s", "-86340"),
        ("1970-01-01T00:00:00-23:59", "s", "86340"),
        ("\u{2003}\r\n2024-01-01T00:00:00Z \n", "s", "1704067200"),
    ])
    func dateFixtures(_ fixture: (String, String, String)) throws {
        #expect(try output("time.toUnix", fixture.0, unit: fixture.1).primaryText == fixture.2)
    }

    @Test(arguments: [
        ("2024-01-01T00:00:00.1234Z", "Toolchord supports millisecond precision (three fraction digits).", 24),
        ("2024-02-30T00:00:00Z", "February 2024 has 29 days.", 9),
        ("2023-02-29T00:00:00Z", "February 2023 has 28 days.", 9),
        ("1900-02-29T00:00:00Z", "February 1900 has 28 days.", 9),
        ("2024-04-31T00:00:00Z", "April 2024 has 30 days.", 9),
        ("2024-01-00T00:00:00Z", "January 2024 has 31 days.", 9),
        ("2024-00-01T00:00:00Z", "Month must be between 01 and 12.", 6),
        ("2024-13-01T00:00:00Z", "Month must be between 01 and 12.", 6),
        ("0000-01-01T00:00:00Z", "Year must be between 0001 and 9999.", 1),
        ("2024-01-01T24:00:00Z", "Hour must be between 00 and 23.", 12),
        ("2024-01-01T00:60:00Z", "Minute must be between 00 and 59.", 15),
        ("2024-01-01T00:00:60Z", "Leap seconds (:60) aren’t supported.", 18),
        ("2024-01-01T00:00:61Z", "Second must be between 00 and 59.", 18),
        ("2024-01-01T00:00:00+24:00", "Offset hour must be between 00 and 23.", 21),
        ("2024-01-01T00:00:00-00:60", "Offset minute must be between 00 and 59.", 24),
        ("2024-01-01T00:00:00", "Add a time zone offset such as “Z” or “+01:00”. Toolchord doesn’t guess the time zone.", 20),
        ("2024-01-01T00:00:00.123", "Add a time zone offset such as “Z” or “+01:00”. Toolchord doesn’t guess the time zone.", 24),
        ("2024-01-01", "Add a time and offset, for example “2024-01-01T00:00:00Z”.", 11),
        ("0001-01-01T00:00:00+00:01", "Out of range. Toolchord supports dates from year 0001 to 9999.", 1),
        ("9999-12-31T23:59:59.999-00:01", "Out of range. Toolchord supports dates from year 0001 to 9999.", 1),
    ])
    func dateErrors(_ fixture: (String, String, Int)) throws {
        let value = try diagnostic("time.toUnix", fixture.0)
        #expect(value.message == fixture.1)
        #expect(value.location == TextLocation(line: 1, column: fixture.2))
    }

    @Test(arguments: ["", "abc", "2024/01/01T00:00:00Z", "2024-1-01T00:00:00Z", "2024-01-01TT00:00:00Z", "2024-01-01T00:00Z", "2024-01-01T00:00:00.Z", "2024-01-01T00:00:00+0100", "2024-01-01T00:00:00Zx", "2024-01-01T00:00:00+01:00:00", "2024-01-01T00:00:00 UTC"])
    func malformedDates(_ input: String) throws {
        #expect(try diagnostic("time.toUnix", input).message == "Use an RFC 3339 date such as 2024-01-01T12:00:00Z.")
    }

    @Test func locationsRespectOriginalUnicodeAndLineBreaks() throws {
        let error = try diagnostic("time.toUnix", "\u{2003}\r\n\t2024-02-30T00:00:00Z")
        #expect(error.location == TextLocation(line: 2, column: 10))
        let unixError = try diagnostic("time.fromUnix", "\r\n\u{2003}1✓")
        #expect(unixError.location == TextLocation(line: 2, column: 3))
    }

    @Test(arguments: [
        ("Europe/Zurich", "2023-11-14T23:13:20.000+01:00"),
        ("America/New_York", "2023-11-14T17:13:20.000-05:00"),
    ])
    func localFields(_ fixture: (String, String)) throws {
        let zone = try #require(TimeZone(identifier: fixture.0))
        let value = try output("time.fromUnix", "1700000000", timeZone: zone)
        let local = try #require(value.fields.first { $0.id == "local" })
        #expect(local.value == fixture.1)
        #expect(local.note == fixture.0)
    }

    @Test func offsetSecondsAndDayRollover() throws {
        let zone = try #require(TimeZone(secondsFromGMT: -3661))
        let value = try output("time.fromUnix", "0", timeZone: zone)
        #expect(value.fields.first { $0.id == "local" }?.value == "1969-12-31T22:58:59.000-01:01:01")
        let zurich = try #require(TimeZone(identifier: "Europe/Zurich"))
        let summer = try output("time.fromUnix", "1719792000", timeZone: zurich)
        // 2024-07-01T00:00:00Z is 02:00 during Central European Summer Time.
        #expect(summer.fields.first { $0.id == "local" }?.value == "2024-07-01T02:00:00.000+02:00")
    }

    @Test(arguments: [
        ("1700000000", Int64(1700259200), "3 days ago"),
        ("1700003600", 1700000000, "in 1 hour"),
        ("1700000000.999", 1700000000, "now"),
        ("1699999999.001", 1700000000, "now"),
        ("1700000001", 1700000000, "in 1 second"),
        ("1699999940", 1700000000, "1 minute ago"),
        ("1699913600", 1700000000, "1 day ago"),
        ("1702592000", 1700000000, "in 1 month"),
        ("1731536000", 1700000000, "in 1 year"),
        ("1700000301", 1700000000, "in 5 minutes"),
    ])
    func relativeFields(_ fixture: (String, Int64, String)) throws {
        let value = try output("time.fromUnix", fixture.0, clock: Date(timeIntervalSince1970: Double(fixture.1)))
        let relative = try #require(value.fields.first { $0.id == "relative" })
        #expect(relative.value == fixture.2)
        #expect(!relative.isCopyable)
        #expect(!relative.isMonospaced)
    }

    @Test func fieldFormatsAndNormalizedStatus() throws {
        let from = try output("time.fromUnix", "-0.500")
        #expect(from.fields.map(\.id) == ["utc", "local", "seconds", "milliseconds", "relative"])
        #expect(from.fields.first { $0.id == "seconds" }?.value == "-0.5")
        #expect(from.fields.first { $0.id == "milliseconds" }?.value == "-500")
        let to = try output("time.toUnix", "2024-01-01T01:00:00+01:00")
        #expect(to.status == "UTC 2024-01-01T00:00:00.000Z")
        #expect(to.fields.map(\.id) == ["seconds", "milliseconds", "utc", "local"])
        #expect(to.fields.map(\.value) == ["1704067200", "1704067200000", "2024-01-01T00:00:00.000Z", "2024-01-01T00:00:00.000+00:00"])
    }

    @Test(arguments: [
        ("0001-01-01T00:00:00.000Z", "-62135596800"),
        // Gregorian day count: 1582-10-10 lies 141432 days before the epoch.
        ("1582-10-10T00:00:00.000Z", "-12219724800"),
        ("2000-02-29T00:00:00.000Z", "951782400"),
        ("9999-12-31T23:59:59.999Z", "253402300799.999"),
        ("1969-12-31T23:59:59.500Z", "-0.5"),
    ])
    func exactRoundTrips(_ fixture: (String, String)) throws {
        let seconds = try output("time.toUnix", fixture.0).primaryText
        #expect(seconds == fixture.1)
        #expect(try output("time.fromUnix", seconds).primaryText == fixture.0)
        let milliseconds = try output("time.toUnix", fixture.0, unit: "ms").primaryText
        #expect(try output("time.fromUnix", milliseconds, unit: "ms").primaryText == fixture.0)
    }

    @Test(arguments: [
        ("1700000000123", "s", "1700000000"),
        ("1700000000123", "ms", "1700000000123"),
        ("1700000000123", "iso", "2023-11-14T22:13:20.123Z"),
        ("-1", "s", "-1"),
        ("-1", "iso", "1969-12-31T23:59:59.999Z"),
        ("-62135596800000", "iso", "0001-01-01T00:00:00.000Z"),
        ("253402300799999", "iso", "9999-12-31T23:59:59.999Z"),
    ])
    func capturedTime(_ fixture: (String, String, String)) throws {
        let value = try command("time.now").run(ToolRequest(input: .none, options: ToolOptions(["format": fixture.1]), seed: fixture.0, now: now, timeZone: utc))
        #expect(value.output?.primaryText == fixture.2)
        #expect(value.output?.fields.map(\.id) == ["seconds", "milliseconds", "utc", "local"])
    }

    @Test func capturedStatusUsesLocalTimeAndSeed() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Zurich"))
        let value = try command("time.now").run(ToolRequest(input: .text("ignored"), seed: "1700000000123", now: Date(timeIntervalSince1970: 0), timeZone: zone))
        #expect(value.output?.status == "Captured at 23:13:20")
        #expect(value.output?.fields.first { $0.id == "seconds" }?.value == "1700000000.123")
    }

    @Test(arguments: [nil, "", "abc", " 123", "+123", "1.0", "-", "9223372036854775808"] as [String?])
    func missingOrMalformedSeed(_ seed: String?) throws {
        let value = try command("time.now").run(ToolRequest(input: .none, seed: seed, now: now, timeZone: utc))
        #expect(value == .needsInput("Select Show Current Time again to capture the time."))
    }

    @Test(arguments: [(1700000000.1239, "1700000000123"), (-0.0004, "-1"), (-0.5004, "-501"), (0.0, "0")])
    func seedFloorsClock(_ fixture: (Double, String)) throws {
        let makeSeed = try #require(command("time.now").makeSeed)
        #expect(makeSeed(SeedContext(now: Date(timeIntervalSince1970: fixture.0))) == fixture.1)
    }

    @Test func requirementsOptionsAndAffinity() throws {
        for id in ["time.fromUnix", "time.toUnix"] {
            #expect(try command(id).run(ToolRequest(input: .none, now: now, timeZone: utc)).output == nil)
            if case .needsInput = try command(id).run(ToolRequest(input: .none, now: now, timeZone: utc)) {} else { Issue.record("Expected needsInput") }
        }
        let from = try command("time.fromUnix")
        let to = try command("time.toUnix")
        let current = try command("time.now")
        #expect(from.group == .time)
        #expect(from.options == [.choice("unit", "Unit", [.init("auto", "Auto"), .init("s", "Seconds"), .init("ms", "Milliseconds")], default: "auto")])
        #expect(to.options == [.choice("unit", "Unit", [.init("s", "Seconds"), .init("ms", "Milliseconds")], default: "s")])
        #expect(to.copyAndCloseTitle(options: ToolOptions(["unit": "ms"])) == "Copy milliseconds & Close")
        #expect(current.copyAndCloseTitle(options: ToolOptions(["format": "iso"])) == "Copy UTC time & Close")
        #expect(current.isGenerator)
        #expect(current.regenerateTitle == "Refresh Time")
        let profile = InputProfile(isAttached: true, kinds: [.unixTime], primaryKind: .unixTime, byteCount: 1, lineCount: 1, isBlank: false)
        #expect(from.affinity(profile) == 95)
        #expect(to.affinity(profile) == 0)
        var dateProfile = profile
        dateProfile.kinds = [.dateTime]
        #expect(to.affinity(dateProfile) == 95)
        #expect(from.affinity(.none) == 0)
        #expect(try result("time.fromUnix", "0", unit: "invalid").output?.primaryText == "1970-01-01T00:00:00.000Z")
    }

    @Test func limitsAndCancellation() throws {
        for (id, text) in [("time.fromUnix", "0"), ("time.toUnix", "1970-01-01T00:00:00Z"), ("time.now", "")] {
            let tool = try command(id)
            let limits = ToolLimits(maxOutputBytes: 2)
            #expect(tool.run(ToolRequest(input: .text(text), seed: "0", now: now, timeZone: utc, limits: limits)) == .tooLarge(limits.outputLimitMessage))
            #expect(tool.run(ToolRequest(input: .text(text), seed: "0", now: now, timeZone: utc, cancellation: CancellationCheck { true })) == .cancelled)
        }
        let limits = ToolLimits(maxInputBytes: 3)
        #expect(try command("time.fromUnix").run(ToolRequest(input: .text("1234"), now: now, timeZone: utc, limits: limits)) == .tooLarge(limits.inputLimitMessage))
    }

    @Test func largeInputsStayLinearAndExact() throws {
        let zeros = String(repeating: "0", count: 100_000)
        #expect(try output("time.fromUnix", zeros + "1").primaryText == "1970-01-01T00:00:01.000Z")
        #expect(try output("time.toUnix", "1970-01-01T00:00:00.123" + zeros + "Z").primaryText == "0.123")
        #expect(try diagnostic("time.fromUnix", String(repeating: "9", count: 100_000)).message == "Out of range. Toolchord supports dates from year 0001 to 9999.")
    }

    @Test func cancellationDuringLargeScans() throws {
        let spaces = String(repeating: "\u{2003}", count: 50_000)
        let zeros = String(repeating: "0", count: 100_000)
        for (id, text, seed) in [
            ("time.fromUnix", spaces + "0", "0"),
            ("time.toUnix", "1970-01-01T00:00:00." + zeros + "Z", "0"),
            ("time.now", "", zeros + "1"),
        ] {
            let counter = TimeCancellationCounter()
            let value = try command(id).run(ToolRequest(
                input: .text(text), seed: seed, now: now, timeZone: utc,
                cancellation: CancellationCheck { counter.shouldCancel() }
            ))
            #expect(value == .cancelled)
        }
    }

    @Test func localDatesMayCrossSupportedUTCYearBoundaries() throws {
        let west = try #require(TimeZone(secondsFromGMT: -60))
        let east = try #require(TimeZone(secondsFromGMT: 60))
        let minimum = try output("time.fromUnix", "-62135596800", timeZone: west)
        #expect(minimum.fields.first { $0.id == "local" }?.value == "0000-12-31T23:59:00.000-00:01")
        let maximum = try output("time.fromUnix", "253402300799.999", timeZone: east)
        #expect(maximum.fields.first { $0.id == "local" }?.value == "10000-01-01T00:00:59.999+00:01")
    }
}

/// Each evaluation gets its own synchronized cancellation source.
final class TimeCancellationCounter: @unchecked Sendable {
    let lock = NSLock()
    var checks = 0

    func shouldCancel() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        checks += 1
        return checks >= 5
    }
}
