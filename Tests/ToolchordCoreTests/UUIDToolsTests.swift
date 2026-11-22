import Foundation
import Testing
@testable import ToolchordCore

@Suite struct UUIDToolsTests {
    private func command(_ id: String) throws -> ToolCommand {
        try #require(UUIDTools.commands.first { $0.id == id })
    }

    private func output(_ id: String, seed: String?) throws -> ToolOutput {
        let result = try command(id).run(ToolRequest(input: .none, seed: seed, timeZone: TimeZone(identifier: "UTC")!))
        return try #require(result.output, "Expected success, got \(result)")
    }

    private func field(_ output: ToolOutput, _ id: String) -> String? {
        output.fields.first { $0.id == id }?.value
    }

    private func seed(_ id: String, milliseconds: Int64, bytes: [UInt8]) throws -> String {
        try ScriptRuntime.seed(id: id, source: BundledScripts.sourceFile("uuid"),
                               context: SeedContext(now: Date(timeIntervalSince1970: Double(milliseconds) / 1000)),
                               entropy: bytes)
    }

    @Test func uuidV7MatchesRFC9562TestVector() throws {
        // RFC 9562 Appendix A.6.
        #expect(try seed("uuid.v7", milliseconds: 0x017F_22E2_79B0, bytes: [0,0,0,0,0,0,0x0c,0xc3,0x18,0xc4,0xdc,0x0c,0x0c,0x07,0x39,0x8f])
            == "017f22e2-79b0-7cc3-98c4-dc0c0c07398f")
    }

    @Test func uuidV7ShowsItsTimestamp() throws {
        let value = try output("uuid.v7", seed: "017f22e2-79b0-7cc3-98c4-dc0c0c07398f")
        #expect(value.primaryText == "017f22e2-79b0-7cc3-98c4-dc0c0c07398f")
        #expect(value.status == "UUID v7")
        #expect(field(value, "timestamp") == "2022-02-22T19:22:22.000Z")
        #expect(field(value, "compact") == "017f22e279b07cc398c4dc0c0c07398f")
    }

    @Test func uuidV7IgnoresBitsOutsideTheirFields() throws {
        let value = try seed("uuid.v7", milliseconds: 0xffffffffffff, bytes: Array(repeating: 255, count: 16))
        #expect(value == "ffffffff-ffff-7fff-bfff-ffffffffffff")
    }

    @Test func ulidMatchesSpecExamples() throws {
        #expect(try seed("uuid.ulid", milliseconds: 0, bytes: Array(repeating: 0, count: 10)) == "00000000000000000000000000")
        #expect(try seed("uuid.ulid", milliseconds: 1_469_918_176_385, bytes: Array(repeating: 0xFF, count: 10)) == "01ARYZ6S41ZZZZZZZZZZZZZZZZ")
        #expect(try seed("uuid.ulid", milliseconds: 281_474_976_710_655, bytes: Array(repeating: 0, count: 10)) == "7ZZZZZZZZZ0000000000000000")
    }

    @Test func ulidShowsTimestampAndLowercase() throws {
        let value = try output("uuid.ulid", seed: "01ARYZ6S41ZZZZZZZZZZZZZZZZ")
        #expect(value.status == "ULID")
        #expect(field(value, "timestamp") == "2016-07-30T22:36:16.385Z")
        #expect(field(value, "lower") == "01aryz6s41zzzzzzzzzzzzzzzz")
    }

    @Test func uuidV4FormatsTheSeed() throws {
        let value = try output("uuid.v4", seed: "0f8fad5b-d9cb-469f-a165-70867728950e")
        #expect(value.primaryText == "0f8fad5b-d9cb-469f-a165-70867728950e")
        #expect(value.status == "UUID v4")
        #expect(field(value, "braced") == "{0F8FAD5B-D9CB-469F-A165-70867728950E}")
        #expect(field(value, "upper") == "0F8FAD5B-D9CB-469F-A165-70867728950E")
    }

    @Test func malformedOrMissingSeedsAskToRegenerate() throws {
        for (id, seed) in [("uuid.v4", "not-a-uuid"), ("uuid.v4", nil), ("uuid.v7", "0f8fad5b-d9cb-469f-a165-70867728950e"), ("uuid.ulid", "8ZZZZZZZZZ0000000000000000"), ("uuid.ulid", nil)] as [(String, String?)] {
            let result = try command(id).run(ToolRequest(input: .none, seed: seed))
            if case .needsInput = result {} else { Issue.record("Expected needsInput for \(id) seed \(String(describing: seed)), got \(result)") }
        }
    }

    @Test func seedsAreValidAndDistinct() throws {
        let v4 = try command("uuid.v4")
        let seeds = (0..<100).map { _ in v4.makeSeed!(SeedContext()) }
        #expect(Set(seeds).count == 100)
        for seed in seeds {
            var uuid = try #require(UUID(uuidString: seed)).uuid
            let bytes = withUnsafeBytes(of: &uuid) { Array($0) }
            #expect(bytes[6] >> 4 == 4)
            #expect(bytes[8] >> 6 == 0b10)
        }
        let now = Date(timeIntervalSince1970: 1_700_000_000.123)
        let v7 = try command("uuid.v7").makeSeed!(SeedContext(now: now))
        #expect(try output("uuid.v7", seed: v7).fields.first?.value == "2023-11-14T22:13:20.123Z")
        let ulid = try command("uuid.ulid").makeSeed!(SeedContext(now: now))
        #expect(try output("uuid.ulid", seed: ulid).fields.first?.value == "2023-11-14T22:13:20.123Z")
    }

    @Test func generatorsIgnoreAttachedInput() throws {
        let result = try command("uuid.v4").run(ToolRequest(input: .text("{}"), seed: "0f8fad5b-d9cb-469f-a165-70867728950e"))
        #expect(result.output?.primaryText == "0f8fad5b-d9cb-469f-a165-70867728950e")
    }
}
