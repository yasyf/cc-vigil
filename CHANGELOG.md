# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial scaffolding.
- Xcode project skeleton (XcodeGen `project.yml`): the CCVigil menu-bar app with
  CCVigilDaemon (LaunchAgent), CCVigilHelper (LaunchDaemon), and the `cc-vigil`
  CLI embedded in its bundle, all sharing the local CCVigilShared package.
- CI on macos-26: swiftformat/swiftlint, `xcodebuild` build of the CCVigil
  scheme, and `swift test` for CCVigilShared.
- CCTranscript oracle dependency (revision-pinned SwiftPM git package from
  [cc-transcript](https://github.com/yasyf/cc-transcript)) wired into
  CCVigilDaemon, with a placeholder `sessionActivity` probe.

[Unreleased]: https://github.com/yasyf/cc-vigil/commits/main
