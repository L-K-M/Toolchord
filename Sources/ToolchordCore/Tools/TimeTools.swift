import Foundation

/// Exact Unix time and proleptic Gregorian RFC 3339 conversion.
public enum TimeTools {
    private static let fromUnixUnit: ToolOption = .choice("unit", "Unit", [.init("auto", "Auto"), .init("s", "Seconds"), .init("ms", "Milliseconds")], default: "auto")
    static let unit: ToolOption = .choice("unit", "Unit", [.init("s", "Seconds"), .init("ms", "Milliseconds")], default: "s")

    public static let commands: [ToolCommand] = [
        ToolCommand(
            id: "time.fromUnix", title: "Convert Unix Time", summary: "Seconds or milliseconds to a date",
            group: .time, icon: .symbol("clock"),
            aliases: ["epoch", "unix timestamp", "timestamp to date", "epoch to date", "unix to date", "epoch converter"],
            options: [fromUnixUnit], copyNoun: "UTC time", affinity: { $0.has(.unixTime) ? 95 : 0 },
            evaluate: { evaluate($0, operation: .fromUnix) }
        ),
        ToolCommand(
            id: "time.toUnix", title: "Convert Date to Unix Time", summary: "RFC 3339 date to Unix time",
            group: .time, icon: .symbol("calendar"),
            aliases: ["date to epoch", "iso to unix", "date to timestamp", "rfc3339 to unix", "iso 8601 to epoch"],
            options: [unit], copyNoun: { $0.choice("unit", default: "s") == "ms" ? "milliseconds" : "seconds" },
            affinity: { $0.has(.dateTime) ? 95 : 0 }, evaluate: { evaluate($0, operation: .toUnix) }
        ),
        ToolCommand(
            id: "time.now", title: "Show Current Time", summary: "Now as Unix time and RFC 3339",
            group: .time, icon: .symbol("clock.arrow.circlepath"),
            aliases: ["now", "current time", "current timestamp", "epoch now", "unix now", "time now"], input: .none,
            options: [.choice("format", "Copy", [.init("s", "Unix seconds"), .init("ms", "Unix milliseconds"), .init("iso", "UTC")], default: "s")],
            copyNoun: {
                switch $0.choice("format", default: "s") {
                case "ms": "milliseconds"
                case "iso": "UTC time"
                default: "seconds"
                }
            },
            makeSeed: { TimeMath.clockMilliseconds($0.now).map(String.init) ?? "" },
            regenerateTitle: "Refresh Time", evaluate: { evaluate($0, operation: .now) }
        ),
    ]

    enum Operation { case fromUnix, toUnix, now }

    static func evaluate(_ request: ToolRequest, operation: Operation) -> ToolResult {
        if request.cancellation.isCancelled { return .cancelled }
        do {
            let milliseconds: Int64
            var readUnit: TimeParser.UnixUnit = .seconds
            switch operation {
            case .now:
                guard let seed = request.seed,
                      let parsed = try TimeParser.seed(seed, cancellation: request.cancellation) else {
                    return .needsInput("Select Show Current Time again to capture the time.")
                }
                milliseconds = parsed
                guard TimeMath.range.contains(milliseconds) else { throw TimeFailure.invalid(ToolDiagnostic(TimeMath.rangeMessage)) }
            case .fromUnix:
                let parser = try TimeParser(text: request.input.text ?? "", cancellation: request.cancellation)
                let unit = TimeParser.UnixUnit(rawValue: request.options.choice("unit", default: "auto")) ?? .auto
                let parsed = try parser.unix(unit: unit)
                milliseconds = parsed.milliseconds
                readUnit = parsed.unit
            case .toUnix:
                let parser = try TimeParser(text: request.input.text ?? "", cancellation: request.cancellation)
                milliseconds = try parser.rfc3339()
            }
            let utc = TimeMath.format(milliseconds, suffix: "Z")
            let offset = request.timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(TimeMath.floorDivide(milliseconds, 1000))))
            let local = TimeMath.format(milliseconds + Int64(offset) * 1000, suffix: TimeMath.offsetText(offset))
            let seconds = TimeMath.secondsText(milliseconds)
            var fields: [ResultField] = [
                ResultField(id: "seconds", label: "Unix seconds", value: seconds),
                ResultField(id: "milliseconds", label: "Unix milliseconds", value: String(milliseconds)),
                ResultField(id: "utc", label: "UTC", value: utc),
                ResultField(id: "local", label: "Local", value: local, note: request.timeZone.identifier),
            ]
            let primary: String
            let status: String
            switch operation {
            case .fromUnix:
                primary = utc
                status = readUnit == .milliseconds ? "Read as milliseconds" : "Read as seconds"
                fields = [fields[2], fields[3], fields[0], fields[1]]
                fields.append(ResultField(id: "relative", label: "Relative", value: TimeMath.relative(milliseconds, to: request.now), isCopyable: false, isMonospaced: false))
            case .toUnix:
                primary = request.options.choice("unit", default: "s") == "ms" ? String(milliseconds) : seconds
                status = "UTC \(utc)"
            case .now:
                switch request.options.choice("format", default: "s") {
                case "ms": primary = String(milliseconds)
                case "iso": primary = utc
                default: primary = String(TimeMath.floorDivide(milliseconds, 1000))
                }
                status = "Captured at \(TimeMath.timeOfDay(milliseconds + Int64(offset) * 1000))"
            }
            // Every independently copyable value observes the output budget.
            if primary.utf8.count > request.limits.maxOutputBytes || fields.contains(where: { $0.value.utf8.count > request.limits.maxOutputBytes }) {
                return .tooLarge(request.limits.outputLimitMessage)
            }
            if request.cancellation.isCancelled { return .cancelled }
            return .success(ToolOutput(primaryText: primary, status: status, fields: fields))
        } catch TimeFailure.cancelled {
            return .cancelled
        } catch TimeFailure.invalid(let diagnostic) {
            return .invalid(diagnostic)
        } catch {
            return .invalid(ToolDiagnostic("Use an RFC 3339 date such as 2024-01-01T12:00:00Z."))
        }
    }
}
