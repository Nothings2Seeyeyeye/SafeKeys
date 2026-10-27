#!/usr/bin/env bash
# 无需 Xcode：SwiftPM 编译 + 手工组装 .app bundle + ad-hoc 签名
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="SafeKeys"
ARCH="arm64"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> 编译 release"
BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)"
EXEC="$BIN/$APP_NAME"

if [[ ! -f "$EXEC" ]]; then
  echo "!! 找不到编译产物: $EXEC" >&2
  exit 1
fi

echo "==> 组装 bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$EXEC" "$APP/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> 打包图标资源"
if [[ -f "Resources/icon/AppIcon.icns" ]]; then
  cp "Resources/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "  (未找到 Resources/icon/AppIcon.icns，跳过 — 图标将使用系统默认)"
fi

echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$APP"

echo "==> 签名校验"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3

echo "==> 生成卸载入口"
cat > "$DIST/卸载 SafeKeys.command" <<'CMDEOF'
#!/bin/bash
# 双击即可卸载 SafeKeys（此文件与本目录同级时也走同一套清理逻辑）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "$SCRIPT_DIR/../scripts/uninstall.sh" "$@"
CMDEOF
chmod +x "$DIST/卸载 SafeKeys.command"

echo
echo "完成: $PWD/$APP"
echo "首次运行请执行:  open \"$APP\""
echo "彻底卸载请执行:  ./scripts/uninstall.sh   （或双击 \"卸载 SafeKeys.command\"）"
