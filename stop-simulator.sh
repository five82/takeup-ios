#!/bin/bash
# Shuts down every booted iOS simulator.
#
# Shutting a device down also stops the app running on it, which is what
# silences a headless simulator still playing audio. The physical iPad is not
# a simulator and is left alone.

set -euo pipefail

booted=$(xcrun simctl list devices | grep "(Booted)" || true)

if [ -z "$booted" ]; then
    echo "No simulator is booted."
    exit 0
fi

echo "$booted" | sed 's/^ */Stopping /'
xcrun simctl shutdown all
