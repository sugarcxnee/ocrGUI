#!/bin/zsh
# 冒烟测试：paddle_classic_server.py 服务 + /ocr 协议
# 用法：scripts/smoke_paddle_classic.sh [python解释器] [测试图片]
#   python 解释器缺省用 runtime/paddle-classic-env；也可以传其他装有 paddleocr 的解释器
set -euo pipefail
source "$(dirname "$0")/common.sh"

PORT=18113
PYTHON="${1:-$RUNTIME/paddle-classic-env/bin/python}"
IMAGE="${2:-}"

# 模型缓存：默认项目内目录，可通过环境变量覆盖（如借用其他已下载的缓存）
export PADDLE_PDX_CACHE_HOME="${PADDLE_PDX_CACHE_HOME:-$MODELS/paddlex_cache}"
export PADDLE_PDX_MODEL_SOURCE="${PADDLE_PDX_MODEL_SOURCE:-modelscope}"
export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True
mkdir -p "$PADDLE_PDX_CACHE_HOME"

if [[ ! -x "$PYTHON" ]]; then
  echo "✗ 未找到解释器：$PYTHON（先运行 scripts/setup_paddle_classic.sh）"
  exit 1
fi
if [[ -z "$IMAGE" ]]; then
  IMAGE="$REPO/tests/fixtures/smoke_cn.png"
  if [[ ! -f "$IMAGE" ]]; then
    "$PYTHON" - "$IMAGE" <<'PYEOF'
import sys
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (800, 300), "white")
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/System/Library/Fonts/PingFang.ttc", 48)
except Exception:
    font = ImageFont.load_default()
d.text((40, 40), "Hello OCR 12345", fill="black", font=font)
d.text((40, 160), "你好世界冒烟测试", fill="black", font=font)
img.save(sys.argv[1])
print(f"生成测试图：{sys.argv[1]}")
PYEOF
  fi
fi

log "启动服务（端口 $PORT，预加载模型）…"
"$PYTHON" "$REPO/scripts/paddle_classic_server.py" --port $PORT --preload &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

for i in {1..120}; do
  if curl -s --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then break; fi
  sleep 1
done
log "健康检查：$(curl -s "http://127.0.0.1:$PORT/health")"

log "识别 $IMAGE …"
"$PYTHON" - "$IMAGE" "$PORT" <<'PYEOF'
import base64, json, sys, urllib.request
image_path, port = sys.argv[1], sys.argv[2]
with open(image_path, "rb") as f:
    b64 = base64.b64encode(f.read()).decode()
payload = json.dumps({"image_b64": b64}).encode()
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/ocr", data=payload,
    headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=300) as resp:
    result = json.load(resp)
lines = result.get("lines", [])
print(f"width={result.get('width')} height={result.get('height')} lines={len(lines)}")
for line in lines:
    print(f"  [{line['score']:.3f}] {line['text']}")
assert len(lines) >= 2, "识别行数不足"
texts = "".join(line["text"] for line in lines)
assert "12345" in texts or "OCR" in texts.upper(), f"英文数字未识别: {texts}"
print("SMOKE OK ✓")
PYEOF
log "✓ 冒烟测试通过"
