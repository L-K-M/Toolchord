# Remaining Toolchord findings

Reviewed against `6353e69` (Longcat review) and consolidated with the earlier review of `6714272`
and Claude's review of the same baseline. File/line references refer to the review baseline.
Findings implemented in open PRs are omitted. All remaining findings are optional improvements;
observations that still need live validation are identified below.

## Bugs

### Empty search results retain a stale accessibility selection

bugs — nice-to-have

Location: `Sources/ToolchordMac/Views/SearchField.swift:51-53`. When a query stops matching any
command, the field keeps its previous accessibility value description. VoiceOver users can encounter
a tool name that is no longer selected. Missing reset is source-confirmed; live announcement
behavior was not exercised.

Suggested fix: set or clear the accessibility description on every update, including the
no-selection state. Rough effort: 30 minutes.

### Bearer-prefixed JWT input misses JWT suggestions

bugs — nice-to-have

Location: `Sources/ToolchordCore/Detection/InputDetector.swift:48-55,143-151`;
`Sources/ToolchordCore/Tools/JWTTools.swift:14-17`. Developers pasting a complete Authorization
value must manually search for Decode JWT, even though the decoder explicitly accepts the prefix.
The detector's single-token gate excludes the space after Bearer. The decoder itself strips the
prefix only when spaces follow it: `Bearer\t<token>` fails with "The header isn't valid
Base64URL: Base64 contains whitespace".

Suggested fix: recognize a bounded Bearer-prefixed token for detection without modifying the
attached input; keep the decoder's removal warning. Accept any whitespace after `Bearer` in the
decoder (`JWTTools.swift:17`). Rough effort: 1 hour.

### BOM-bearing XML misses XML suggestions

bugs — nice-to-have

Location: `Sources/ToolchordCore/Detection/InputDetector.swift:43-46`. Pasting U+FEFF followed by
`<r/>` labels it Text and omits XML suggestions, even though XMLTools accepts an initial BOM. This
affects XML copied from BOM-bearing files and was confirmed against the built module.

Suggested fix: ignore one initial BOM for lexical detection while retaining the original payload
bytes and diagnostic offsets. Rough effort: 1 hour.

### Nonhierarchical URIs miss Inspect URL suggestions

bugs — nice-to-have

Location: `Sources/ToolchordCore/Detection/InputDetector.swift:158-170`. URI detection requires
`://`, although Inspect URL accepts `mailto:a@example.com`, `data:text/plain,Hi` and `file:/tmp/a`.
Users inspecting these forms receive Text suggestions instead. Confirmed against the built module.

Suggested fix: align bounded scheme recognition with the inspector, retaining safeguards for
drive-letter paths and ordinary prose. Rough effort: 1-2 hours.

### Padded numeric entities miss decoder suggestions

bugs — nice-to-have

Location: `Sources/ToolchordCore/Detection/InputDetector.swift:325-328`. The detector looks ahead
only 12 characters after an ampersand, while HTMLTools accepts numeric references with up to 32
digits. A valid reference such as `&#0000000000065;` decodes successfully but does not suggest
Unescape HTML. This affects uncommon numeric-entity input.

Suggested fix: align the bounded numeric-reference lookahead with the decoder's limit, without
broadening named-entity support accidentally. Rough effort: 1 hour.

### Slugs ignore camelCase and acronym boundaries

bugs — nice-to-have

Location: `Sources/ToolchordCore/Tools/CaseTools.swift:435-460`. Convert to Slug transliterates
and lowercases before splitting, so `helloWorld XMLHttpRequest` becomes
`helloworld-xmlhttprequest` instead of `hello-world-xml-http-request`, against the shared
word-splitting rules for case conversion and slugs. Confirmed against the built module.

Suggested fix: split each line with `splitWords` first, then transliterate and join with hyphens.
Rough effort: 1 hour.

### Combining marks hide case boundaries

bugs — nice-to-have

Location: `Sources/ToolchordCore/Tools/CaseTools.swift:241-245`. Boundary detection looks at the
previous scalar, so a combining mark hides the lowercase letter before it: decomposed
`e\u{0301}Name` becomes `éname` in snake_case instead of `é_name`. This affects NFD text such
as file names copied from Finder. Confirmed against the built module.

Suggested fix: decide boundaries from the base letter before any combining marks. Rough effort:
1 hour.

### Hidden HTML leaks after a stray end tag or with `!important`

bugs — nice-to-have

Location: `Sources/ToolchordCore/Tools/Markup/HTMLTextConverter.swift:59,279` (open PR #20 changes
this file for self-closing slashes). `<div hidden>secret</p>leak</div>visible` converts to
`leak` and `visible`, while a browser shows only `visible`, and
`<span style="display:none!important;display:block">secret</span>` shows `secret`. Confirmed
against the built module.

Suggested fix: end suppression only when the hidden element or an ancestor closes, and honor
`!important` when resolving `display`. Rough effort: 2 hours, after #20 lands.

### Make Plain Text counts a trimmed converted space twice

bugs — nice-to-have

Location: `Sources/ToolchordCore/Tools/PlainTextTools.swift:236-255`, with the trailing counts at
163, 172, 182 and 290. A non-breaking space at a line end counts as a normalized space and again
as a trimmed trailing space: `a\u{00A0} \nb` reports "3 changes" for two removed characters.

Suggested fix: count a trimmed space as trailing only if it was not already counted as a normalized
space. Rough effort: 30 minutes.

## General issues

### The benchmark exercises early rejection for many tools

general issues — nice-to-have

Location: `Sources/ToolchordSnapshots/main.swift:110-148`. Maintainers see green/fast benchmark
output for XML, Base64 decode, JWT, number, hex decode and color paths that mostly reject the
shared JSON fixture. Real successful-path regressions can escape measurement.

Suggested fix: supply valid per-family fixtures and report successful and rejected-input timings
separately. Keep exact byte sizes in the output. Rough effort: half a day.

### Snapshot coverage omits accessibility and stress states

general issues — nice-to-have

Location: `Sources/ToolchordMac/Snapshots/SnapshotRenderer.swift:19-70`. Maintainers still lack
long-field, high-contrast, and constrained-height scenarios. Long copy titles and the full
horizontal footer also need stress coverage at narrow widths, beyond the existing 600-point simple
case. Actual footer overflow is not established. Dense-option and four-warning JWT coverage is
implemented in open PRs and is excluded from this remaining work.

Suggested fix: add a small representative set and document manual checks for real glass, keyboard
traversal, and VoiceOver. If footer crowding is reproduced, hide low-priority hints first.
Offscreen snapshots cannot prove interactive behavior; attempts to inspect SwiftUI accessibility in
the Swift Testing host returned an empty tree. Rough effort: half a day.

### Multiple line scanners need an explicit shared contract

general issues — nice-to-have

Location: `Sources/ToolchordCore/Tools/LineTools.swift:174-262`;
`Sources/ToolchordCore/Tools/CaseTools.swift:215-248`;
`Sources/ToolchordCore/Detection/InputDetector.swift:382-399`. Maintainers must reason
independently about CR, LF, CRLF and trailing-break conventions across several scanners; detection
counts a trailing break differently from Count Characters. This is not necessarily incorrect but is
easy to change inconsistently.

Suggested fix: document the intentional counting differences and consolidate shared byte-scanning
mechanics only if that simplifies the code. Add shared newline fixtures rather than a speculative
abstraction. Rough effort: half a day.

### Result announcements fire on every settled edit

general issues — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:52-54,963-980`. `Announcer.announce` posts
a VoiceOver announcement for every `.ready` preview, including each debounced result after typing
in the input editor. A VoiceOver user editing JSON hears "Valid JSON" repeated on every pause,
which is noisy and can mask other announcements.

Suggested fix: announce only when the result kind or command changes (for example success ↔
invalid), or rate-limit announcements during editing. Rough effort: about an hour.

### Dead `isWaitingForInput`

general issues — nice-to-have

Location: `Sources/ToolchordSession/PaletteSession.swift:208-210`. The method is defined but never
used; the UI derives the needs-input state from the result. Dead code adds maintenance surface.

Suggested fix: remove it, or use it in the view layer if it expresses a real rule. Rough effort:
minutes.

### `Scripts/` and `scripts/` coexist

general issues — nice-to-have

Location: `Scripts/make-icon.swift` beside `scripts/*.sh`; `Makefile:38`;
`docs/implementation-contracts.md:224`. On case-insensitive macOS the two folders are one; on
Linux CI they are two, so moves and globs behave differently per platform.

Suggested fix: move `make-icon.swift` into `scripts/` and update the Makefile and docs. Rough
effort: 15 minutes.

### `PaletteView.swift` holds more than 20 types in 981 lines

general issues — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift`. This goes against the one-type-per-file
convention, and every UI change touches the same file, so concurrent PRs conflict (#21, #22,
#23, #24, #30 and #36 all edit it).

Suggested fix: extract views into their own files as they change, starting with the most edited
(command list, results, options). Rough effort: about 2 hours.

## Performance problems, stuttering, and jank

### Near-limit Markdown conversion takes about one second

performance problems, stuttering, and jank — nice-to-have

Location: `Sources/ToolchordCore/Tools/Markup/MarkdownDocument.swift:146-153,179-220`;
reproducible with `make benchmark`. Large-document users wait about 1,004 ms for Markdown-to-HTML
and 937 ms for Markdown-to-text in the release benchmark. Work is off the main actor, but the
Foundation parser is not interruptible, so superseded work can continue: editing a large Markdown
document schedules a conversion per pause, each superseded task is cancelled, and a conversion
already inside Foundation keeps a `userInitiated` detached task until it finishes. This is already
acknowledged in the implementation contracts.

Suggested fix: profile parser versus reconstruction cost, consider a longer debounce for large
edits or a cancellable parser only if measurements justify the dependency and fidelity tradeoffs.
Open PR #35 bounds the pile-up (at most two evaluations run at once); the conversion itself still
takes about a second.
Preserve current copy gating. Rough effort: 1-3 days for profiling and a bounded improvement;
parser replacement needs separate design.

### Case transformations cancel only between large batches of lines

performance problems, stuttering, and jank — nice-to-have

Location: `Sources/ToolchordCore/Tools/CaseTools.swift:336-358,405-473`. Large single-line payloads
still finish scanning/splitting/transliterating after their results are obsolete; line-based
checks do not help them. Case conversions measured about 183-317 ms at near 1 MiB, off the main
actor. Repeated edits can waste CPU. In a release build, snake_case of a single 1 MiB line ran
234 ms without a single cancellation check.

Suggested fix: add cancellation checkpoints during scalar/byte scanning and avoid intermediate
Character arrays where practical. Measure single-line and multiline payloads independently;
Foundation transliteration itself may remain non-interruptible. Rough effort: half a day to one
day.

### Inspector sizing scans entire field values on the main actor

performance problems, stuttering, and jank — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:526-530`. Large JWT/URL fields are
traversed completely when estimating a row that shows at most four lines. This is avoidable work on
view updates. In a release build, walking every `Character` of a 1 MiB value took 38 ms, and
SwiftUI also lays out the whole `Text` despite `lineLimit(4)` (`PaletteView.swift:567-571`); an
actual frame stall was not measured.

Suggested fix: stop after the third newline and use a bounded newline scan, caching only if
profiling warrants it, and display at most the first few thousand characters of a value with an
ellipsis; Copy keeps the full value. Rough effort: 1 hour.

### Detection precedes editor debounce on the main actor

performance problems, stuttering, and jank — nice-to-have

Location: `Sources/ToolchordSession/PaletteSession.swift:18-23,267-283`. Editing a near-limit
payload runs the complete profiler synchronously before the 60 ms evaluation debounce. Release
measurements on 1 MiB inputs: 2-11 ms (plain 2.4 ms, newlines 3.8 ms, 1M ampersands 10.9 ms);
Debug builds were 24-61 ms. Release typing jank is not established, so this is a measurement
opportunity rather than a confirmed frame stall.

Suggested fix: measure optimized typing latency, then bound or defer profiling if needed while
preserving immediate stale-result copy invalidation. Computing the profile off the main actor or
debouncing and caching it by text are the options; keep the cheap byte count synchronous for the
attachment bar. Rough effort: half a day for measurement and a safe design.

### Superseded line transformations do not stop cooperatively

performance problems, stuttering, and jank — nice-to-have

Location: `Sources/ToolchordCore/Tools/LineTools.swift:34-174`. Sorting, deduplication and reversal
do not consult request cancellation, so obsolete work can keep using background CPU. Session
revisions correctly prevent stale publication and copy. Sort Lines takes about 103 ms at 1 MiB in
the release benchmark.

Suggested fix: add useful checkpoints around long stages and within traversals where practical;
measure large-line workloads before changing the sorting algorithm. Rough effort: 2-4 hours.

### Syntax highlighting runs on the main thread when a result settles

performance problems, stuttering, and jank — nice-to-have

Location: `Sources/ToolchordMac/Views/CodeTextView.swift:208-216`;
`Sources/ToolchordMac/Views/SyntaxHighlighter.swift:11-28`. `ResultTextView.apply` builds the
highlighted `NSAttributedString` in `updateNSView` on the main actor. Debug measurements with a
256 KiB document: JSON 31 ms, XML 53 ms (the highlighter caps at 256 KiB, so larger results take
the plain path). Release is expected to be several times faster, so this is a possible small hitch
rather than a confirmed stall; the evaluation itself runs in the background.

Suggested fix: if desired, build the attributed string off the main actor or set the plain text
immediately and replace it when ready. Keep the highlighter's cancellation and cap. Rough effort:
about half a day.

### Warm invocation time is unmeasured

performance problems, stuttering, and jank — nice-to-have

Location: `docs/implementation-contracts.md` (Performance); `Sources/ToolchordSnapshots/main.swift`.
The contracts say warm invocation time still needs measuring by hand. The benchmark times tool
evaluation only; it does not measure hotkey-to-panel-rendered or first-open cost. The panel is a
full SwiftUI view created on first use, and a slow first open is the user's first impression.

Suggested fix: add a warm-invocation measurement (hotkey to first frame and to first result) to the
benchmark or a manual procedure, then optimize if it is over budget. Rough effort: about half a day.

## Missing features

### Long inspector fields have no full-value view

missing features — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:567-570`. People inspecting long JWT
headers/claims and URL values can copy the complete value but can only read four lines inside
Toolchord.

Suggested fix: add an accessible field expansion or read-only details popover while keeping
compact default rows. Rough effort: 2-4 hours.

### Markdown fidelity limitations are invisible in the result

missing features — nice-to-have

Location: `docs/implementation-contracts.md:86`;
`Sources/ToolchordCore/Tools/Markup/MarkdownDocument.swift:64-78`. README converters can lose
link/image titles, reference-style images inside links, empty structures, and formatting beyond
recovery limits. These are documented parser limitations, but the app reports only "Rendered HTML".

Suggested fix: surface a concise limitation note where a lossy path is detectable, then evaluate
fuller source parsing against representative fixtures. Do not promise full CommonMark fidelity
without coverage. Rough effort: half a day for disclosure; fuller fidelity is a multi-day parser
task.

### Pasted UUIDs have detection but no inspector

missing features — nice-to-have

Location: `Sources/ToolchordCore/Detection/InputDetector.swift:205-220`;
`Sources/ToolchordCore/Tools/UUIDTools.swift:8-48`. Developers can generate UUIDs but cannot
inspect a pasted identifier's version, variant or v7 timestamp in the palette, despite UUID
detection already existing.

Suggested fix: add a separate Inspect UUID command with strict validation, normalized forms and v7
timestamp fields. Keep generators' stable-seed behavior unchanged. Rough effort: half a day to one
day.

### Named CSS colors are unsupported despite the type comment

missing features — nice-to-have

Location: `Sources/ToolchordCore/Tools/ColorTools.swift:142-223`;
`Sources/ToolchordCore/Detection/InputProfile.swift:16`. Neither detection nor conversion accepts
names such as `red` or `rebeccapurple`, although the color-kind comment claims named-color support.
Web developers must look up the numeric form themselves. This is an optional feature extension; the
user-facing conversion contract lists hex, RGB and HSL. Space-separated channels must also be
separated by spaces: `rgb(255\t0\t0)` is rejected (`ColorTools.swift:269`).

Suggested fix: consider a shared standard name table for detection and conversion, including
transparent, with contract fixtures and no network dependency. Until then, narrow the capability
comment to supported syntax. Split channels on any CSS whitespace, and fold the three copies of
the evaluation function (`ColorTools.swift:54-130`) into one. Rough effort: half a day for
support; minutes for the comment correction.

### No way to pin favorite tools

missing features — nice-to-have

Location: `Sources/ToolchordMac/Settings/SettingsView.swift:93-104`;
`Sources/ToolchordMac/Services/AppPreferences.swift:28-35`. Only the four most recent tools are
surfaced. Users with a small set of daily tools (JSON format, UUID, timestamp) must search or
scroll for them every time, which works against the "shortcut away" goal.

Suggested fix: add a persisted favorite flag per command (IDs only), a way to toggle it (Actions
menu or a star on the row), and a "Favorites" section ahead of Recents. Rough effort: about a day.

### No "copy all fields" for inspectors

missing features — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:521-553`;
`Sources/ToolchordMac/Panel/PanelController.swift:297-359`. URL inspection and JWT claims can have
many fields, each with its own Copy button. There is no way to copy them all at once (for example as
`label: value` lines), so copying a full set of parameters is tedious.

Suggested fix: add a "Copy All Fields" item to the Actions menu (and/or a button in the fields
header) that joins the fields in a stable, documented format. Rough effort: about half a day.

### No compact, list-only mode

missing features — nice-to-have

Location: `docs/design-review.md` (Open questions); `Sources/ToolchordMac/Views/PaletteView.swift:121-144`.
The panel always reserves the preview pane; below 640 pt it stacks the list above the preview. The
design review lists a list-only compact mode as an open question for small displays. On a small
screen or Stage Manager, the preview consumes most of the height.

Suggested fix: add a compact mode (toolbar toggle or automatic below a width) that hides the preview
and grows the list, with Return to open the tool. Rough effort: about a day.

### No keyboard shortcut to clear the search

missing features — nice-to-have

Location: `Sources/ToolchordMac/Views/SearchField.swift:73-96`;
`Sources/ToolchordMac/Panel/PalettePanel.swift:88-116`. When a query has no matches, a "Clear
search" button appears, but there is no key for it. Escape at the root dismisses the whole palette
(documented), so a user who wants to keep their attached input and clear only the query must reach
for the mouse. Spotlight and Raycast clear a non-empty query on the first Escape.

Suggested fix: add a shortcut (for example ⌘U, or a first Escape that clears a non-empty query and
a second that closes) that clears the query and keeps the draft. The Escape variant changes the
documented root-Escape rule. Rough effort: about half a day (product decision on the key).

### No hover preview

missing features — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:201-227`. The preview follows the
selection, so users must click or arrow through rows to compare tools. Hovering a row could preview
it without changing the selection, which is a common palette interaction.

Suggested fix: on hover, temporarily show the hovered command's result while keeping the selection;
revert on mouse-out. Rough effort: about half a day.

### Result fields cannot be copied from the keyboard

missing features — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:555-603`. Field Copy buttons are reachable
only by tabbing through every row, so copying one JWT claim or URL parameter takes many
keystrokes in a keyboard-first palette.

Suggested fix: ⌘1-⌘9 copy the first nine copyable fields, with the keycap shown on each row. Rough
effort: about 2 hours.

### Inspect URL has no raw Query field

missing features — nice-to-have

Location: `Sources/ToolchordCore/Tools/URLTools.swift:161-210`. Fields are Scheme, Host, Path,
Fragment and the decoded pairs; the contract lists the query among the raw components, and there
is no way to copy it as written. Confirmed against the built module.

Suggested fix: add an independently copyable raw Query field. Rough effort: 15 minutes.

### Decode Hex rejects common dump formats

missing features — nice-to-have

Location: `Sources/ToolchordCore/Tools/HexTools.swift:53-68`. `0x48 0x65` and `48, 65`, typical of C
arrays and debugger output, fail with "Invalid hex digit".

Suggested fix: accept per-byte `0x` and `\x` prefixes and commas. Rough effort: about 1 hour.

### Unescape HTML knows only the HTML 4 entities

missing features — nice-to-have

Location: `Sources/ToolchordCore/Tools/HTML/HTMLEntityTable.swift`. `&check;`, `&NewLine;` and the
other HTML5-only names stay unescaped with an "Unknown entity" warning.

Suggested fix: generate the full HTML5 table (2,231 names) the same way. Rough effort: 1-2 hours.

### No way to bring selected text in without the clipboard

missing features — nice-to-have

Location: no single line; the app has no Services entry and the panel accepts no drops. Text
selected in another app must be copied first, which overwrites the clipboard.

Suggested fix: an "Open in Toolchord" service for selected text, and text drops on the search area,
both user-initiated. Rough effort: about half a day.

## Visual issues and layout problems

### Field lists scroll and clip rows although there is room

visual issues and layout problems — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:464-487,526-533`. The height estimate
counts only line breaks, so a wrapped value (UUID v7's Uppercase field) makes the list scroll
with free space below it, and in snapshots Decode JWT ("sub") and Convert Unix Time
("Relative") show half a row at the bottom edge.

Suggested fix: size the list to its content up to a cap (a plain stack first, a scroll view only
when it does not fit), or snap the cap to whole rows. Rough effort: about 2 hours.

### Convert Unix Time repeats its result as a UTC field

visual issues and layout problems — nice-to-have

Location: `Sources/ToolchordCore/Tools/TimeTools.swift:63-77`. The UTC field duplicates the primary
result (the contract lists local time, Unix seconds, milliseconds and relative time) and pushes
Relative out of view in the preview.

Suggested fix: drop the UTC field for Convert Unix Time. Rough effort: 15 minutes.

### The narrow layout shows only three commands

visual issues and layout problems — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:127-134`. Below 640 pt the list is fixed at
150 pt, about two and a half rows.

Suggested fix: give the list a share of the height (about 40%), or adopt the compact list-only mode
under missing features. Rough effort: 30 minutes.

## Usability

### Pending field Copy controls look usable but do nothing

usability — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:465-475,580`. Previous inspector output is
dimmed during reevaluation, but its field Copy buttons are not disabled. Clicking them does
nothing because session gating correctly rejects stale writes. Users get no explanation for the
apparently available action.

Suggested fix: disable field Copy controls with the pending state, preserving the existing
session-level guard. Rough effort: under an hour.

### Immediate progress badges can defeat delayed progress treatment

usability — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:735,956`. The result spinner waits 150 ms
to avoid flicker, but the status badge immediately shows a spinner and Working text on every
pending transition. Rapid typing or selection can therefore still produce distracting status
changes. Selecting another command also blanks the result area: it starts as
`.pending(previous: nil)` (`PaletteSession.swift:520-521`), so the pane stays empty until the
result lands, which shows whenever evaluation outlasts a frame (Markdown at 10 KiB takes about
11 ms). This is source-established behavior; no frame capture was made.

Suggested fix: share a delayed pending-indicator policy between the badge and result pane, keeping
the previous output dimmed during the delay, without delaying invalidation or copy gating. Rough
effort: 1-2 hours.

### Opening Settings discards the palette draft

usability — nice-to-have

Location: `Sources/ToolchordMac/Panel/PanelController.swift:255-258`;
`Sources/ToolchordMac/App/ToolchordApplication.swift:181-186`. Both paths to Settings call
`dismiss(.system)`, and `dismiss` always calls `session.end()`, which clears the query, payload,
edits, options, seeds and result. A user who presses ⌘, while a paste or edit is in progress loses
that work. The countervailing constraint is the privacy promise: input is kept in memory only
while the palette is open, so preserving the draft across Settings requires clearing it on app
switch or when Settings closes.

Suggested fix: if preserving the draft is desired, add a dismiss reason that keeps the session, and
end the session when Settings closes or the user activates another app. Otherwise document the
intentional clear. Rough effort: about half a day (with the extra lifetime rules).

### Line tools are suggested for JSON and one-line text with a trailing newline

usability — nice-to-have

Location: `Sources/ToolchordCore/Tools/LineTools.swift:28,80`;
`Sources/ToolchordCore/Detection/InputDetector.swift:41,384-399`. Pasted multiline JSON lists Sort
Lines and Remove Duplicate Lines under "Suggested for JSON", against the contract's rule that
general text tools suggest themselves only for plain text; and `token\n` counts as two lines, so
a one-line paste gets line tools and loses the URL-encode suggestion.

Suggested fix: require `isPlainText` for the line tools, and do not count one final line break as an
extra line in detection. Rough effort: 30 minutes.

### The global shortcut never closes the palette

usability — nice-to-have

Location: `Sources/ToolchordMac/Panel/PanelController.swift:50-55`. Pressing the shortcut again
refocuses the open panel (documented), while launcher muscle memory expects it to toggle.

Suggested fix: when the panel is already key, the shortcut dismisses it; when it is visible but not
key, it focuses it. This changes a documented rule. Rough effort: 30 minutes.

### Date-only and offset-less dates are rejected

usability — nice-to-have

Location: `Sources/ToolchordCore/Tools/Time/TimeParser.swift:142,171-173`. `2024-01-01` and
`2024-01-01 12:00:00` are detected as dates and Convert Date to Unix Time is suggested, but both
fail.

Suggested fix: an Assume option (UTC or local) used only when the time or offset is missing, stated
in the status. Rough effort: about 2 hours.

### Hashes and encoders silently include a copied line break

usability — nice-to-have

Location: `Sources/ToolchordCore/Tools/HashTools.swift:69-83` (also the Base64, URL and hex
encoders). `password\n` hashes 9 bytes, so the `echo` versus `echo -n` mistake goes unnoticed.

Suggested fix: a warning such as "Includes the line break at the end". Rough effort: about 1 hour.

### Closing Settings or the welcome window leaves Toolchord active

usability — nice-to-have

Location: `Sources/ToolchordMac/App/ToolchordApplication.swift:181-192`. After the window closes,
no app window has focus until the user clicks somewhere.

Suggested fix: when the last Toolchord window closes, hide the app so the previous app regains
focus. Rough effort: 30 minutes.

## Aesthetics and theming

### Transparency is hard to distinguish in color swatches

aesthetics and theming — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:609-614`. Designers inspecting translucent
colors see them blended directly into the panel and cannot easily distinguish alpha from the
surrounding surface.

Suggested fix: put a subtle checkerboard under swatches, optionally with light/dark halves. Rough
effort: 1-2 hours.

### Custom surfaces have no dedicated high-contrast treatment

aesthetics and theming — nice-to-have

Location: `Sources/ToolchordMac/Views/Theme.swift:28-32,56-62`. Users enabling Increase Contrast
receive the same custom well/selection fills and syntax palette. System colors can adapt, but the
custom colors do not. No measured contrast failure is claimed.

Suggested fix: add explicit high-contrast borders/background variants and test over real busy
wallpapers as well as opaque snapshots. Rough effort: half a day.

### Appearance and code text size follow the system

aesthetics and theming — nice-to-have

Location: `Sources/ToolchordMac/Views/Theme.swift:22-24`;
`Sources/ToolchordMac/Settings/SettingsView.swift:78-104`. The panel follows the system appearance
and uses a fixed 12 pt code font. Users who want a light palette in dark mode, or a larger result
font, have no control. This is an optional customization, not a defect.

Suggested fix: offer light/dark/auto and a small set of code-font sizes, persist only the
preference, and validate minimum useful editor space. Rough effort: half a day.

### Three tool families share the same "#" icon

aesthetics and theming — nice-to-have

Location: `Sources/ToolchordCore/Tools/UUIDTools.swift:14,27,47`; `HashTools.swift:62`;
`NumberTools.swift:86`. Under "Suggested for Number" every row shows "#", as do the UUID and
hash rows, which makes the list harder to scan.

Suggested fix: distinct glyphs, for example "ID" for identifiers, a fingerprint symbol for hashes
and "0b" for bases. Rough effort: 30 minutes.

### The menu bar item fakes shortcut alignment and uses a stock symbol

aesthetics and theming — nice-to-have

Location: `Sources/ToolchordMac/App/ToolchordApplication.swift:89,98`. "Open Toolchord   ⌥⇧Space"
pads with spaces instead of using the native key-equivalent column, and the generic
`command.square` symbol is easy to confuse with other menu bar items.

Suggested fix: show the shortcut through the item's key equivalent (display only) and use a template
glyph derived from the app icon. Rough effort: about 1 hour.

## Novel, delightful, or quirky ideas worth trying

### Use the current result as the next tool's input

novel, delightful, or quirky ideas worth trying — nice-to-have

Location: `Sources/ToolchordMac/Panel/PanelController.swift:309-374`. Decode Base64 → format JSON
or HTML → clean plaintext currently requires copy and paste, replacing the user's clipboard along
the way. A related reversible-conversion idea is a "Swap Input and Result" action for commands
that declare a reverse command.

Suggested fix: add an explicit session-local "Use result as input" action that attaches the ready
primary output and returns to search, preserving revision/copy gating and requiring no saved
history. For reversible commands, declare the reverse command ID and add "Swap Input and Result".
Preserve a clear way back to the original draft if a chain is introduced; draft ownership and undo
behavior need an explicit design before implementation. A breadcrumb in the attachment row (for
example "Decoded Base64 →") would show where the input came from. Rough effort: half a day for a
prototype; 1-2 days with reversible draft handling.

### Optional examples could teach unfamiliar tools

novel, delightful, or quirky ideas worth trying — nice-to-have

Reproduction: open an unfamiliar tool with no input; the empty state asks for a paste but gives no
example of accepted syntax. First-time users of time offsets, number prefixes, colors and encoding
tools must guess syntax or consult docs.

Suggested fix: add a clearly labeled "Try an example" action for selected tools, using deterministic
public synthetic fixtures and an explicit user action that explains it replaces the current input.
Keep ordinary opening free of injected sample data. Rough effort: half a day for a small curated set
and session tests.

### Explain ambiguous automatic suggestions briefly

novel, delightful, or quirky ideas worth trying — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:163-170`;
`Sources/ToolchordSession/CommandListing.swift`. Curious users cannot see why ambiguous input was
labeled Base64, hex or a timestamp. A detection label can be mistaken for validation.

Suggested fix: prototype a short metadata tooltip explaining the lexical hint without displaying
pasted secrets or claiming validity. Keep it out of the fast keyboard path and validate demand before
adding persistent UI. Rough effort: half a day.

### Result history within the session

novel, delightful, or quirky ideas worth trying — nice-to-have

Location: `Sources/ToolchordSession/PaletteSession.swift:101-134`. An in-memory, per-session list
of recent results (with the command and a timestamp) would let users go back to a value they just
replaced by typing. Privacy stays intact because it is session-only and never persisted.

Suggested fix: keep the last N ready results keyed by command and expose a "Previous Result" action.
Rough effort: about a day.

### Tool alias hints in the row or footer

novel, delightful, or quirky ideas worth trying — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:201-227`. Showing a command's aliases (for
example "pretty print", "epoch") teaches search vocabulary and makes search feel more forgiving.

Suggested fix: show the first alias as secondary text on the selected row or in the preview header.
Rough effort: about an hour.

### Reveal invisible characters in the input editor

novel, delightful, or quirky ideas worth trying — nice-to-have

Location: `Sources/ToolchordMac/Views/CodeTextView.swift:80-123`. Make Plain Text removes
characters the user cannot see, so its input gives no clue what will change.

Suggested fix: draw markers for non-breaking spaces, zero-width characters and directional controls
in the editor (always for Make Plain Text, as a toggle elsewhere). Rough effort: about 2 hours.

### Hint that the clipboard holds text without reading it

novel, delightful, or quirky ideas worth trying — nice-to-have

Location: `Sources/ToolchordMac/Views/PaletteView.swift:60-83`. The first step is nearly always
⌘V, but the panel cannot say whether it will work.

Suggested fix: on open, check the pasteboard's types (no read, no privacy prompt) and emphasize the
⌘V keycap with "Clipboard has text". Rough effort: about 1 hour.
