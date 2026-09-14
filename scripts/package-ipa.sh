#!/usr/bin/env bash
# 将 xcodebuild 产出的 .app 打包为 .ipa（供 Sideloadly 侧载）
set -euo pipefail

APP_PATH="${1:-}"
OUTPUT="${2:-build/iPadSVN.ipa}"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Usage: $0 <path/to/iPadSVN.app> [output.ipa]" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="${ROOT}/build/ipa-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
cp -R "$APP_PATH" "$STAGE/Payload/"

mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"
(cd "$STAGE" && zip -qr "$ROOT/$OUTPUT" Payload)

echo "IPA created: $ROOT/$OUTPUT"
ls -lh "$ROOT/$OUTPUT"
