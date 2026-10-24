#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/.build"
swiftc -parse-as-library \
    "$ROOT/Sources/VoiceBarCore/Audio/AudioSource.swift" \
    "$ROOT/Sources/VoiceBarCore/Audio/AudioChunker.swift" \
    "$ROOT/Sources/VoiceBarCore/Transcript/TranscriptChunk.swift" \
    "$ROOT/Scripts/check-core.swift" \
    -o "$ROOT/.build/VoiceBarCoreChecks"
"$ROOT/.build/VoiceBarCoreChecks"
