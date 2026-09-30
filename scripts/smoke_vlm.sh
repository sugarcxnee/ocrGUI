#!/bin/zsh
# 冒烟测试：vlm_server.py（OpenAI 兼容）服务 + /v1/chat/completions 协议
# 用法：scripts/smoke_vlm.sh [端口] [python解释器(用于生成测试图)] [提示词]
set -euo pipefail
source "$(dirname "$0")/common.sh"

PORT="${1:-8114}"
PYTHON="${2:-$RUNTIME/xiaomi-env/bin/python}"
PROMPT="${3:-Task: Text Extraction.}"
IMAGE="$REPO/tests/fixtures/smoke_cn.png"

if ! curl -s --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "✗ http://127.0.0.1:$PORT 服务未运行（先在 OCR GUI 设置中启动引擎，或手动运行 vlm_server.py）"
  exit 1
fi
log "健康检查：$(curl -s "http://127.0.0.1:$PORT/health")"

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
PYEOF
fi

log "识别 $IMAGE（prompt: $PROMPT）…"
"$PYTHON" - "$IMAGE" "$PORT" "$PROMPT" <<'PYEOF'
import base64, json, sys, urllib.request
image_path, port, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
with open(image_path, "rb") as f:
    b64 = base64.b64encode(f.read()).decode()
payload = {
    "model": "smoke",
    "messages": [{"role": "user", "content": [
        {"type": "input_image", "image_url": f"data:image/png;base64,{b64}"},
        {"type": "text", "text": prompt},
    ]}],
    "max_tokens": 2048,
    "temperature": 0,
}
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/v1/chat/completions",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=600) as resp:
    result = json.load(resp)
content = result["choices"][0]["message"]["content"]
print("--- 识别结果 ---")
print(content)
print("----------------")
assert len(content.strip()) > 0, "识别结果为空"
print("SMOKE OK ✓")
PYEOF
log "✓ 冒烟测试通过"
