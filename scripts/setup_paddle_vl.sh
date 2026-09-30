#!/bin/zsh
# 配置 PaddleOCR-VL 1.6 引擎（MLX 4bit 量化，Apple GPU 加速，整页 Markdown 版面还原）
# 产物：runtime/paddle-vl-env + models/PaddleOCR-VL-1.6-4bit(682MB) + 引擎配置（端口 8112）
set -euo pipefail
source "$(dirname "$0")/common.sh"

ENV_DIR="$RUNTIME/paddle-vl-env"
MODEL_DIR="$MODELS/PaddleOCR-VL-1.6-4bit"
PORT=8112

log "=== 配置 PaddleOCR-VL 1.6（MLX）引擎 ==="
PY="$(pick_python)" || fail "未找到 python3"

if [[ ! -x "$ENV_DIR/bin/pip" ]]; then
  log "创建虚拟环境 $ENV_DIR …"
  "$PY" -m venv "$ENV_DIR"
fi

log "安装依赖（mlx-vlm 等，约 700MB）…"
"$ENV_DIR/bin/pip" install --quiet --upgrade pip
"$ENV_DIR/bin/pip" install mlx-vlm

if [[ ! -f "$MODEL_DIR/model.safetensors" ]]; then
  log "下载模型 mlx-community/PaddleOCR-VL-1.6-4bit（682MB）…"
  "$ENV_DIR/bin/hf" download mlx-community/PaddleOCR-VL-1.6-4bit --local-dir "$MODEL_DIR"
fi

log "写入引擎配置（端口 $PORT）…"
write_engine "paddle-vl.json" <<JSON
{
  "id": "paddle-vl",
  "name": "PaddleOCR-VL 1.6（MLX 加速）",
  "kind": "openai-http",
  "enabled": true,
  "base_url": "http://127.0.0.1:$PORT/v1",
  "model": "$MODEL_DIR",
  "prompt": "Text Recognition:",
  "timeout": 600,
  "launch": {
    "command": "$ENV_DIR/bin/mlx_vlm.server --model $MODEL_DIR --trust-remote-code --host 127.0.0.1 --port $PORT",
    "cwd": "$REPO",
    "environment": {},
    "health_url": "http://127.0.0.1:$PORT/health",
    "ready_timeout": 180
  },
  "notes": "整页版面还原为 Markdown（含 LaTeX 公式、表格）。模型加载冷启动约 40 秒。"
}
JSON

log "✓ 完成。打开 OCR GUI 设置即可启动该引擎。"
