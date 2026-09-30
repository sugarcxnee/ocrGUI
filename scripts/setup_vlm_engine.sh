#!/bin/zsh
# 通用 transformers VLM 引擎安装器：任意 HuggingFace image-text-to-text 模型
# 经 scripts/vlm_server.py（OpenAI 兼容）接入 OCR GUI。
#
# 用法：
#   scripts/setup_vlm_engine.sh --repo <HF repo> [--id <engine-id>] [--name <名称>]
#                               [--port 8114] [--prompt <提示词>] [--fallback-prompt <兜底>]
#                               [--venv runtime/vlm-env] [--ready-timeout 300]
# 示例：
#   scripts/setup_vlm_engine.sh --repo SeerRay-Lab/Xiaomi-OCR-0 --port 8114 \
#       --fallback-prompt "Task: Text Extraction."
#   scripts/setup_vlm_engine.sh --repo Qwen/Qwen3.5-VL-2B-Instruct --port 8115
set -euo pipefail
source "$(dirname "$0")/common.sh"

REPO_ID=""
ENGINE_ID=""
ENGINE_NAME=""
PORT=8114
PROMPT="把图片中的内容完整转写为 Markdown。所有数学公式用 LaTeX 表示（行内用 \$...\$），不要遗漏任何文字，不要总结。"
FALLBACK_PROMPT=""
VENV_DIR="$RUNTIME/vlm-env"
READY_TIMEOUT=300

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ID="$2"; shift 2 ;;
    --id) ENGINE_ID="$2"; shift 2 ;;
    --name) ENGINE_NAME="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --fallback-prompt) FALLBACK_PROMPT="$2"; shift 2 ;;
    --venv) VENV_DIR="$2"; shift 2 ;;
    --ready-timeout) READY_TIMEOUT="$2"; shift 2 ;;
    *) echo "未知参数：$1"; exit 1 ;;
  esac
done

[[ -n "$REPO_ID" ]] || { echo "用法：$0 --repo <HF repo> [选项]（见脚本头部注释）"; exit 1; }
[[ -n "$ENGINE_ID" ]] || ENGINE_ID="${REPO_ID##*/}"
[[ -n "$ENGINE_NAME" ]] || ENGINE_NAME="$ENGINE_ID"
MODEL_DIR="$MODELS/$ENGINE_ID"

log "=== 安装 VLM 引擎：$REPO_ID（端口 $PORT）==="
PY="$(pick_python)" || fail "未找到 python3"

if [[ ! -x "$VENV_DIR/bin/pip" ]]; then
  log "创建虚拟环境 $VENV_DIR（多引擎共享，torch 只装一次）…"
  "$PY" -m venv "$VENV_DIR"
fi

if [[ ! -x "$VENV_DIR/bin/python" ]] || ! "$VENV_DIR/bin/python" -c "import torch, transformers, fastapi" >/dev/null 2>&1; then
  log "安装依赖（torch/torchvision/transformers/fastapi，首次约 2-3GB）…"
  "$VENV_DIR/bin/pip" install --quiet --upgrade pip
  "$VENV_DIR/bin/pip" install torch torchvision transformers pillow fastapi uvicorn numpy
fi

if [[ ! -f "$MODEL_DIR/model.safetensors" && ! -f "$MODEL_DIR/config.json" ]]; then
  log "下载模型 $REPO_ID → $MODEL_DIR …"
  "$VENV_DIR/bin/hf" download "$REPO_ID" --local-dir "$MODEL_DIR"
fi

log "写入引擎配置（id=$ENGINE_ID）…"
FALLBACK_LINE=""
if [[ -n "$FALLBACK_PROMPT" ]]; then
  FALLBACK_LINE="\"fallback_prompt\": \"$FALLBACK_PROMPT\","
fi
write_engine "$ENGINE_ID.json" <<JSON
{
  "id": "$ENGINE_ID",
  "name": "$ENGINE_NAME",
  "kind": "openai-http",
  "enabled": true,
  "base_url": "http://127.0.0.1:$PORT/v1",
  "model": "$MODEL_DIR",
  "prompt": "$PROMPT",
  $FALLBACK_LINE
  "timeout": 600,
  "launch": {
    "command": "$VENV_DIR/bin/python $REPO/scripts/vlm_server.py --model $MODEL_DIR --host 127.0.0.1 --port $PORT",
    "cwd": "$REPO",
    "environment": {},
    "health_url": "http://127.0.0.1:$PORT/health",
    "ready_timeout": $READY_TIMEOUT
  },
  "notes": "任意 transformers VLM 引擎（$REPO），由 setup_vlm_engine.sh 安装。"
}
JSON

log "✓ 完成。打开 OCR GUI 设置即可启动 $ENGINE_NAME。"
