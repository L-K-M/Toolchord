import Foundation

enum TimeFailure: Error {
    case cancelled
    case invalid(ToolDiagnostic)
}

struct TimeParser {
    let original: [UInt8]
    let bytes: [UInt8]
    let start: Int
    let cancellation: CancellationCheck

    init(text: String, cancellation: CancellationCheck) throws {
        self.cancellation = cancellation
        var first: Int?
        var end = 0
        var offset = 0
        var scalarCount = 0
        for scalar in text.unicodeScalars {
            if scalarCount & 4095 == 0, cancellation.isCancelled { throw TimeFailure.cancelled }
            let length = scalar.utf8.count
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if first == nil { first = offset }
                end = offset + length
            }
            offset += length
            scalarCount += 1
        }
        original = Array(text.utf8)
        start = first ?? offset
        bytes = Array(original[start..<max(start, end)])
        if cancellation.isCancelled { throw TimeFailure.cancelled }
    }

    func fail(_ message: String, at offset: Int = 0) -> TimeFailure {
        .invalid(ToolDiagnostic(message, at: TextLocator.location(ofUTF8Offset: start + offset, in: original)))
    }

    func check(_ offset: Int) throws {
        if offset & 4095 == 0, cancellation.isCancelled { throw TimeFailure.cancelled }
    }

    static func isDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }

    /// Seeds deliberately accept only a signed decimal integer, without trimming.
    static func seed(_ text: String, cancellation: CancellationCheck) throws -> Int64? {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty else { return nil }
        var index = bytes[0] == 45 ? 1 : 0
        guard index < bytes.count else { return nil }
        var magnitude: UInt64 = 0
        let maximum = bytes[0] == 45 ? UInt64(Int64.max) + 1 : UInt64(Int64.max)
        while index < bytes.count {
            if index & 4095 == 0, cancellation.isCancelled { throw TimeFailure.cancelled }
            guard isDigit(bytes[index]) else { return nil }
            let digit = UInt64(bytes[index] - 48)
            guard magnitude <= (maximum - digit) / 10 else { return nil }
            magnitude = magnitude * 10 + digit
            index += 1
        }
        if bytes[0] != 45 { return Int64(magnitude) }
        return magnitude == UInt64(Int64.max) + 1 ? Int64.min : -Int64(magnitude)
    }

    enum UnixUnit: String {
        case auto
        case seconds = "s"
        case milliseconds = "ms"
    }

    func unix(unit: UnixUnit) throws -> (milliseconds: Int64, unit: UnixUnit) {
        let isMilliseconds = unit == .milliseconds
        let malformed = "Enter a Unix time such as 1700000000."
        guard !bytes.isEmpty else { throw fail(malformed) }
        let negative = bytes[0] == 45
        var index = negative ? 1 : 0
        let digitStart = index
        var whole: Int64 = 0
        var overflow = false
        while index < bytes.count, Self.isDigit(bytes[index]) {
            try check(index)
            let digit = Int64(bytes[index] - 48)
            if whole > (Int64.max - digit) / 10 { overflow = true }
            if !overflow { whole = whole * 10 + digit }
            index += 1
        }
        guard index > digitStart else { throw fail(malformed, at: index) }
        let dot = index
        var fraction: Int64 = 0
        var fractionCount = 0
        if index < bytes.count, bytes[index] == 46 {
            index += 1
            while index < bytes.count, Self.isDigit(bytes[index]) {
                try check(index)
                if fractionCount < 3 { fraction = fraction * 10 + Int64(bytes[index] - 48) }
                fractionCount += 1
                index += 1
            }
            guard fractionCount > 0 else { throw fail(malformed, at: index) }
        }
        guard index == bytes.count else { throw fail(malformed, at: index) }
        if isMilliseconds, fractionCount > 0 { throw fail("Milliseconds must be a whole number.", at: dot) }
        if !isMilliseconds, fractionCount > 3 {
            throw fail("Unix seconds support up to millisecond precision (three decimal places).", at: dot + 1)
        }
        if fractionCount == 1 { fraction *= 100 }
        if fractionCount == 2 { fraction *= 10 }
        let scale: Int64 = isMilliseconds ? 1 : 1000
        let (scaled, scaleOverflow) = whole.multipliedReportingOverflow(by: scale)
        let (magnitude, fractionOverflow) = scaled.addingReportingOverflow(isMilliseconds ? 0 : fraction)
        if !overflow && !scaleOverflow && !fractionOverflow {
            let value = negative ? -magnitude : magnitude
            if TimeMath.range.contains(value) { return (value, isMilliseconds ? .milliseconds : .seconds) }
        }
        var message = TimeMath.rangeMessage
        if !isMilliseconds, fractionCount == 0, !overflow, TimeMath.range.contains(negative ? -whole : whole) {
            if unit == .auto { return (negative ? -whole : whole, .milliseconds) }
            message += TimeMath.millisecondHint
        }
        throw fail(message)
    }

    func rfc3339() throws -> Int64 {
        let generic = "Use an RFC 3339 date such as 2024-01-01T12:00:00Z."
        func number(_ offset: Int, _ count: Int) throws -> Int64 {
            guard offset + count <= bytes.count else { throw fail(generic, at: min(offset, bytes.count)) }
            var value: Int64 = 0
            for index in offset..<(offset + count) {
                guard Self.isDigit(bytes[index]) else { throw fail(generic, at: index) }
                value = value * 10 + Int64(bytes[index] - 48)
            }
            return value
        }
        func expect(_ byte: UInt8, at offset: Int) throws {
            guard offset < bytes.count, bytes[offset] == byte else { throw fail(generic, at: min(offset, bytes.count)) }
        }
        let year = try number(0, 4)
        try expect(45, at: 4)
        let month = try number(5, 2)
        try expect(45, at: 7)
        let day = try number(8, 2)
        guard year >= 1 else { throw fail("Year must be between 0001 and 9999.") }
        guard (1...12).contains(month) else { throw fail("Month must be between 01 and 12.", at: 5) }
        let maximumDay = TimeMath.monthDays(month, year)
        guard (1...maximumDay).contains(day) else {
            let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
            throw fail("\(months[Int(month - 1)]) \(year) has \(maximumDay) days.", at: 8)
        }
        if bytes.count == 10 { throw fail("Add a time and offset, for example “2024-01-01T00:00:00Z”.", at: 10) }
        guard [UInt8(84), 116, 32].contains(bytes[10]) else { throw fail(generic, at: 10) }
        let hour = try number(11, 2)
        try expect(58, at: 13)
        let minute = try number(14, 2)
        try expect(58, at: 16)
        let second = try number(17, 2)
        guard hour < 24 else { throw fail("Hour must be between 00 and 23.", at: 11) }
        guard minute < 60 else { throw fail("Minute must be between 00 and 59.", at: 14) }
        if second == 60 { throw fail("Leap seconds (:60) aren’t supported.", at: 17) }
        guard second < 60 else { throw fail("Second must be between 00 and 59.", at: 17) }
        var index = 19
        var fraction: Int64 = 0
        if index < bytes.count, bytes[index] == 46 {
            index += 1
            let fractionStart = index
            while index < bytes.count, Self.isDigit(bytes[index]) {
                try check(index)
                if index - fractionStart < 3 { fraction = fraction * 10 + Int64(bytes[index] - 48) }
                else if bytes[index] != 48 {
                    throw fail("Toolchord supports millisecond precision (three fraction digits).", at: index)
                }
                index += 1
            }
            let count = index - fractionStart
            guard count > 0 else { throw fail(generic, at: index) }
            if count == 1 { fraction *= 100 }
            if count == 2 { fraction *= 10 }
        }
        guard index < bytes.count else {
            throw fail("Add a time zone offset such as “Z” or “+01:00”. Toolchord doesn’t guess the time zone.", at: index)
        }
        var offset: Int64 = 0
        if bytes[index] == 90 || bytes[index] == 122 { index += 1 }
        else if bytes[index] == 43 || bytes[index] == 45 {
            let negative = bytes[index] == 45
            let hours = try number(index + 1, 2)
            try expect(58, at: index + 3)
            let minutes = try number(index + 4, 2)
            guard hours < 24 else { throw fail("Offset hour must be between 00 and 23.", at: index + 1) }
            guard minutes < 60 else { throw fail("Offset minute must be between 00 and 59.", at: index + 4) }
            offset = (hours * 3600 + minutes * 60) * (negative ? -1 : 1)
            index += 6
        } else { throw fail(generic, at: index) }
        guard index == bytes.count else { throw fail(generic, at: index) }
        let seconds = TimeMath.daysFromCivil(year: year, month: month, day: day) * 86400 + hour * 3600 + minute * 60 + second - offset
        let milliseconds = seconds * 1000 + fraction
        guard TimeMath.range.contains(milliseconds) else { throw fail(TimeMath.rangeMessage) }
        return milliseconds
    }
}
