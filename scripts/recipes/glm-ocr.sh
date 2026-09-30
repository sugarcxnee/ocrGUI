#!/bin/zsh
# 配方：GLM-OCR（智谱 2026-02 开源，0.9B OCR 专用 VLM，MLX 4bit）
# 只是给通用 MLX 安装器传参——验证"新增引擎零核心代码改动"。
set -euo pipefail
exec "$(dirname "$0")/../setup_mlx_engine.sh" \
  --repo "mlx-community/GLM-OCR-4bit" \
  --id "glm-ocr" \
  --name "GLM-OCR（MLX 4bit）" \
  --port 8116 \
  --prompt "把图片中的内容完整转写为 Markdown。所有数学公式用 LaTeX 表示（行内用 \$...\$），不要遗漏任何文字，不要总结。/nothink"
