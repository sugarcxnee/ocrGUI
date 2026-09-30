#!/bin/zsh
# 一键配置全部外部引擎（可单独运行各 setup 脚本）
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== 可选引擎配置 =="
echo "  1) Paddle 经典 PP-OCRv6（det+rec，坐标框+置信度，约 1.3GB 依赖）"
echo "  2) PaddleOCR-VL 1.6（MLX，整页 Markdown，约 1.4GB）"
echo "  3) Xiaomi-OCR-0（实验性 VLM，约 4-5GB 含 torch）"
echo "  a) 全部"
echo "  q) 退出"
printf "选择 [1/2/3/a/q]: "
read -r choice

case "$choice" in
  1) "$DIR/setup_paddle_classic.sh" ;;
  2) "$DIR/setup_paddle_vl.sh" ;;
  3) "$DIR/setup_xiaomi.sh" ;;
  a) "$DIR/setup_paddle_classic.sh" && "$DIR/setup_paddle_vl.sh" && "$DIR/setup_xiaomi.sh" ;;
  *) echo "退出"; exit 0 ;;
esac
