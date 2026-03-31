#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-/tmp/clickcherry-overlay-visual-checks}"
BIN_PATH="/tmp/generate_overlay_visual_checks"

swiftc \
  "$ROOT_DIR/scripts/generate_overlay_visual_checks.swift" \
  "$ROOT_DIR/TaskAgentMacOSApp/TaskAgentMacOSApp/Services/DesktopScreenshotTransformService.swift" \
  -o "$BIN_PATH"

"$BIN_PATH" "$OUT_DIR"
echo "Wrote visual checks to: $OUT_DIR"
