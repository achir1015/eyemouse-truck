#!/usr/bin/env bash
# 匯出線上版（Godot Web，單執行緒，GitHub Pages 可直接放）→ ../build/web，並壓成 ../build/release/EyeMouseTruck-web.zip
# 用法：bash tools/build_web.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(cd .. && pwd)"
GODOT="/e/從零建置 Godot 賽車遊戲/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
rm -rf "$ROOT/build/web" && mkdir -p "$ROOT/build/web" "$ROOT/build/release"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" "$ROOT/build/web/index.html" 2>&1 | grep -E "ERROR" || true
rm -f "$ROOT/build/release/EyeMouseTruck-web.zip"
(cd "$ROOT/build/web" && powershell -NoProfile -Command "Compress-Archive -Path * -DestinationPath '$(cygpath -w "$ROOT/build/release")\EyeMouseTruck-web.zip'")
ls -la "$ROOT/build/web" "$ROOT/build/release/EyeMouseTruck-web.zip"
