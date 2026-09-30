#!/bin/zsh
# 配方：Xiaomi-OCR-0（SeerRay-Lab，0.8B VLM，2026-09 发布）
# 只是给通用安装器传参——换成任何 HF VLM repo 即可接入其他模型。
set -euo pipefail
exec "$(dirname "$0")/../setup_vlm_engine.sh" \
  --repo "SeerRay-Lab/Xiaomi-OCR-0" \
  --id "xiaomi-ocr-0" \
  --name "Xiaomi-OCR-0（实验性）" \
  --port 8114 \
  --fallback-prompt "Task: Text Extraction." \
  --venv "$(
    d="$(cd "$(dirname "$0")/../.." && pwd)/runtime/xiaomi-env"
    [[ -d "$d" ]] && echo "$d" || echo "$(cd "$(dirname "$0")/../.." && pwd)/runtime/vlm-env"
  )"
