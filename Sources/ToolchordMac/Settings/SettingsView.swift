import AppKit
import SwiftUI

/// Shortcut choices shared by Settings and the welcome window.
struct ShortcutSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ShortcutRecorder(
                    shortcut: model.shortcut,
                    onRecord: { model.setShortcut($0) },
                    onProblem: { model.reportRecorderProblem($0) }
                )
                .frame(width: 168, height: 26)
                statusLabel
            }
            HStack(spacing: 8) {
                Text("Suggestions:")
                    .foregroundStyle(.secondary)
                ForEach([KeyboardShortcut.optionShiftSpace, .controlCommandSpace, .controlOptionCommandSpace], id: \.self) { candidate in
                    Button(candidate.displayString) { model.setShortcut(candidate) }
                        .controlSize(.small)
                        .disabled(candidate == model.shortcut && model.isShortcutActive)
                        .accessibilityLabel("Use \(candidate.accessibilityLabel)")
                }
            }
            .font(.system(size: 12))
            if let problem = model.shortcutProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let note = model.shortcut.conflictNote {
                Text(note)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if model.isShortcutActive {
            Label("Active", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
                .font(.system(size: 12))
        } else {
            Label("Not active", systemImage: "xmark.circle.fill")
                .foregroundStyle(Theme.failure)
                .font(.system(size: 12))
        }
    }
}

struct SettingsView: View {
    let model: AppModel
    @Bindable var preferences: AppPreferences

    init(model: AppModel) {
        self.model = model
        self.preferences = model.preferences
    }

    var body: some View {
        Form {
            Section {
                ShortcutSection(model: model)
            } header: {
                Text("Keyboard Shortcut")
            } footer: {
                Text("Press the shortcut over any app to open Toolchord. You can always open it from the menu bar too.")
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { model.loginItemState == .enabled || model.loginItemState == .requiresApproval },
                    set: { model.setOpensAtLogin($0) }
                ))
                .disabled(isLoginItemUnavailable)
                loginItemNote
                Toggle("Show in menu bar", isOn: $preferences.showsMenuBarIcon)
                if !preferences.showsMenuBarIcon {
                    Text("To open Settings later, open Toolchord again from Finder or Spotlight.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tools") {
                Picker("JSON and XML indentation", selection: $preferences.indent) {
                    ForEach(AppPreferences.Indent.allCases) { indent in
                        Text(indent.label).tag(indent)
                    }
                }
                Toggle("Show recently used tools", isOn: $preferences.remembersRecents)
                if preferences.remembersRecents && !preferences.recentCommandIDs.isEmpty {
                    Button("Clear Recent Tools") { preferences.clearRecents() }
                        .controlSize(.small)
                }
            }

            Section("Privacy") {
                Label {
                    Text("Toolchord processes everything on this Mac and has no network access. It reads the clipboard only when you paste, keeps your input in memory only while the palette is open, and never stores or logs it. Results you copy go to the system clipboard, which macOS may share with your other devices through Universal Clipboard. Generated random strings stay on this Mac and are marked as confidential for clipboard history apps.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.system(size: 12))
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshLoginItem() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refreshLoginItem()
        }
    }

    private var isLoginItemUnavailable: Bool {
        if case .unavailable = model.loginItemState { return true }
        return false
    }

    @ViewBuilder
    private var loginItemNote: some View {
        switch model.loginItemState {
        case .requiresApproval:
            HStack {
                Text("Approve Toolchord in Login Items to finish.")
                Button("Open Login Items") { LoginItem.openSystemSettings() }
                    .controlSize(.small)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        case .unavailable(let reason):
            Text(reason).font(.system(size: 12)).foregroundStyle(.secondary)
        case .enabled, .disabled:
            EmptyView()
        }
        if let error = model.loginItemError {
            Text(error).font(.system(size: 12)).foregroundStyle(Theme.failure)
        }
    }
}

struct WelcomeView: View {
    let model: AppModel
    let onTry: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Toolchord")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Developer tools a shortcut away.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Your shortcut")
                    .font(.system(size: 13, weight: .semibold))
                ShortcutSection(model: model)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How it works")
                    .font(.system(size: 13, weight: .semibold))
                step(1, "Press \(model.shortcut.displayString) over any app.")
                step(2, "Press ⌘V to attach the clipboard. Toolchord suggests tools for what you pasted, with a live preview.")
                step(3, "Press ⌘↵ to copy the result and go straight back to your work. Press ↵ to open a tool with an editor.")
            }

            Label("Toolchord processes everything on this Mac, has no network access, and reads the clipboard only when you paste. Results you copy go to the system clipboard.", systemImage: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Try It Now", action: onTry)
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.chip))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
