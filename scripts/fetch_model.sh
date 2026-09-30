#!/bin/zsh
# 通用 HuggingFace 模型下载：scripts/fetch_model.sh <repo> [目标目录]
# 使用 runtime 下任一 venv 自带的 hf 命令（先跑过任一 setup 脚本即可）
set -euo pipefail
source "$(dirname "$0")/common.sh"

[[ $# -ge 1 ]] || { echo "用法：$0 <HF repo> [目标目录（默认 models/<repo 名>）]"; exit 1; }
REPO_ID="$1"
DEST="${2:-$MODELS/${REPO_ID##*/}}"

HF_BIN=""
for env in "$RUNTIME"/*-env; do
  if [[ -x "$env/bin/hf" ]]; then
    HF_BIN="$env/bin/hf"
    break
  fi
done

if [[ -z "$HF_BIN" ]]; then
  echo "✗ 未找到 hf 命令。请先运行任一 setup 脚本（如 scripts/setup_xiaomi.sh）创建 runtime venv。"
  exit 1
fi

mkdir -p "$DEST"
log "下载 $REPO_ID → $DEST"
exec "$HF_BIN" download "$REPO_ID" --local-dir "$DEST"
