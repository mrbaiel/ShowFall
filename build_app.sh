#!/bin/bash
# Собирает Snowfall.app (без иконки в доке), можно закинуть в /Applications
set -e
swift build -c release
APP="build/Snowfall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Snowfall "$APP/Contents/MacOS/Snowfall"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Готово: $APP"
