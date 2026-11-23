# Developer utility research and tool priorities

Research checked **12 November 2026** using publisher websites, store listings, documentation, source catalogs, and Apple developer documentation and forums. Install counts are cumulative figures shown on each page on that date.

## Positioning

Native execution, offline processing, clipboard detection, and command search already exist in competing products. Toolchord's bet is narrower: a preview beside the command list and a single **Copy & Close** shorten the path from invoking the palette to resuming work, without a separate app window or a background clipboard reader. [Product plan](product-plan.md)

| Product | What the primary source establishes | Implication for Toolchord |
| --- | --- | --- |
| [IT Tools](https://it-tools.tech/) · [catalog](https://github.com/CorentinTh/it-tools/blob/main/src/tools/index.ts) | 86 browser tools in 10 categories; 85 run fully offline. Latest release 2024-10-22; 369 open PRs, 167 of them proposing new tools. The [sharevb fork](https://github.com/sharevb/it-tools) is the only active large fork, with 479 tools. Both are GPL-3.0. | A broad catalog of jobs, but maintenance stalled. Toolchord's public-domain license means reimplementing behavior, never porting code. |
| [DevUtils](https://devutils.com/) | 47 native Mac tools, offline. "Smart Detection" picks a tool from the clipboard content. Opened from the status bar or a Services hotkey (⌘\\). | The closest native competitor. Toolchord detects only after an explicit paste, so it never reads the clipboard on its own. |
| [DevToys](https://devtoys.app/) | Free, open source, Windows/macOS/Linux, 30 default tools plus extensions. Smart Detection marks suitable tools and can auto-paste when only one matches. | Confirms the consensus catalog. Its "suitable tools" lightbulb inspired Toolchord's "Suggested for …" section. |
| [Devly](https://devly.techfixpro.net/) | 65 tools, menu-bar dropdown on ⌃⌥⌘D, ⌘↵ runs a tool, ⇧⌘C copies output, ⌘P quick-switches. One-time purchase; Liquid Glass on macOS 26+. | Validates a global hotkey and keyboard-first copy. Toolchord removes the separate "run" step: the preview is always live. |
| [Anvil Command Center](https://anvilmac.com/en/events/command-center/) | A searchable palette of tools and clipboard actions in a universal Mac/iPad app. | Palettes for developer tools are an emerging pattern; differentiation is in result handling, not in having a palette. |
| [Raycast action panel](https://manual.raycast.com/action-panel) · [search](https://manual.raycast.com/search-bar) | ↵ runs the first ("primary") action; ⌘K opens all actions with fuzzy search; root search ranks by frecency. | Toolchord names its primary action in the footer, keeps secondary actions on ⌘K, and remembers recent tools (IDs only). |
| [Spotlight shortcuts, macOS 27](https://support.apple.com/guide/mac-help/spotlight-keyboard-shortcuts-mh26783/mac) | ⌘Space opens Spotlight; ⌘1–⌘4 filter Applications, Files, Actions, and Clipboard; quick keys run actions. | Spotlight now covers actions and clipboard history, so Toolchord focuses on transforming text, not launching things. |

## Demand signals

Raycast store installs (primary) and VS Code Marketplace unique installs (secondary, skewed toward editing files):

| Job | Raycast | VS Code |
| --- | --- | --- |
| JSON formatting | [Format JSON](https://www.raycast.com/destiner/json-format) 105,633 | [Prettify JSON](https://marketplace.visualstudio.com/items?itemName=mohsen1.prettify-json) 2,986,642 |
| Lorem ipsum | [Lorem Ipsum](https://www.raycast.com/AntonNiklasson/lorem-ipsum) 115,832 | [Lorem ipsum](https://marketplace.visualstudio.com/items?itemName=Tyriar.lorem-ipsum) 1,103,135 |
| Case conversion | [Change Case](https://www.raycast.com/erics118/change-case) 57,334 | [change-case](https://marketplace.visualstudio.com/items?itemName=wmaurer.change-case) 1,843,067 |
| Random strings and passwords | [Password Generator](https://www.raycast.com/joshuaiz/password-generator) 44,793 | [Random String Generator](https://marketplace.visualstudio.com/items?itemName=bibhasdn.random-string-password-generator) 11,275 |
| Word and character counts | [Word Count](https://www.raycast.com/itsmingjie/word-count) 44,321 | [WordCounter](https://marketplace.visualstudio.com/items?itemName=kirozen.wordcounter) 58,243 |
| Base64 | [Base64](https://www.raycast.com/DanielSinclair/base64) 44,003 | [vscode-base64](https://marketplace.visualstudio.com/items?itemName=adamhartford.vscode-base64) 345,479 |
| UUID and ULID | [UUID Generator](https://www.raycast.com/jmaeso/uuid-generator) 37,487 | [Insert GUID](https://marketplace.visualstudio.com/items?itemName=heaths.vscode-guid) 188,538 |
| Unix timestamps | [Unix Timestamp](https://www.raycast.com/destiner/unix-timestamp) 32,920 | [Time Converter](https://marketplace.visualstudio.com/items?itemName=HaaLeo.timing) 20,549 |
| JWT decoding | [JWT Decoder](https://www.raycast.com/gdsmith/jwt-decoder) 19,085 | [jwt-decoder](https://marketplace.visualstudio.com/items?itemName=jflbr.jwt-decoder) 62,681 |
| URL encode and decode | [URL Tools](https://www.raycast.com/huzef44/url-tools) 14,694 | [URL Encode](https://marketplace.visualstudio.com/items?itemName=flesler.url-encode) 83,517 |
| Sorting and deduplicating lines | [Deduplicator](https://www.raycast.com/HerbertLu/deduplicator) 574 | [Sort lines](https://marketplace.visualstudio.com/items?itemName=Tyriar.sort-lines) 1,203,189 |
| String escaping | — | [vscode-json](https://marketplace.visualstudio.com/items?itemName=andyyaldoo.vscode-json) 291,119 |
| XML formatting | no standalone extension | [XML Tools](https://marketplace.visualstudio.com/items?itemName=DotJoshJohnson.xml) 8,178,322 |
| Color conversion (text) | [Web Converter](https://www.raycast.com/nielsvanrijn/web-converter) 9,068 | [Change Color Format](https://marketplace.visualstudio.com/items?itemName=bbugh.change-color-format) 60,690 |
| Hashing | [Encoding Tools](https://www.raycast.com/eth-p/encoding-tools) 5,810 | [Hasher](https://marketplace.visualstudio.com/items?itemName=deerawan.vscode-hasher) 19,309 |
| HTML entities | — | [html-entities](https://marketplace.visualstudio.com/items?itemName=christopherstyles.html-entities) 37,465 |
| Number bases | [Converter](https://www.raycast.com/koinzhang/converter) 5,116 | [Hex Hover Converter](https://marketplace.visualstudio.com/items?itemName=maziac.hex-hover-converter) 34,987 |
| Text diff | [Diff Checker](https://www.raycast.com/destiner/diff-checker) 22,628 | [Partial Diff](https://marketplace.visualstudio.com/items?itemName=ryu1kn.partial-diff) 1,403,251 |
| QR codes | [QR Code Generator](https://www.raycast.com/Melvynx/qrcode-generator) 39,645 | [QR Code Generator](https://marketplace.visualstudio.com/items?itemName=Compulim.vscode-qrcode) 19,930 |
| Regex | [Regex Tester](https://www.raycast.com/allenan/regex-tester) 14,019 | [Regex Previewer](https://marketplace.visualstudio.com/items?itemName=chrmarti.regex) 1,019,273 |
| Time zones | [Timezone Converter](https://www.raycast.com/joao.mainka/raycast-timezone-converter) 22,953 | — |
| Cron | [Cron Description](https://www.raycast.com/niall-maloney/cron-description) 4,210 | [Cron Explained](https://marketplace.visualstudio.com/items?itemName=tumido.cron-explained) 20,075 |

Every tool in the original first release except XML has a dedicated Raycast extension with solid demand; XML's demand shows up in editors. Single-purpose tools outdraw bundles: DevUtils' Raycast launcher has 27,144 installs and CyberChef 11,055. The Alfred Gallery shows no popularity counts.

IT Tools' most-reacted requests point the same way: regex (33), SSH keys (8), byte units (7), IPv6 (6), certificates (5), UUID v6/v7 (4), and time zones (10 upvotes). Only one request exceeds 11 reactions.

## Consensus catalog

Tools offered by at least three of IT Tools, DevUtils, DevToys, Devly, and Boop are the consensus core. Toolchord's fit test stays the same: paste text (or nothing), get one copyable text result, with at most two options.

| Status | Tools | Why |
| --- | --- | --- |
| **First release** (original plan) | JSON format, minify, validate · XML format, validate · Base64 and Base64URL · URL component encode/decode and URL inspection · JWT inspection · Unix time ↔ RFC 3339 · UUID v4 | Consensus core with strong demand; already specified. |
| **First release** (added after this research) | JSON string escape/unescape · case conversion and slugs · sort, deduplicate, and reverse lines · HTML entity escape/unescape · number base conversion · text ↔ hex · SHA-256, SHA-512, SHA-1, MD5 · character, word, line, and byte counts · CSS color conversion · current time · UUID v7 and ULID · random strings · lorem ipsum | Consensus tools with high demand (case 57k, word count 44k, lorem 116k, random strings 45k) that fit the same paste → preview → copy flow, need no new result type, and run on Foundation and CryptoKit alone. |
| **First release** (added on request) | Make Plain Text (hidden characters, typographic spaces, smart punctuation) · HTML → plain text · Markdown → plain text · Markdown → HTML | Requested after the first review. They fit the same flow with at most two options, and Markdown parsing uses Foundation's built-in parser (cmark-gfm), so they add no third-party code. |
| **Deferred: larger editor** | Regex testing, text diff, JSONPath/jq, SQL formatting | High demand, but they need two inputs, a results table, or language-aware formatting. |
| **Deferred: vetted parser needed** | JSON ↔ YAML, TOML, CSV | Lossless YAML parsing (implicit typing, anchors) needs a vetted parser; Foundation has none, and Toolchord ships without third-party code. |
| **Deferred: new result type** | QR codes (image), certificate inspection (rich structure), cron explanations (prose generation) | Each needs new UI or a large rule set. |
| **Not planned** | Network lookups, file and image converters, reference cheat sheets | Need network access or files, or aren't transforms. |

## macOS platform constraints

| Topic | Finding | Decision |
| --- | --- | --- |
| Hotkeys | `RegisterEventHotKey` needs no Accessibility or Input Monitoring permission and works in the App Sandbox. macOS 15.0–15.1 rejected Option-only and Option-Shift-only hotkeys for sandboxed apps with error −9868; [Apple reverted this in 15.2](https://developer.apple.com/forums/thread/763878). | Default to ⌥⇧Space; if registration fails on first launch, fall back to ⌃⌥⌘Space. Settings explain failures. |
| ⌃⌘Space | Opens [Character Viewer / Emoji & Symbols](https://support.apple.com/en-us/102650) through each app's Edit menu. A global hotkey takes it over everywhere. | Offered as a one-click choice with that note, not as the default. |
| Pasteboard privacy | macOS can alert when an app [reads the general pasteboard programmatically](https://lapcatsoftware.com/articles/2025/5/3.html) unless the read follows paste-related input. `detect` APIs inspect types without reading. macOS 27.2 removed the developer-preview flag. | Read only inside the Paste command (⌘V or Edit › Paste); never on open. The ⌘V button sends the same paste action. |
| Non-activating panels | An `NSPanel` with `.nonactivatingPanel` becomes key without activating its app; the previous app stays active and owns the menu bar. The flag must be set at initialization ([details](https://philz.blog/nspanel-nonactivating-style-mask-flag/)). | Focus returns to the originating app automatically on close; reactivation is only needed if Toolchord became active. |
| Target display | `NSScreen.main` in an accessory app can report the menu-bar display ([FB11506568](https://github.com/feedback-assistant/reports/issues/355)). `CGWindowListCopyWindowInfo` bounds are available without Screen Recording permission. | Place the panel on the display of the frontmost app's topmost window, falling back to the pointer's display. |
| Login items | `SMAppService.mainApp` needs an app bundle; users can disable it in System Settings, and App Review requires opt-in. | Off by default; status is read from the system each time. |
| Screen lock | `com.apple.screenIsLocked` is not documented API ([DTS](https://developer.apple.com/forums/thread/686011)). | Dismiss on it as a best-effort signal, plus documented session-resign, sleep, and display-sleep notifications. |
| Liquid Glass and icons | macOS 26 adds `NSGlassEffectView`; it [wraps non-squircle icons in a gray squircle](https://lapcatsoftware.com/articles/2025/6/2.html). Xcode 26+ compiles Icon Composer `.icon` documents with fallbacks for earlier systems. | Glass panel on macOS 26+, `NSVisualEffectView` on 14–15; the app icon is a generated `.icon` document. |

## Validation before catalog expansion

The interaction study from the original plan still applies. Run a formative comparison with developers who use web utilities, native toolboxes, or launcher extensions, using the same non-sensitive fixtures across products.

1. **JSON.** Format a minified response and return to the source editor with the result on the clipboard.
2. **XML.** Format a compact document, preserve whitespace-sensitive text, then locate a mismatched tag using Validate XML.
3. **Base64.** Decode non-ASCII text, then confirm that malformed input prevents copying the previous result.
4. **JWT.** Find the expiry and copy one claim. Ask the participant what the signature status means.
5. **UUID.** Generate and copy a UUID from an empty panel.
6. **Discovery.** Find `epoch`, `pretty print`, `GUID`, and `snake case` using search.

Measure from invocation until the correct output is on the clipboard and focus has returned. Record keystrokes, errors, wrong copy targets, and focus failures with the app and macOS versions. Choose the deferred tools to build next from where participants still reach for another tool.
