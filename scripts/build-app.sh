#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "Нужен полный Xcode. Установите Xcode и выберите его через xcode-select." >&2
    exit 2
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "Нужен CMake (например, brew install cmake)." >&2
    exit 2
fi

if ! xcrun --find metal >/dev/null 2>&1; then
    echo "Активный Xcode не содержит Metal compiler; выберите полный Xcode через xcode-select." >&2
    exit 2
fi

cmake -S "$ROOT" -B "$ROOT/build/whisper" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.2
cmake --build "$ROOT/build/whisper" --config Release --parallel

cd "$ROOT"
swift build -c release

APP="$ROOT/dist/VoiceBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$ROOT/.build/release/VoiceBar" "$APP/Contents/MacOS/VoiceBar"
cp "$ROOT/build/whisper/libVoiceBarWhisper.dylib" "$APP/Contents/Frameworks/"
cp "$ROOT/AppInfo.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - --timestamp=none "$APP"

echo "Готово: $APP"
