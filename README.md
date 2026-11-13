# Toolchord

> [!IMPORTANT]
> LLM disclosure: This codebase was written with substantial help from large language models: AI coding agents working from the [`AGENTS.md`](AGENTS.md) brief in this repo.

Developer tools a shortcut away. Toolchord is a native macOS palette for the small jobs between edits: format an API response, decode a token, convert a timestamp, or generate an ID. Press **⌥⇧Space** over any app, press **⌘V**, read the live preview, and press **⌘↵** to copy the result and go straight back to work.

**Latest release:** v<!-- version -->1.0<!-- /version --> · [Download](https://github.com/L-K-M/Toolchord/releases/latest)

![Toolchord with pasted JSON: suggested tools on the left, a syntax-colored preview on the right, and Copy JSON & Close in the footer.](docs/images/search-json.png)

## What it does

56 commands in 18 tool families, all offline:

- **JSON** — format, minify, and validate without changing a single number or key order; escape and unescape string literals.
- **XML** — format structure while keeping mixed content and preserved whitespace intact; well-formedness and namespace checks.
- **Encoding** — Base64 and Base64URL, URL components, HTML entities, text ↔ hex.
- **Inspection** — URLs with every query parameter, JWT headers and claims with readable expiry, character and word counts.
- **Conversion** — Unix time ↔ RFC 3339, number bases at any size, hex/`rgb()`/`hsl()` colors, ten case styles and slugs.
- **Generation** — UUID v4 and v7, ULID, secure random strings, lorem ipsum, the current time.
- **Lines and hashes** — sort, deduplicate, and reverse lines; SHA-256, SHA-512, SHA-1, and MD5.
- **Plain text and Markdown** — strip hidden characters, non-breaking spaces, and smart quotes from copied text; turn HTML or Markdown into readable plain text; render Markdown to HTML.

Paste something and Toolchord suggests the tools that fit it. Every result shows exactly what ⌘↵ will copy, errors point to the line and column, and inspectors give each field its own Copy button.

## Privacy

Toolchord processes everything on your Mac. It runs in the App Sandbox **without network access**, so the app itself can't send your input anywhere. It reads the clipboard only when you paste, keeps your input in memory only while the palette is open, and never stores or logs it. Results you copy go to the standard system clipboard, which macOS may share with your other devices through [Universal Clipboard](https://support.apple.com/en-us/102430). Generated random strings are the exception: they stay on this Mac and are marked as confidential, which asks clipboard history apps that follow the [nspasteboard.org](http://nspasteboard.org) convention not to keep or show them.

## Requirements

- macOS 14 Sonoma or later (Liquid Glass on macOS 26 and later)
- To build: Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build and run

```bash
make run
```

This generates `Toolchord.xcodeproj` from `project.yml`, builds a release app into `build/DerivedData`, and opens it. To install it, use `make install`, which copies the app to `/Applications`. Local builds are ad-hoc signed; set your team in `project.yml` to sign for distribution.

To work in Xcode, run `make project` and open `Toolchord.xcodeproj`.

For the shared build and release entry points, install the current
[lkm-build and lkm-release engines](https://github.com/L-K-M/release-tool)
by running `./install.sh` in that repository, then use:

```bash
scripts/build.sh --install
scripts/release.sh 1.0.1          # bump project.yml + README and create a local tag
scripts/release.sh 1.0.2 --push   # also push the commit and tag to publish zip + DMG
```

The build script requires App Sandbox support from the engine. The release
script generates the Xcode project first; nothing is published without `--push`.

## Use

| Key | Action |
| --- | --- |
| ⌥⇧Space | Open Toolchord over any app (change it in Settings; ⌃⌘Space is one click away) |
| ⌘V | Attach the clipboard as input |
| ↑ ↓ | Choose a tool; the preview follows |
| ⌘↵ | Copy the result and close |
| ↵ | Open the tool with an editor |
| ⌘K | Actions: copy without closing, options, regenerate, and more |
| esc | Back, or close |

Settings (from the menu bar icon or ⌘, in the palette) cover the shortcut, opening at login, the menu bar icon, JSON and XML indentation, and recent tools.

## Develop

```bash
make test
```

More than 400 tests cover every tool fixture, a robustness sweep that runs each command against awkward input, the session's stale-result and copy rules, and the Mac layer's logic.

```bash
make snapshots
```

This renders palette states to `build/snapshots` for design review. `make benchmark` times every command on 10 KiB and 1 MiB inputs.

| Directory | Contents |
| --- | --- |
| `Sources/ToolchordCore` | Tool commands, input detection, and search ranking (Foundation and CryptoKit only) |
| `Sources/ToolchordSession` | The palette draft: selection, evaluation scheduling, and copy gating |
| `Sources/ToolchordMac` | Panel, global shortcut, pasteboard, SwiftUI views, Settings, and the snapshot renderer |
| `App`, `project.yml` | The app target: Info.plist keys, sandbox entitlements, and the Icon Composer icon |

To add a tool, follow `Sources/ToolchordCore/Tools/HashTools.swift`: declare commands with IDs, aliases, options, a copy noun, and an affinity for detected input, then register the module in `ToolCatalog`.

## Documentation

- [Product plan](docs/product-plan.md): scope, panel layout, keyboard behavior, and acceptance checks
- [Shortcut UX](docs/shortcut-ux.md): search, paste, keys, and copy targets
- [Implementation contracts](docs/implementation-contracts.md): tool contracts, fixtures, and native decisions
- [Research](docs/research.md): competitors, demand, the catalog decision, and macOS constraints
- [Design review](docs/design-review.md): how the proposed mockups shaped the panel

**Status:** first release implemented. Toolchord is a working name.

## License

Toolchord's own code is released into the public domain under [The Unlicense](LICENSE).
