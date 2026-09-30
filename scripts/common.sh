#!/bin/zsh
# 公共函数：setup 脚本共用
# shellcheck shell=bash

REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
RUNTIME="$REPO/runtime"
MODELS="$REPO/models"
ENGINES_DIR="$HOME/Library/Application Support/OCRGUI/Engines"

log()   { echo "[$(date '+%H:%M:%S')] $*"; }
fail()  { log "✗ $*"; exit 1; }

# 选一个可用的 python3（优先 3.12，paddle/mlx 系 wheel 支持最稳）
pick_python() {
  for candidate in /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3 \
                   /usr/local/bin/python3 /usr/bin/python3 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# 写引擎配置 JSON（stdin 传入内容）
# 用法：write_engine <文件名>
write_engine() {
  mkdir -p "$ENGINES_DIR"
  local target="$ENGINES_DIR/$1"
  cat > "$target"
  log "已写入引擎配置：$target"
}
