#!/bin/zsh
# 配置 Paddle 经典 PP-OCRv6 引擎（det+rec，行级坐标框+置信度）
# 产物：runtime/paddle-classic-env（venv）+ models/paddlex_cache + 引擎配置（端口 8113）
set -euo pipefail
source "$(dirname "$0")/common.sh"

ENV_DIR="$RUNTIME/paddle-classic-env"
PORT=8113

log "=== 配置 Paddle 经典 PP-OCRv6 引擎 ==="
PY="$(pick_python)" || fail "未找到 python3"
log "使用 Python：$PY"

if [[ ! -x "$ENV_DIR/bin/pip" ]]; then
  log "创建虚拟环境 $ENV_DIR …"
  "$PY" -m venv "$ENV_DIR"
fi

log "安装依赖（paddleocr + paddlepaddle CPU + fastapi，约 1.3GB，需要几分钟）…"
"$ENV_DIR/bin/pip" install --quiet --upgrade pip
"$ENV_DIR/bin/pip" install \
  "paddleocr==3.7.0" "paddlepaddle==3.2.1" \
  fastapi uvicorn pillow numpy

mkdir -p "$MODELS/paddlex_cache"

log "写入引擎配置（端口 $PORT，模型缓存 $MODELS/paddlex_cache）…"
write_engine "paddle-classic.json" <<JSON
{
  "id": "paddle-classic",
  "name": "Paddle 经典 PP-OCRv6（det+rec）",
  "kind": "json-http",
  "enabled": true,
  "base_url": "http://127.0.0.1:$PORT",
  "model": null,
  "prompt": null,
  "timeout": 300,
  "launch": {
    "command": "$ENV_DIR/bin/python $REPO/scripts/paddle_classic_server.py --host 127.0.0.1 --port $PORT --preload",
    "cwd": "$REPO",
    "environment": {
      "PADDLE_PDX_CACHE_HOME": "$MODELS/paddlex_cache",
      "PADDLE_PDX_MODEL_SOURCE": "modelscope",
      "PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK": "True"
    },
    "health_url": "http://127.0.0.1:$PORT/health",
    "ready_timeout": 300
  },
  "notes": "行级坐标框+置信度，中文准确度好。首次识别会自动下载模型（已配置缓存目录）。"
}
JSON

log "✓ 完成。打开 OCR GUI 设置即可启动该引擎；或先运行 scripts/smoke_paddle_classic.sh 验证。"
