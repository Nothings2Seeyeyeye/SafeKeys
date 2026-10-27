#!/usr/bin/env bash
# SafeKeys 彻底卸载
#
#   1. 先让正在运行的 App 优雅退出（顺带解除键盘锁定）
#   2. 调用 App 自带的 --uninstall 清理用户数据与隐私授权记录
#   3. 删除 App 本体
#   4. 再兜底扫一遍清单，并逐项校验是否真的删干净
#
# 用法：
#   ./scripts/uninstall.sh            # 交互式，会先列出待删清单
#   ./scripts/uninstall.sh --yes      # 跳过确认
#   ./scripts/uninstall.sh /绝对路径/SafeKeys.app
set -o pipefail

APP_NAME="SafeKeys"
BUNDLE_ID="cn.open-book.SafeKeys"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ASSUME_YES=0
EXTRA_PATH=""
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help)
      echo "用法: $0 [--yes] [App 路径]"
      exit 0 ;;
    *) EXTRA_PATH="$arg" ;;
  esac
done

HOME_LIB="$HOME/Library"

# 用户级残留清单（白名单，不做任何通配扫描）
RESIDUE=(
  "$HOME_LIB/Preferences/$BUNDLE_ID.plist"
  "$HOME_LIB/Application Support/$APP_NAME"
  "$HOME_LIB/Application Support/$BUNDLE_ID"
  "$HOME_LIB/Caches/$BUNDLE_ID"
  "$HOME_LIB/Caches/$BUNDLE_ID.userDiagnosticReports"
  "$HOME_LIB/HTTPStorages/$BUNDLE_ID"
  "$HOME_LIB/HTTPStorages/$BUNDLE_ID.binarycookies"
  "$HOME_LIB/Saved Application State/$BUNDLE_ID.savedState"
  "$HOME_LIB/Logs/$APP_NAME"
  "$HOME_LIB/LaunchAgents/$BUNDLE_ID.plist"
  "$HOME_LIB/LaunchAgents/$BUNDLE_ID.helper.plist"
  "$HOME_LIB/Containers/$BUNDLE_ID"
)

# 待删除的 App 本体
APP_PATHS=()
for candidate in \
  "/Applications/$APP_NAME.app" \
  "$HOME/Applications/$APP_NAME.app" \
  "$PROJECT_ROOT/dist/$APP_NAME.app"; do
  [[ -e "$candidate" ]] && APP_PATHS+=("$candidate")
done
if [[ -n "$EXTRA_PATH" ]]; then
  if [[ -e "$EXTRA_PATH" ]]; then
    APP_PATHS+=("$EXTRA_PATH")
  else
    echo "!! 指定的路径不存在: $EXTRA_PATH"
    exit 1
  fi
fi

# 实际存在的残留项
EXISTING_RESIDUE=()
for item in "${RESIDUE[@]}"; do
  [[ -e "$item" ]] && EXISTING_RESIDUE+=("$item")
done

echo "SafeKeys 卸载"
echo "────────────────────────────────────────"

if [[ ${#APP_PATHS[@]} -eq 0 && ${#EXISTING_RESIDUE[@]} -eq 0 ]]; then
  echo "没有找到 SafeKeys 的任何文件，无需清理。"
  exit 0
fi

echo "⚠️  此操作会永久删除以下文件，且无法恢复："
echo
if [[ ${#APP_PATHS[@]} -gt 0 ]]; then
  echo "  App 本体："
  for item in "${APP_PATHS[@]}"; do echo "    • $item"; done
fi
if [[ ${#EXISTING_RESIDUE[@]} -gt 0 ]]; then
  echo "  用户数据与缓存："
  for item in "${EXISTING_RESIDUE[@]}"; do echo "    • ${item/#$HOME/~}"; done
fi
echo "  隐私授权记录："
echo "    • 辅助功能 / 输入监控 (${BUNDLE_ID})"
echo

if [[ $ASSUME_YES -eq 0 ]]; then
  read -r -p "确认删除？[y/N] " answer
  case "$answer" in
    [yY]*) ;;
    *) echo "已取消，没有做任何改动。"; exit 0 ;;
  esac
fi

echo
echo "==> 停止正在运行的实例"
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    sleep 0.6
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
  done
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
    sleep 1
  fi
  echo "    已退出（键盘解锁随之恢复）"
else
  echo "    没有运行中的实例"
fi

echo "==> 清理配置、缓存与隐私授权"
for item in "${EXISTING_RESIDUE[@]}"; do
  rm -rf "$item" 2>/dev/null || true
  echo "    已删除 ${item/#$HOME/~}"
done
if [[ ${#EXISTING_RESIDUE[@]} -eq 0 ]]; then
  echo "    没有找到用户数据"
fi
TCC_DONE=0
TCC_ERR=""
for service in Accessibility InputMonitoring ListenEvent; do
  if TCC_ERR=$(/usr/bin/tccutil reset "$service" "$BUNDLE_ID" 2>&1); then
    TCC_DONE=1
  fi
done
if [[ $TCC_DONE -eq 1 ]]; then
  echo "    已重置隐私授权记录"
else
  echo "    没有可清除的授权条目（可能本来就没授权过）"
  if [[ -n "$TCC_ERR" ]]; then
    echo "      tccutil 返回：${TCC_ERR#*: }"
    echo "      若为权限不足，请给终端授予「完全磁盘访问权限」后重跑一次"
  fi
fi

echo "==> 删除 App 本体"
for app in "${APP_PATHS[@]}"; do
  rm -rf "$app" && echo "    已删除 $app"
done

echo "==> 校验残留"
LEFTOVER=0
for app in "${APP_PATHS[@]}"; do
  if [[ -e "$app" ]]; then
    echo "    ✗ 仍存在: $app"
    LEFTOVER=1
  fi
done
for item in "${RESIDUE[@]}"; do
  if [[ -e "$item" ]]; then
    echo "    ✗ 仍存在: ${item/#$HOME/~}"
    LEFTOVER=1
  fi
done

echo "────────────────────────────────────────"
if [[ $LEFTOVER -eq 0 ]]; then
  echo "✅ 已彻底移除，磁盘上没有留下任何 SafeKeys 痕迹。"
  echo
  echo "唯一需要手动的一件事：如果你把图标拖过 Dock 或 Launchpad，"
  echo "把它拖出去即可（macOS 不允许第三方脚本改动 Dock 布局）。"
else
  echo "⚠️  仍有残留，请检查上面列出的项目。"
fi
