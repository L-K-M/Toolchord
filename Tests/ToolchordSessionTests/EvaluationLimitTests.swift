import Foundation
import Testing
import ToolchordCore
@testable import ToolchordSession

/// Review P1: superseded evaluations that cannot stop early must not pile up
/// while the user keeps editing.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct EvaluationLimitTests {
    let a = #"{"a":1}"#, b = #"{"b":2}"#, c = #"{"c":3}"#, d = #"{"d":4}"#

    func makeSession(_ gate: GatedEvaluator) -> PaletteSession {
        let session = PaletteSession(evaluator: gate, clipboard: MemoryClipboard(), preferences: MemoryPreferences())
        session.editDebounce = .zero
        session.activate()
        session.setQuery("minify json")
        return session
    }

    /// Attaches `a` and then `b`, each reaching the evaluator, so two
    /// evaluations are in flight and `a` is already superseded.
    private func startTwoEvaluations(_ session: PaletteSession, _ gate: GatedEvaluator) async {
        session.attach(a)
        await gate.waitForPending(1)
        session.attach(b)
        await gate.waitForPending(2)
    }

    private func waitUntilQueued(_ session: PaletteSession, _ count: Int) async {
        while session.queuedEvaluationCount < count { await Task.yield() }
    }

    @Test func atMostTwoEvaluationsRunAtOnce() async {
        let gate = GatedEvaluator()
        let session = makeSession(gate)
        await startTwoEvaluations(session, gate)
        session.attach(c)
        await waitUntilQueued(session, 1)
        #expect(await gate.pendingInputs == [a, b])

        // A finished superseded evaluation frees its slot for the newest change.
        await gate.release(input: a)
        await gate.waitForPending(2)
        #expect(await gate.pendingInputs == [b, c])
        await gate.release(input: c)
        await session.waitForIdle()
        #expect(session.copyableOutput?.primaryText == c)

        await gate.releaseAll()
        for _ in 0..<20 { await Task.yield() }
        #expect(session.copyableOutput?.primaryText == c)
        #expect(session.queuedEvaluationCount == 0)
    }

    @Test func changesSupersededWhileWaitingNeverReachTheEvaluator() async {
        let gate = GatedEvaluator()
        let session = makeSession(gate)
        await startTwoEvaluations(session, gate)
        session.attach(c)
        await waitUntilQueued(session, 1)
        session.attach(d)
        await waitUntilQueued(session, 2)

        await gate.release(input: a)
        await gate.waitForPending(2)
        #expect(await gate.pendingInputs == [b, d])
        #expect(session.queuedEvaluationCount == 0)

        await gate.releaseAll()
        await session.waitForIdle()
        #expect(session.copyableOutput?.primaryText == d)
    }
}
