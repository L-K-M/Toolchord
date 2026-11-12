# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- The bundle identifier is now `ch.lkmc.Toolchord` (was `com.toolchord.Toolchord`),
  matching the house `ch.lkmc.<App>` convention.

### Added

- Project tooling: `scripts/build.sh` and `scripts/release.sh` stubs over the
  shared `lkm-build`/`lkm-release` engines, a CI workflow (`swift test` +
  Release app build + shellcheck), a tag-triggered release workflow that
  packages and publishes the unsigned zip and DMG, dependabot, and the GLM
  review workflow. Build/install and release signing retain App Sandbox
  restrictions; the release stub generates the project and keeps the
  committed XcodeGen version source in sync with release tags.
