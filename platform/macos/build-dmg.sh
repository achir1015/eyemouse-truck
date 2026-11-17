#!/bin/bash
# 在 Mac 上匯出 macOS 版（Intel＋Apple 晶片通用），ad-hoc 簽章後包成 DMG。可直接用 SSH 執行。
# 產出：~/Developer/eyemouse-truck-build/EyeMouseTruck-macOS.dmg
set -e
PROJ=~/Developer/eyemouse-truck
OUT=~/Developer/eyemouse-truck-build/macos
GODOT=~/Developer/godot/Godot.app/Contents/MacOS/Godot
NAME="眼動鼠之寶島卡車"

rm -rf "$OUT" && mkdir -p "$OUT"
"$GODOT" --headless --path "$PROJ" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$PROJ" --export-release "macOS" "$OUT/EyeMouseTruck.app" 2>&1 | grep -E "ERROR|DONE" || true
cd "$OUT"
mv EyeMouseTruck.app "$NAME.app"
xattr -cr "$NAME.app"
codesign --force --deep -s - "$NAME.app"
codesign --verify --deep "$NAME.app"
mkdir dmg && cp -R "$NAME.app" dmg/ && ln -s /Applications dmg/Applications
hdiutil create -volname "$NAME" -srcfolder dmg -ov -format UDZO -size 900m ../EyeMouseTruck-macOS.dmg >/dev/null
rm -rf dmg
ls -l ../EyeMouseTruck-macOS.dmg
