<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/takeup-logo-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/takeup-logo-light.png">
    <img src="docs/takeup-logo-light.png" alt="Takeup logo" width="220">
  </picture>
</p>

# Takeup for iPad

Takeup for iPad is a native SwiftUI client for [Loom](https://github.com/five82/loom), a personal media server for movies, short films, and TV. It browses a Loom library, plays original media directly through [MPVKit](https://github.com/mpvkit/MPVKit) (libmpv), keeps viewing progress in sync, and supports full-file downloads for offline playback.

It is a sibling of [Takeup for Android](https://github.com/five82/takeup). Takeup and Loom are designed together for a single user on a trusted local network.

## Features

- Home discovery with Continue Watching, Next Up, and recently added/played titles
- Separate movie, short film, and TV libraries with collection and genre browsing
- Search across titles, episodes, cast, and crew, including fuzzy matches
- Direct playback of original files (Matroska, HEVC/AV1, Opus) with resume, chapter skipping, audio/subtitle selection, and HDR passthrough
- Watched-state management and automatic playback progress reporting
- Full-file downloads with offline playback and deferred progress sync
- Bonjour discovery of Loom servers on the local network

## Requirements

- An iPad running a recent iPadOS
- A running Loom server reachable over the local network

Loom does not authenticate requests and serves trusted-LAN traffic over HTTP. Do not expose it directly to the internet.

Loom streams source files without transcoding or remuxing; playback uses libmpv, so container and codec support is broad. Offline downloads are full-size copies of the source files.

## Building

Playback depends on a locally patched libmpv (live resize on the Metal
rendering path; see `docs/mpv-live-resize.md`). No binaries are committed,
so build it once first — FFmpeg and mpv compile from source, roughly 30-60
minutes:

```bash
brew install meson ninja wget
./scripts/build-libmpv.sh
```

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
open Takeup.xcodeproj
```

Set your development team under Signing & Capabilities (or in `project.yml`) to run on a device.
