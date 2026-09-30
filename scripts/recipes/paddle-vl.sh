#!/bin/zsh
# 配方：PaddleOCR-VL 1.6（MLX 4bit 量化，整页 Markdown 版面还原）
# 只是给通用安装器传参。
set -euo pipefail
exec "$(dirname "$0")/../setup_mlx_engine.sh" \
  --repo "mlx-community/PaddleOCR-VL-1.6-4bit" \
  --id "paddle-vl" \
  --name "PaddleOCR-VL 1.6（MLX 加速）" \
  --port 8112 \
  --prompt "Text Recognition:"
