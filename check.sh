#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p build/check-cache
sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
target="arm64-apple-macos14.0"

/usr/bin/xcrun clang -isysroot "$sdk" -target "$target" -Wall -Wextra -Werror \
    -c Sources/InputHardware.c -o build/ChecksHardware.o
/usr/bin/xcrun swiftc -sdk "$sdk" -target "$target" -swift-version 5 -warnings-as-errors \
    -module-cache-path build/check-cache -import-objc-header Sources/InputHardware.h \
    Sources/InputProfile.swift Sources/GestureRecognizer.swift Sources/TrackpadDrawing.swift \
    Sources/DrawingApplication.swift Sources/ScrollEngine.swift \
    Sources/InputController.swift Sources/SettingsView.swift Sources/DrawingSettingsView.swift Tools/Checks.swift build/ChecksHardware.o \
    -framework AppKit -framework Carbon -framework IOKit -framework ApplicationServices \
    -o build/Checks
build/Checks "$@"
