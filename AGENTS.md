# AGENTS.md

This file provides guidance when working with code in this repository.

## TL;DR

- Do not create git branches unless explicitly instructed.
- The `.xcodeproj` is generated and gitignored. Run `xcodegen generate` after adding, removing, or renaming files, or after editing `project.yml`.
- Build and test on the iOS simulator by default. Use the Xcode beta toolchain (`DEVELOPER_DIR=/Applications/Xcode-beta.app`) so the simulator matches the physical iPad's OS.
- Unlike the Android emulator, video playback (including MKV via MPVKit) works in the simulator. HDR/EDR output, hardware decode, and playback smoothness must be verified on the physical iPad.
- The app has debug launch arguments for CLI-driven checks: `-autoplay <itemId>` jumps straight into playback, `-tab <home|movies|shorts|tv|browse|search|downloads|settings>` selects a sidebar section, `-server <address>` sets the Loom address (an unroutable address simulates offline), and `-download <itemId>` starts a download.

## Project

Takeup iOS is a native iPad client for Loom, written in Swift/SwiftUI with MPVKit (libmpv) for playback. It is a sibling of the Android Takeup app (`~/projects/takeup`); when in doubt about feature semantics (progress protocol, home rows, artwork buckets), mirror the Android app's behavior.

Single-developer hobby project - prefer simple, maintainable solutions over clever abstractions.

Loom and Takeup are developed and deployed together for one user. Do not preserve compatibility with older versions of either application; make coordinated changes in both repositories instead of adding compatibility shims.

Loom serves original files directly with no transcoding and no authentication over trusted-LAN HTTP. AVPlayer cannot play this library (Matroska/Opus/PGS); MPVKit is a hard requirement, not a preference.

## Critical Expectations

- Apply YAGNI ("You Aren't Gonna Need It") and KISS ("Keep It Simple, Stupid"). Build only what the current task requires; do not add abstractions, generality, or future-proofing for needs that do not yet exist. When two approaches work, take the simpler one.
- Prefer self-documenting code and local comments over separate documentation. Comments should explain non-obvious constraints, tradeoffs, invariants, historical context, or surprising decisions rather than restating the code.
- Prefer opinionated defaults over exposing more user-facing configuration. Add configuration only when there is a clear recurring need.
- Coordinate major tradeoffs with the user; never unilaterally defer functionality.
- Keep edits ASCII unless the file already uses extended characters.
- When troubleshooting, gather evidence and test rather than guessing.
- Add focused tests for new behavior and regressions.
- Follow established Swift/SwiftUI and project conventions. Do not add libraries, frameworks, or architectural layers without a concrete need.

## Build

Two toolchains are installed. The stable Xcode builds and runs the older-OS simulators; the beta (`Xcode-beta.app`) is required for the iOS beta simulator and for deploying to the physical iPad, which runs the beta OS.

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app

xcodegen generate   # only needed after file additions/removals or project.yml edits

xcodebuild -project Takeup.xcodeproj -scheme Takeup \
  -destination 'platform=iOS Simulator,name=iPad27' \
  -derivedDataPath DerivedData27 build
```

There is no test suite yet; a clean build plus a simulator smoke check is the current bar. Never commit `DerivedData*` output (gitignored, and it has already escaped once).

## Simulator

The `iPad27` simulator (iPad Pro 11-inch M4, iOS beta runtime) is the default target for everything it can run: UI, layout, navigation, API integration against the live Loom server, and playback smoke checks.

Xcode's beta removed the standalone Simulator app (its replacement is DeviceHub), so CLI-driven simulators run headless. Drive them with `simctl` and verify with screenshots:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app
xcrun simctl boot iPad27
xcrun simctl install iPad27 DerivedData27/Build/Products/Debug-iphonesimulator/Takeup.app
xcrun simctl launch iPad27 xyz.five82.takeup -tab browse   # or -autoplay <itemId>
xcrun simctl io iPad27 screenshot /tmp/check.png
xcrun simctl terminate iPad27 xyz.five82.takeup   # stops headless audio too
```

A launched player keeps playing (audibly) in the headless simulator; terminate the app when done.

## Physical iPad

HDR/EDR output, hardware decode behavior, playback smoothness, and the close-player lifecycle are verified on the physical iPad ("Kenneth's iPad"). Say so when you use it. Signing is pinned in `project.yml` (`DEVELOPMENT_TEAM`), so CLI builds are installable:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app
xcodebuild -project Takeup.xcodeproj -scheme Takeup \
  -destination 'platform=iOS,name=Kenneth’s iPad' \
  -derivedDataPath DerivedDataDevice -allowProvisioningUpdates build
xcrun devicectl list devices
xcrun devicectl device install app --device <udid> \
  DerivedDataDevice/Build/Products/Debug-iphoneos/Takeup.app
xcrun devicectl device process launch --terminate-existing --device <udid> xyz.five82.takeup
```

The free developer account means device installs expire after 7 days; reinstalling refreshes them.

## Loom

The development Loom server runs on the trusted LAN (`/api/v1`, port 8097, no auth); the address is configured in the app's Settings screen and must not be committed to this public repo. The API contract is Loom's README plus `internal/httpapi/httpapi_test.go` in `~/projects/loom`; the Android app's `LoomDtos.kt` mirrors the JSON shapes. List endpoints wrap arrays in `{"items": [...]}`, `/items` paginates with no total count (a short page means the end), and progress is reported in milliseconds via `PUT /items/{id}/progress`.
