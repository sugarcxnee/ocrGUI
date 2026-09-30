#!/bin/zsh
# 引擎安装入口：通用安装器 + 项目自带引擎 + 示例配方
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== OCR GUI 引擎安装 =="
echo "  1) 安装任意 transformers VLM 模型（输入 HF repo，如 Qwen/Qwen3.5-VL-2B-Instruct）"
echo "  2) 安装任意 MLX 模型（输入 mlx-community repo）"
echo "  3) Paddle 经典 PP-OCRv6（项目自带 json-http 引擎）"
echo "  ---- 示例配方 ----"
echo "  4) Xiaomi-OCR-0（0.8B VLM）"
echo "  5) PaddleOCR-VL 1.6（MLX 4bit）"
echo "  q) 退出"
printf "选择 [1-5/q]: "
read -r choice

case "$choice" in
  1)
    printf "HF repo（如 SeerRay-Lab/Xiaomi-OCR-0）: "
    read -r repo
    printf "端口（回车默认 8114）: "
    read -r port
    "$DIR/setup_vlm_engine.sh" --repo "$repo" ${port:+--port "$port"}
    ;;
  2)
    printf "mlx-community repo（如 mlx-community/PaddleOCR-VL-1.6-4bit）: "
    read -r repo
    printf "端口（回车默认 8112）: "
    read -r port
    "$DIR/setup_mlx_engine.sh" --repo "$repo" ${port:+--port "$port"}
    ;;
  3) "$DIR/setup_paddle_classic.sh" ;;
  4) "$DIR/recipes/xiaomi-ocr-0.sh" ;;
  5) "$DIR/recipes/paddle-vl.sh" ;;
  *) echo "退出"; exit 0 ;;
esac
