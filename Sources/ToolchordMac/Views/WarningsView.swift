import SwiftUI

/// Keeps a short summary inline and makes every diagnostic inspectable.
struct WarningsView: View {
    let warnings: [String]
    @Binding var isExpanded: Bool

    private let summaryCount = 3

    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if warnings.count <= summaryCount {
                    rows(warnings)
                } else {
                    if !isExpanded {
                        rows(Array(warnings.prefix(summaryCount)))
                    }
                    DisclosureGroup(isExpanded: $isExpanded) {
                        // Replaces the summary rather than extending it, so a
                        // long list leaves room for the result and its fields.
                        ScrollView {
                            rows(warnings)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 100)
                        .focusable()
                        .accessibilityLabel("All warnings")
                    } label: {
                        Text(disclosureTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var disclosureTitle: String {
        if isExpanded { return "All \(warnings.count) warnings" }
        let remaining = warnings.count - summaryCount
        return remaining == 1 ? "1 more warning" : "\(remaining) more warnings"
    }

    private func rows(_ messages: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(messages.enumerated()), id: \.offset) { _, warning in
                Label {
                    Text(warning)
                        .font(.system(size: 11.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                }
            }
        }
    }
}
