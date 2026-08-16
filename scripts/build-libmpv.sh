#!/bin/bash
# Builds the live-resize-patched Libmpv.xcframework that Vendor/MPVKit uses.
#
# MPVKit's Metal/MoltenVK backend cannot resize a live video output
# (https://github.com/mpvkit/MPVKit/issues/3). patches/mpvkit adds drawable-
# size polling to mpv's MoltenVK context so rotation and window resizes work
# without rebuilding the player. This script rebuilds only libmpv from
# source; every other dependency downloads prebuilt from MPVKit's releases.
#
# Takes roughly 30-60 minutes (FFmpeg compiles from source). Requires:
#   brew install meson ninja wget
#
# Usage: ./scripts/build-libmpv.sh [work-dir]

set -euo pipefail

MPVKIT_TAG="0.41.0"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${1:-$(mktemp -d /tmp/mpvkit-build.XXXX)}"
DEST="$REPO_ROOT/Vendor/MPVKit/Frameworks"

echo "==> Cloning MPVKit $MPVKIT_TAG into $WORK_DIR"
if [ ! -d "$WORK_DIR/.git" ]; then
    git clone --depth 1 --branch "$MPVKIT_TAG" https://github.com/mpvkit/MPVKit.git "$WORK_DIR"
fi

echo "==> Applying local patches"
cp "$REPO_ROOT"/patches/mpvkit/*.patch "$WORK_DIR/Sources/BuildScripts/patch/libmpv/"

echo "==> Building (ios + simulator)"
cd "$WORK_DIR"
export PATH="/opt/homebrew/bin:$PATH"
make build platform=ios,isimulator

echo "==> Installing Libmpv.xcframework into $DEST"
XCFRAMEWORK=$(find "$WORK_DIR/dist" -name "Libmpv.xcframework" -type d | head -1)
if [ -z "$XCFRAMEWORK" ]; then
    echo "error: Libmpv.xcframework not found under $WORK_DIR/dist" >&2
    exit 1
fi
rm -rf "$DEST/Libmpv.xcframework"
mkdir -p "$DEST"
cp -R "$XCFRAMEWORK" "$DEST/"

echo "==> Done. Rebuild the app (xcodegen generate && xcodebuild ...) to pick it up."
