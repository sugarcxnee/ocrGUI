#!/bin/zsh
# 配置 Xiaomi-OCR-0 引擎（0.8B VLM，transformers + MPS，实验性）
# 产物：runtime/xiaomi-env + models/Xiaomi-OCR-0(1.7GB) + 引擎配置（端口 8114）
set -euo pipefail
source "$(dirname "$0")/common.sh"

ENV_DIR="$RUNTIME/xiaomi-env"
MODEL_DIR="$MODELS/Xiaomi-OCR-0"
PORT=8114

log "=== 配置 Xiaomi-OCR-0 引擎（实验性，模型发布于 2026-09-28）==="
PY="$(pick_python)" || fail "未找到 python3"

if [[ ! -x "$ENV_DIR/bin/pip" ]]; then
  log "创建虚拟环境 $ENV_DIR …"
  "$PY" -m venv "$ENV_DIR"
fi

log "安装依赖（torch + torchvision + transformers 5.17 + fastapi，torch 下载约 2-3GB）…"
"$ENV_DIR/bin/pip" install --quiet --upgrade pip
"$ENV_DIR/bin/pip" install torch torchvision "transformers==5.17.0" pillow fastapi uvicorn numpy

if [[ ! -f "$MODEL_DIR/model.safetensors" ]]; then
  log "下载模型 SeerRay-Lab/Xiaomi-OCR-0（1.7GB）…"
  "$ENV_DIR/bin/hf" download SeerRay-Lab/Xiaomi-OCR-0 --local-dir "$MODEL_DIR"
fi

log "写入引擎配置（端口 $PORT）…"
write_engine "xiaomi-ocr-0.json" <<JSON
{
  "id": "xiaomi-ocr-0",
  "name": "Xiaomi-OCR-0（实验性）",
  "kind": "openai-http",
  "enabled": true,
  "base_url": "http://127.0.0.1:$PORT/v1",
  "model": "$MODEL_DIR",
  "prompt": "Task: Text Extraction.",
  "timeout": 600,
  "launch": {
    "command": "$ENV_DIR/bin/python $REPO/scripts/vlm_server.py --model $MODEL_DIR --host 127.0.0.1 --port $PORT",
    "cwd": "$REPO",
    "environment": {},
    "health_url": "http://127.0.0.1:$PORT/health",
    "ready_timeout": 300
  },
  "notes": "小米 0.8B VLM。提示词可选：Task: Text Extraction.（纯文本）/ Task: Document Parsing.（Markdown）。"
}
JSON

log "✓ 完成。打开 OCR GUI 设置即可启动；或运行 scripts/smoke_vlm.sh 8114 验证。"
