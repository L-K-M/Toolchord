import Foundation

/// Bounds how many evaluations run at once.
///
/// A cancelled evaluation cannot always stop early: Foundation's Markdown
/// parser, for one, runs to the end. Without a bound, typing in a large
/// document starts a new evaluation for every edit while the superseded ones
/// keep the CPU busy. Waiters are served in order; a waiter whose change was
/// superseded gives its slot to the next one as soon as it resumes.
@MainActor
final class EvaluationSlots {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        precondition(limit >= 1, "At least one evaluation must be able to run")
        self.limit = limit
    }

    /// Evaluations waiting for a slot, including superseded ones that will
    /// pass their slot on.
    var waitingCount: Int { waiting.count }

    /// Waits until a slot is free and takes it. Every call must be balanced
    /// by one ``release()``.
    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Frees a slot, handing it straight to the longest waiter if there is one.
    func release() {
        guard !waiting.isEmpty else {
            running -= 1
            return
        }
        waiting.removeFirst().resume()
    }
}
