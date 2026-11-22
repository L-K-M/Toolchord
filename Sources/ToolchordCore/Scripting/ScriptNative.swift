import CryptoKit
import Foundation

/// The entire native surface is a closed set of pure data operations.
enum ScriptNative {
    static func call(_ name: String, _ args: [Any], _ request: ToolRequest) throws -> Any? {
        func string(_ index: Int) throws -> String {
            guard args.indices.contains(index), let value = args[index] as? String else {
                throw ScriptFailure("Expected text in " + name + ".")
            }
            return value
        }
        func millis() throws -> Int64 {
            guard let value = args.first as? NSNumber, let n = Int64(exactly: value.doubleValue),
                  (-281_474_976_710_655...281_474_976_710_655).contains(n) else {
                throw ScriptFailure("Timestamp is outside the supported range.")
            }
            return n
        }
        switch name {
        case "crypto.digest":
            let algorithm = try string(0)
            let data = try Data(string(1).utf8)
            guard let kind = HashTools.Algorithm(rawValue: algorithm) else { throw ScriptFailure("Unknown digest algorithm.") }
            return HashTools.hexDigest(of: data, algorithm: kind, cancellation: request.cancellation) ?? ""
        case "crypto.hkdfHex":
            let hex = try string(0)
            guard hex.utf8.count <= 4096, hex.utf8.count.isMultiple(of: 2),
                  args.count == 3, let size = args[2] as? Int, (1...4096).contains(size) else {
                throw ScriptFailure("Invalid HKDF parameters.")
            }
            var bytes = Data()
            var high: UInt8?
            for ascii in hex.utf8 {
                let digit: UInt8
                switch ascii {
                case 48...57: digit = ascii - 48
                case 97...102: digit = ascii - 87
                default: throw ScriptFailure("Expected a lowercase hex key.")
                }
                if let h = high { bytes.append(h << 4 | digit); high = nil } else { high = digit }
            }
            let info = try Data(string(1).utf8)
            let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes), info: info, outputByteCount: size)
            return key.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
        case "text.byteCountLabel":
            return try ByteCountText.string(string(0).utf8.count)
        case "clock.offsetSeconds":
            let date = try Date(timeIntervalSince1970: Double(millis()) / 1000)
            return request.timeZone.secondsFromGMT(for: date)
        default:
            if let result = try ScriptTextHost.call(name, args, request) { return result }
            return try ScriptStructuredHost.call(name, args, request)
        }
    }
}
