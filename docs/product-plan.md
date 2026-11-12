# Toolchord product plan and design

Toolchord is a native macOS command palette for the small tasks developers do between edits: format an API response, check when a token expires, decode a value, convert a timestamp, or generate an ID. Press a shortcut over any app, paste, read the live preview, and press ⌘↵ to copy the result and go straight back to work.

The [shortcut UX](shortcut-ux.md) specifies panel behavior. The [implementation contracts](implementation-contracts.md) define results, copy targets, format rules, and fixtures. The [research](research.md) covers competitors, demand, and macOS constraints, and the [design review](design-review.md) explains how the proposed mockups shaped the final panel.

**Status:** implemented. The app, its 56 commands, and 458 automated tests are in this repository; see the [README](../README.md) to build and run it.

![Toolchord with pasted JSON: suggested tools on the left, a syntax-colored preview on the right, and Copy JSON & Close in the footer.](images/search-json.png)

## First release

Seven core tools from the original plan, plus the consensus tools that research showed fit the same paste → preview → copy flow. **Scope decision (12 November 2026):** the first release ships every family below; the original seven remain the core workflows for the [validation study](research.md#validation-before-catalog-expansion).

| Tool | Commands and result |
| --- | --- |
| **JSON** | Format (2 spaces, 4 spaces, or tab), minify, or validate, preserving every token's spelling, member order, and duplicate names. Escape text as a JSON string literal, or unescape one. Errors give a line, column, and the offending line with a caret. |
| **XML** | **Format XML** indents structural markup only, preserving mixed content, `xml:space="preserve"` regions, comments, CDATA, and processing instructions. **Validate XML** checks XML 1.0 well-formedness and namespaces. A DOCTYPE gets a distinct unsupported message, and nothing is ever fetched or expanded. |
| **Base64** | Encode and decode with the standard alphabet (padded) or Base64URL (unpadded), as separate commands so the alphabet is always explicit. Strict decoding, optional whitespace tolerance, and a clear error for non-UTF-8 bytes. |
| **URL** | Percent-encode or decode a component once. **Inspect URL** shows scheme, host, port, path, and fragment, plus every query parameter in order with its own Copy control; the primary result is the ordered parameter list as JSON. |
| **JWT** | Decode the header and claims with **Signature unverified** shown as a warning, a readable expiry, a field per claim, and tolerance for a pasted `Bearer` prefix. |
| **Time** | Unix seconds or milliseconds (explicit unit) to RFC 3339 UTC, with local time and a relative description; RFC 3339 dates (offset required) to Unix time; and the current time, captured once. |
| **Identifiers** | UUID v4, UUID v7 (with its embedded timestamp), and ULID. Each stays stable on screen until **Regenerate** (⌘R). |
| **Random** | Random strings from the system's secure generator (length and alphabet options) and lorem ipsum (sentence to five paragraphs). |
| **Hash** | SHA-256, SHA-512, SHA-1, and MD5 of the UTF-8 text, with a warning on the legacy algorithms. |
| **Text** | camelCase, PascalCase, snake_case, kebab-case, CONSTANT_CASE, Title Case, Sentence case, lowercase, UPPERCASE, and slugs; sort, deduplicate, or reverse lines; HTML entity escape and unescape; character, word, line, byte, UTF-16, and scalar counts. |
| **Plain text and Markdown** | **Make Plain Text** removes invisible characters and typographic spaces, and optionally straightens quotes and dashes, so text copied from documents and web pages works in code and terminals. HTML or Markdown → readable plain text, and Markdown → HTML (CommonMark with GitHub tables, strikethrough, autolinks, and task lists). |
| **Numbers and color** | Arbitrary-precision decimal, hex, binary, and octal; text ↔ hex bytes; hex, `rgb()`, and `hsl()` color conversion with a swatch. |

Deferred tools and the reasons are in the [research](research.md#consensus-catalog).

## Panel layout

One floating, non-activating panel (760 × 460 points, growing to 600 high for an open tool while keeping its top edge) appears on the display holding the frontmost window, falling back to the pointer's display. It uses Liquid Glass on macOS 26 and later and vibrancy on macOS 14–15, system fonts for controls, monospaced text for payloads, the user's accent color for selection, and works in light and dark appearance with Reduce Motion, Reduce Transparency, and Increase Contrast.

### Search with live preview

Search is focused on open. Typing filters commands by name, alias, and tool family; ⌘V attaches the clipboard as input below the search field, showing only its source, detected type, and size (the text itself appears in the tool's editor, so a pasted secret isn't on display while it is hashed or decoded). With input attached, commands that fit it appear under **Suggested for JSON** (or URL, JWT, and so on) ahead of **Other tools**; with nothing attached, recently used tools come first. The preview beside the list always shows the selected command's live result, its options, and a status such as **Valid JSON**.

### Expanded tool

Return opens the selected command in the same panel: an editable input (native undo, find, and IME) beside the full result, with the command's options in the header. Inspectors show labeled fields with individual Copy buttons; generators show their value, fields, and a Regenerate button. Escape returns to search with the draft intact.

![An open tool: JSON input on the left and the formatted result on the right.](images/tool-json.png)

## Keyboard and clipboard behavior

| Input | Behavior |
| --- | --- |
| **Global shortcut** | Opens the palette with search focused; pressing it again refocuses the open palette and keeps the draft. Defaults to **⌥⇧Space**; Settings and the welcome window offer **⌃⌘Space** (which takes over Emoji & Symbols) and recording any other combination. The menu bar item opens the palette even if registration fails. |
| **⌘V** | In search, attaches or replaces the input and keeps the query. In the input editor, pastes at the insertion point. The clipboard is read only here. |
| **↑ ↓** | Move through the list while focus stays in search; the preview follows. |
| **↵** | Opens the selected tool. In the input editor, inserts a newline. |
| **⌘↵** | Copies the visible successful result and closes the palette, returning focus to the previous app. Disabled while a result is pending or invalid. |
| **⇧⌘↵** | Copies the result without closing. |
| **⌘K** | Actions menu: copy without closing, open or go back, paste, use pasted text as the search query, clear input, regenerate, every option of the selected command, Settings, and Close. |
| **⌘R / ⇧⌘⌫ / ⌘, / ⌘W** | Regenerate, clear input, open Settings, close. |
| **Escape** | Goes back from a tool to search with the draft intact; at the root, dismisses and discards the draft. Input methods get Escape and Return first while composing. |
| **Tab** | Moves through controls in visible order; ⌥Tab inserts a tab character in the editor. |

Tool input is processed on-device and kept in memory for the panel session only. Dismissal, Copy & Close, switching to another app, screen lock, sleep, user switching, and quitting all clear the draft and retire pending work. Preferences (shortcut, indentation, menu bar icon, recent command IDs) are stored separately and never include payloads, queries, or results. The app runs in the App Sandbox without the network entitlement, so Toolchord itself cannot send pasted data anywhere; results the user copies go to the standard system clipboard, which macOS may share through Universal Clipboard. Generated random strings stay on this Mac and are marked as confidential, which asks clipboard history apps not to keep or show them.

## Implementation

The code mirrors the plan's separation of concerns:

- **ToolchordCore** — commands, input detection, and search ranking. Foundation and CryptoKit only; evaluation is a pure function of a request (input, resolved options, seed, clock, time zone, limits, cancellation).
- **ToolchordSession** — the draft: query, payload, selection, options, generated values, revisions, background evaluation, and copy gating. Every change bumps the revision and disables copy before new work starts; completions publish only if their session and revision are still current.
- **ToolchordMac** — the non-activating panel, Carbon hotkey and recorder, pasteboard, SwiftUI views with AppKit text views, Settings, welcome window, menu bar item, and a snapshot renderer.
- **App** — a thin XcodeGen target: Info.plist keys, sandbox entitlements, and the Icon Composer app icon.

Native findings and decisions are recorded in the [implementation contracts](implementation-contracts.md#native-panel-decisions).

Toolchord is a working name. Revisit naming before committing to release branding, including the existing software uses of [ToolCord](https://github.com/imhvit/ToolCord) and [Chord](https://github.com/KeyChord/Chord).

## Acceptance checks

Automated tests cover every fixture in the contracts. These checks also need a person at the keyboard:

- **JSON:** From an editor, open the palette, paste minified JSON, and press ⌘↵. The clipboard matches the preview and the editor has focus again. Malformed JSON shows the error location and disables copying; fixing it in the editor restores copying.
- **XML:** Format a namespaced document with mixed content, CDATA, and preserved whitespace. A mismatched tag reports its line and column. A DOCTYPE reports unsupported and leaves the clipboard untouched.
- **Base64, URL, JWT, time:** Round-trip non-ASCII text through both Base64 alphabets. Copy the second of two repeated query values without closing. Decode a token, see **Signature unverified**, and copy one claim. Convert equivalent seconds and milliseconds to the same instant.
- **Generators:** Open Generate UUID with nothing pasted. The value stays the same until ⌘R, and ⌘↵ copies the value shown.
- **Focus and clipboard:** The shortcut and the menu bar item work across multiple displays, full-screen apps, and Stage Manager. Pressing the shortcut again refocuses the palette. Escape from a tool keeps the draft; switching apps clears it. Opening and closing the palette never changes the clipboard.
- **Accessibility:** Complete each flow with the keyboard alone and with VoiceOver; results and errors are announced when they settle.

## After the first release

Run the [validation study](research.md#validation-before-catalog-expansion), then consider regex testing and text diff (they need a roomier two-input editor), JSON ↔ YAML once a lossless parser is chosen, QR codes, certificate inspection, and cron explanations.
