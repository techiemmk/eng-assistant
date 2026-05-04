#!/usr/bin/env bash
# Wraps `swift test` with the framework search paths needed when running with
# Apple Command Line Tools (no full Xcode). Once Xcode is installed, plain
# `swift test` will work and this script can be deleted.
set -euo pipefail
TESTING_FW="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
exec swift test \
  -Xswiftc -F -Xswiftc "$TESTING_FW" \
  -Xlinker -F -Xlinker "$TESTING_FW" \
  -Xlinker -rpath -Xlinker "$TESTING_FW" \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib \
  "$@"
