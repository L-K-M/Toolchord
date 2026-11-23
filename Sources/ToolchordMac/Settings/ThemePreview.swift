import AppKit
import Observation
import SwiftUI
import ToolchordSession

/// The real palette drawn with the current theme, in its own glass, over
/// a sample desktop: Settings ▸ Appearance's live preview. It shows a demo
/// session and takes no clicks or keys.
struct ThemePreview: View {
    /// Smaller than the panel so it fits beside the controls; the layout
    /// keeps the panel's proportions.
    static let size = CGSize(width: 600, height: 364)

    let style: PaletteStyle
    let scenario: ThemePreviewScenario
    let backdrop: ThemePreviewBackdrop
    @State private var sessions = ThemePreviewSessions()

    var body: some View {
        ZStack {
            backdrop.view
            if let session = sessions.ready[scenario] {
                PalettePreviewHost(session: session, style: style)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: scenario) { await sessions.prepare(scenario) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the palette in this theme")
    }
}

/// What the preview shows. Between them, the scenarios draw every color a
/// theme sets.
enum ThemePreviewScenario: String, CaseIterable, Identifiable {
    case json
    case xml
    case fields
    case error
    case editor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .json: "JSON"
        case .xml: "XML"
        case .fields: "Fields"
        case .error: "Error"
        case .editor: "Editor"
        }
    }

    @MainActor
    func setUp(_ session: PaletteSession) {
        switch self {
        case .json:
            session.attach(#"{"requestId":"req_81f2","status":200,"cache":"HIT","items":[1,2.50,-0],"ok":true,"next":null}"#)
        case .xml:
            session.attach(#"<!-- feed --><feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Release notes</title><entry id="42"><![CDATA[<b>bold</b>]]></entry></feed>"#)
        case .fields:
            session.setQuery("jwt")
            session.attach("Bearer eyJhbGciOiJub25lIn0.eyJleHAiOjAsIm5iZiI6NDEwMjQ0NDgwMH0.")
        case .error:
            session.attach("{\n  \"status\": 200,\n  \"cache\": HIT\n}")
        case .editor:
            session.attach(#"{"requestId":"req_81f2","status":200,"cache":"HIT"}"#)
            session.openSelected()
        }
    }
}

/// What the preview draws behind the palette, so translucent surfaces can
/// be judged over a busy desktop as well as plain ones.
enum ThemePreviewBackdrop: String, CaseIterable, Identifiable {
    case wallpaper
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wallpaper: "Wallpaper"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .wallpaper:
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.55, blue: 0.62), Color(red: 0.36, green: 0.24, blue: 0.62), Color(red: 0.95, green: 0.55, blue: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            Color(white: 0.93)
        case .dark:
            Color(white: 0.12)
        }
    }
}

/// One demo session per scenario, made on first use and kept, so switching
/// back is instant.
@MainActor
@Observable
private final class ThemePreviewSessions {
    private(set) var ready: [ThemePreviewScenario: PaletteSession] = [:]

    func prepare(_ scenario: ThemePreviewScenario) async {
        guard ready[scenario] == nil else { return }
        let session = PaletteSession.demo()
        scenario.setUp(session)
        await session.waitForIdle()
        ready[scenario] = session
    }
}

private struct PalettePreviewHost: NSViewRepresentable {
    let session: PaletteSession
    let style: PaletteStyle

    func makeNSView(context: Context) -> PalettePreviewView {
        PalettePreviewView(session: session, style: style)
    }

    func updateNSView(_ view: PalettePreviewView, context: Context) {
        view.show(session, style: style)
    }
}

/// The palette in its material. It returns no view from hit testing, so
/// clicks and scrolling never reach the demo session.
private final class PalettePreviewView: NSView {
    private let hosting: NSHostingView<AnyView>
    private let surface: PaletteSurface
    private var session: PaletteSession
    private var style: PaletteStyle

    init(session: PaletteSession, style: PaletteStyle) {
        self.session = session
        self.style = style
        hosting = NSHostingView(rootView: Self.root(session: session, style: style))
        surface = PaletteSurface(content: hosting, blending: .withinWindow)
        super.init(frame: .zero)
        let material = surface.view
        material.translatesAutoresizingMaskIntoConstraints = false
        addSubview(material)
        NSLayoutConstraint.activate([
            material.leadingAnchor.constraint(equalTo: leadingAnchor),
            material.trailingAnchor.constraint(equalTo: trailingAnchor),
            material.topAnchor.constraint(equalTo: topAnchor),
            material.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        surface.apply(style)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }

    func show(_ session: PaletteSession, style: PaletteStyle) {
        guard session !== self.session || style != self.style else { return }
        self.session = session
        self.style = style
        surface.apply(style)
        hosting.rootView = Self.root(session: session, style: style)
    }

    private static func root(session: PaletteSession, style: PaletteStyle) -> AnyView {
        AnyView(
            PaletteView(
                session: session,
                actions: InertPaletteActions(),
                focus: PaletteFocus(),
                isNarrow: false,
                listWidth: style.listWidth(forPanelWidth: ThemePreview.size.width),
                style: style
            )
            .environment(\.isPalettePreview, true)
        )
    }
}
