import Foundation
import Testing
@testable import ToolchordCore

@Suite struct RandomToolsTests {
    private func command(_ id: String) throws -> ToolCommand {
        try #require(RandomTools.commands.first { $0.id == id })
    }

    private func string(seed: String, options: [String: String]) throws -> ToolOutput {
        let result = try command("random.string").run(ToolRequest(input: .none, options: ToolOptions(options), seed: seed))
        return try #require(result.output, "Expected success, got \(result)")
    }

    private func hexSeed(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    @Test func zeroBytesMapToTheFirstCharacter() {
        let zeros = [UInt8](repeating: 0, count: 512)
        #expect(RandomTools.map(zeros, to: RandomTools.alphanumerics, length: 16) == "AAAAAAAAAAAAAAAA")
        #expect(RandomTools.map(zeros, to: RandomTools.hexDigits, length: 32) == String(repeating: "0", count: 32))
    }

    @Test func biasedBytesAreRejected() {
        // 255 ≥ 248 (the largest multiple of 62 below 256), so it is skipped.
        let bytes: [UInt8] = [0xFF] + [UInt8](repeating: 0x01, count: 511)
        #expect(RandomTools.map(bytes, to: RandomTools.alphanumerics, length: 16) == "BBBBBBBBBBBBBBBB")
        #expect(RandomTools.map([0xFF, 0xFF], to: RandomTools.alphanumerics, length: 1) == nil)
    }

    @Test func symbolsAlphabetAndEntropy() throws {
        let seed = try command("random.string").makeSeed!(SeedContext())
        let output = try string(seed: seed, options: ["length": "64", "characters": "symbols"])
        #expect(output.primaryText.unicodeScalars.count == 64)
        #expect(output.primaryText.unicodeScalars.allSatisfy(RandomTools.symbols.contains))
        #expect(output.fields.first { $0.id == "entropy" }?.value == "415 bits")
        #expect(output.status == "64 characters")
        #expect(!output.status.lowercased().contains("password"))
    }

    @Test func defaultOptionsGiveThirtyTwoAlphanumerics() throws {
        let seed = try command("random.string").makeSeed!(SeedContext())
        let result = try command("random.string").run(ToolRequest(input: .none, seed: seed))
        let text = try #require(result.output?.primaryText)
        #expect(text.unicodeScalars.count == 32)
        #expect(text.unicodeScalars.allSatisfy(RandomTools.alphanumerics.contains))
        #expect(result.output?.fields.first?.value == "190 bits")
    }

    /// Review G1: random strings are used as secrets, lorem ipsum is not.
    @Test func randomStringsAreSecrets() throws {
        for characters in ["alnum", "symbols", "hex"] {
            let output = try string(seed: hexSeed(Array(repeating: 7, count: 512)), options: ["characters": characters])
            #expect(output.sensitivity == .secret)
        }
        let lorem = try command("random.lorem").run(ToolRequest(input: .none, seed: "42"))
        #expect(lorem.output?.sensitivity == .normal)
    }

    /// Review P2: a value copied at one length must not reveal the value at another.
    @Test func optionChangesGiveIndependentValues() throws {
        let seed = try command("random.string").makeSeed!(SeedContext())
        let long = try string(seed: seed, options: ["length": "64", "characters": "hex"]).primaryText
        let short = try string(seed: seed, options: ["length": "16", "characters": "hex"]).primaryText
        #expect(!long.hasPrefix(short))
        let alphanumeric = try string(seed: seed, options: ["length": "16", "characters": "alnum"]).primaryText
        #expect(alphanumeric != short)
        // The same options give the same value, so it stays stable on screen.
        #expect(try string(seed: seed, options: ["length": "64", "characters": "hex"]).primaryText == long)
    }

    @Test func seedsAreSecureLengthAndDistinct() throws {
        let make = try #require(try command("random.string").makeSeed)
        let seeds = (0..<20).map { _ in make(SeedContext()) }
        #expect(Set(seeds).count == 20)
        #expect(seeds.allSatisfy { $0.utf8.count == 1024 })
    }

    @Test func missingSeedAsksToRegenerate() throws {
        for id in ["random.string", "random.lorem"] {
            if case .needsInput = try command(id).run(ToolRequest(input: .none, seed: nil)) {} else { Issue.record("Expected needsInput for \(id)") }
            if case .needsInput = try command(id).run(ToolRequest(input: .none, seed: "zz")) {} else { Issue.record("Expected needsInput for \(id)") }
        }
    }

    @Test func loremSentenceIsTheClassicOpening() throws {
        let result = try command("random.lorem").run(ToolRequest(input: .none, options: ToolOptions(["length": "sentence"]), seed: "42"))
        #expect(result.output?.primaryText == "Lorem ipsum dolor sit amet, consectetur adipiscing elit.")
        #expect(result.output?.status == "8 words")
    }

    @Test func loremIsDeterministicPerSeed() throws {
        let lorem = try command("random.lorem")
        let request = ToolRequest(input: .none, options: ToolOptions(["length": "five"]), seed: "12345")
        let first = try #require(lorem.run(request).output?.primaryText)
        #expect(lorem.run(request).output?.primaryText == first)
        let paragraphs = first.components(separatedBy: "\n\n")
        #expect(paragraphs.count == 5)
        #expect(paragraphs[0].hasPrefix("Lorem ipsum dolor sit amet, consectetur adipiscing elit. "))
        #expect(!first.hasSuffix(" ") && !first.hasSuffix("\n"))
        let other = lorem.run(ToolRequest(input: .none, options: ToolOptions(["length": "five"]), seed: "54321")).output?.primaryText
        #expect(other != first)
    }

    @Test func loremSentencesFollowTheShape() throws {
        let text = RandomTools.lorem(paragraphs: 3, seed: 7)
        for paragraph in text.components(separatedBy: "\n\n") {
            let sentences = paragraph.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            #expect((4...7).contains(sentences.count))
            for sentence in sentences.dropFirst() {
                let words = sentence.split(separator: " ")
                #expect((6...14).contains(words.count))
                #expect(words[0].first?.isUppercase == true)
                #expect(sentence.filter { $0 == "," }.count <= 1)
            }
        }
    }
}
