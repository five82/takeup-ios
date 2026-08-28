# Patched libmpv: live resize on iOS

## The problem

MPVKit's Metal rendering path (libmpv + Vulkan via MoltenVK) cannot resize a
live video output. Its MoltenVK context only reads the Metal layer's
`drawableSize` when a video (re)configures, and its `control` handler is
unimplemented, so nothing ever tells mpv that the surface changed. Rotating
the iPad mid-playback left the picture at its old size and position. This is
[MPVKit issue #3](https://github.com/mpvkit/MPVKit/issues/3), unresolved
upstream.

Workarounds tried and rejected:

- Video filter add/remove to force a reconfig: software filters cannot accept
  VideoToolbox hardware frames; the commands fail.
- `hwdec` off/on bounce: executes, but the swapchain resize still reapplies
  the stale surface size.
- Full player rebuild on rotation: works (shipped briefly) but interrupts
  audio and video for ~250ms per rotation.

## The fix

`patches/mpvkit/0004-moltenvk-live-resize.patch` adds ~20 lines to mpv's
MoltenVK context (itself an MPVKit patch on top of upstream mpv): poll
`layer.drawableSize` in `VOCTRL_CHECK_EVENTS` — which the video output core
calls every frame cycle — and when it changes, call `ra_vk_ctx_resize` and
raise `VO_EVENT_RESIZE`. This is the same mechanism desktop windowing
backends use, which is why live window resizing is seamless in desktop mpv.

The app side (`MPVPlayerController`) keeps the layer's `frame` and
`drawableSize` in sync with the view in `viewDidLayoutSubviews`; the patched
context notices and resizes within a frame.

The framework also carries tvOS slices for the TakeupTV app. The patch
compiles into them but is inert there — an Apple TV's screen never changes
size mid-playback.

## How it's wired in

- `Vendor/MPVKit/Package.swift` — a vendored copy of MPVKit 0.41.0's package
  manifest. Every binary comes from MPVKit's official release artifacts
  except `Libmpv`, which points at the locally built
  `Vendor/MPVKit/Frameworks/Libmpv.xcframework`.
- `project.yml` references the vendored package by path instead of the
  upstream URL.

No binaries are committed: `Vendor/MPVKit/Frameworks/` is gitignored, so a
fresh clone will not build until the frameworks are built locally with the
steps below.

The same build also produces a second local framework, `Libavfilter`. MPVKit
configures FFmpeg with `--disable-filters` and a short allowlist that has no
dynamics processing; the player's night-mode dialogue boost runs
`acompressor` + `alimiter` through mpv's `lavfi` filter, so the script adds
both to the allowlist (a `sed` on MPVKit's build script, since the list is
not in a patchable source tree) and installs the rebuilt `Libavfilter`
alongside `Libmpv`. `Package.swift` points its `Libavfilter` binary target at
that local copy; every other FFmpeg library still downloads prebuilt from the
same MPVKit release, which is safe because the rebuild compiles the identical
FFmpeg version.

## Building the framework

```bash
brew install meson ninja wget
./scripts/build-libmpv.sh
xcodegen generate
```

The script builds all four slices — iOS, tvOS, and both simulators — into
each xcframework. FFmpeg and mpv compile from source (~30-60 minutes);
all other dependencies download prebuilt. When bumping the MPVKit version: update `MPVKIT_TAG` in
`scripts/build-libmpv.sh`, regenerate `Vendor/MPVKit/Package.swift` from the
new tag's manifest (keep the local `Libmpv` and `Libavfilter` binaryTargets), re-check that the
patch still applies and that the filter-list `sed` in the script still
matches, and rebuild. If upstream ever fixes issue #3, drop the
vendored package and point `project.yml` back at the upstream URL.
