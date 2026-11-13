# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- The bundle identifier is now `ch.lkmc.Toolchord` (was `com.toolchord.Toolchord`),
  matching the house `ch.lkmc.<App>` convention.
- Convert Unix Time has a new Auto unit, now the default: a value too large
  to be seconds but valid as milliseconds, such as `1700000000000` from
  JavaScript's `Date.now()`, is read as milliseconds, and the status says
  which unit was used. Seconds and Milliseconds are still available.
- A click selects a command row at once, and a click on the selected row
  opens its tool. Opening used to take a double-click, so every click
  waited about a third of a second.
- Copies of generated random strings stay on this Mac and are marked as
  confidential, which asks clipboard history apps that follow the
  nspasteboard.org convention not to keep or show them. This covers Copy,
  Copy & Close, and ⌘C on selected result text.
- The Actions menu's last item is now named Close Panel: it closes the
  palette, and Toolchord keeps running.

### Added

- Project tooling: `scripts/build.sh` and `scripts/release.sh` stubs over the
  shared `lkm-build`/`lkm-release` engines, a CI workflow (`swift test` +
  Release app build + shellcheck), a tag-triggered release workflow that
  packages and publishes the unsigned zip and DMG, dependabot, and the GLM
  review workflow. Build/install and release signing retain App Sandbox
  restrictions; the release stub generates the project and keeps the
  committed XcodeGen version source in sync with release tags.

### Fixed

- The shortcut recorder no longer rejects macOS shortcuts that are turned
  off in System Settings, such as ⌃⌥Space when the input source shortcuts
  are off or ⌘Space when Spotlight's is. It asks macOS which ones are on,
  and its message says where to turn one off.
- The shortcut recorder rejects the keys the palette handles itself, such
  as ⌘C, ⌘V, ⌘W, and ⌘↵. At launch, a saved shortcut that the recorder now
  rejects, or that is corrupt, falls back to the default; a corrupt key
  code no longer crashes the app.
- Decode Base64 and Decode Base64URL ignore whitespace around the input,
  such as the line break copied along with a token. Whitespace inside the
  encoding still needs Ignore whitespace.
- Convert to Title Case and Convert to Sentence case keep punctuation,
  spacing, digits, and emoji, and in mixed-case text they leave acronyms
  and words such as NASA or iPhone as they are. They used to drop
  punctuation, turning "it's a test, really." into "It S A Test Really".
- Identifiers such as `first_name`, `max-width`, or `OAuth2Token` are no
  longer detected as Base64URL, so the case conversions are suggested for
  them.
- Remove Duplicate Lines keeps lines that differ only in how an accent is
  encoded, such as `é` and `e` followed by a combining accent.
- Number conversions reject a trailing underscore, such as `123_`, instead
  of ignoring it.
- HTML and Markdown to plain text keep the contents of a hidden element
  hidden when its tag ends with a slash, such as `<div hidden/>`.
- Every warning on a result can be read. Past the first three, a
  disclosure shows them all, where it used to show only a count.
- A tool with many options keeps them inside the panel: they move below
  the title, or become menus, when they don't fit beside it.
- Editing the input of an open tool keeps the result's scroll position.
  New input and another tool still start at the top.
- Typing in a large document no longer piles up evaluations: at most two
  run at once, so the result for the last edit arrives sooner.
- VoiceOver can select a command row, and reaches each result field's
  Copy button on its own.
- ⌘V in a generator tool explains that generators take no input, and ⌘V
  with a read-only result focused pastes into the input or search field.
