#!/bin/zsh
# 通用 MLX 引擎安装器：任意 mlx-community 的 OpenAI 兼容模型（mlx_vlm.server）。
#
# 用法：
#   scripts/setup_mlx_engine.sh --repo <mlx-community/...> [--id <id>] [--name <名称>]
#                               [--port 8112] [--prompt <提示词>] [--venv runtime/mlx-env]
# 示例：
#   scripts/setup_mlx_engine.sh --repo mlx-community/PaddleOCR-VL-1.6-4bit --port 8112
set -euo pipefail
source "$(dirname "$0")/common.sh"

REPO_ID=""
ENGINE_ID=""
ENGINE_NAME=""
PORT=8112
PROMPT="Text Recognition:"
VENV_DIR="$RUNTIME/mlx-env"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ID="$2"; shift 2 ;;
    --id) ENGINE_ID="$2"; shift 2 ;;
    --name) ENGINE_NAME="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --venv) VENV_DIR="$2"; shift 2 ;;
    *) echo "未知参数：$1"; exit 1 ;;
  esac
done

[[ -n "$REPO_ID" ]] || { echo "用法：$0 --repo <mlx-community/...> [选项]"; exit 1; }
[[ -n "$ENGINE_ID" ]] || ENGINE_ID="${REPO_ID##*/}"
[[ -n "$ENGINE_NAME" ]] || ENGINE_NAME="$ENGINE_ID"
MODEL_DIR="$MODELS/$ENGINE_ID"

log "=== 安装 MLX 引擎：$REPO_ID（端口 $PORT）==="
PY="$(pick_python)" || fail "未找到 python3"

if [[ ! -x "$VENV_DIR/bin/pip" ]]; then
  log "创建虚拟环境 $VENV_DIR …"
  "$PY" -m venv "$VENV_DIR"
fi
if ! "$VENV_DIR/bin/python" -c "import mlx_vlm" >/dev/null 2>&1; then
  log "安装依赖（mlx-vlm 等，约 700MB）…"
  "$VENV_DIR/bin/pip" install --quiet --upgrade pip
  "$VENV_DIR/bin/pip" install mlx-vlm
fi

if [[ ! -f "$MODEL_DIR/model.safetensors" ]]; then
  log "下载模型 $REPO_ID（大小视模型而定）…"
  "$VENV_DIR/bin/hf" download "$REPO_ID" --local-dir "$MODEL_DIR"
fi

log "写入引擎配置（id=$ENGINE_ID）…"
write_engine "$ENGINE_ID.json" <<JSON
{
  "id": "$ENGINE_ID",
  "name": "$ENGINE_NAME",
  "kind": "openai-http",
  "enabled": true,
  "base_url": "http://127.0.0.1:$PORT/v1",
  "model": "$MODEL_DIR",
  "prompt": "$PROMPT",
  "timeout": 600,
  "launch": {
    "command": "$VENV_DIR/bin/mlx_vlm.server --model $MODEL_DIR --trust-remote-code --host 127.0.0.1 --port $PORT",
    "cwd": "$REPO",
    "environment": {},
    "health_url": "http://127.0.0.1:$PORT/health",
    "ready_timeout": 180
  },
  "notes": "MLX 加速引擎（$REPO），由 setup_mlx_engine.sh 安装。"
}
JSON

log "✓ 完成。打开 OCR GUI 设置即可启动 $ENGINE_NAME。"
