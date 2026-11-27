#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
project_dir="$(pwd)"
build_dir="$project_dir/build"
application="$build_dir/Gestures and Scroll.app"
target="arm64-apple-macos14.0"
sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$build_dir/module-cache" "$application/Contents/MacOS" "$application/Contents/Resources"
/usr/bin/xcrun clang -isysroot "$sdk" -target "$target" -O2 -Wall -Wextra -Werror \
    -c Sources/InputHardware.c -o "$build_dir/InputHardware.o"
/usr/bin/xcrun swiftc -sdk "$sdk" -target "$target" -swift-version 5 -O -warnings-as-errors \
    -module-cache-path "$build_dir/module-cache" -import-objc-header Sources/InputHardware.h \
    Sources/*.swift "$build_dir/InputHardware.o" \
    -framework AppKit -framework Carbon -framework IOKit -framework ApplicationServices \
    -o "$application/Contents/MacOS/GesturesAndScroll"
/usr/bin/xcrun swiftc -sdk "$sdk" -target "$target" -O \
    -module-cache-path "$build_dir/module-cache" Tools/MakeAppIcon.swift -o "$build_dir/MakeAppIcon"
"$build_dir/MakeAppIcon" "$application/Contents/Resources/AppIcon.icns"
/usr/bin/install -m 644 Resources/Info.plist "$application/Contents/Info.plist"
/usr/bin/install -m 644 LICENSE NOTICE "$application/Contents/Resources/"
for locale in en ru; do
    mkdir -p "$application/Contents/Resources/$locale.lproj"
    /usr/bin/install -m 644 "Resources/$locale.lproj/InfoPlist.strings" \
        "$application/Contents/Resources/$locale.lproj/InfoPlist.strings"
done
/usr/bin/codesign --force --sign - --timestamp=none "$application"
/usr/bin/codesign --verify --strict "$application"
printf '%s\n' "$application"
