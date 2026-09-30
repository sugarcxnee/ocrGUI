#!/usr/bin/env python3
"""Paddle 经典 PP-OCRv6（det+rec）薄 HTTP 服务 —— OCR GUI 的 json-http 引擎后端。

协议：
  GET  /health      -> {"status": "ok", "model_loaded": true}
  POST /ocr         请求 {"image_b64": "<PNG/JPG base64>"}
                      响应 {"width": w, "height": h,
                            "lines": [{"text", "score", "box": [[x,y]×4]}]}

运行（通常由 OCR GUI 按引擎配置自动拉起，无需手动执行）：
  python paddle_classic_server.py --host 127.0.0.1 --port 8113 --lang ch

模型缓存目录由环境变量 PADDLE_PDX_CACHE_HOME 控制（setup 脚本写入引擎配置）。
首次识别会按需下载/加载模型，之后常驻内存。
"""
import argparse
import base64
import io
import os
import sys

import numpy as np
from PIL import Image
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn

app = FastAPI(title="paddle-classic-ocr")

_OCR = None
_ARGS = None


def get_ocr():
    global _OCR
    if _OCR is None:
        from paddleocr import PaddleOCR
        # 不同 paddleocr 版本参数白名单不同，参照 webUI 的做法：不支持的参数剔除后重试
        kwargs = {
            "lang": _ARGS.lang,
            "use_doc_orientation_classify": False,
            "use_doc_unwarping": False,
            "use_textline_orientation": True,
        }
        while True:
            try:
                _OCR = PaddleOCR(**kwargs)
                break
            except (TypeError, ValueError) as e:
                dropped = next((k for k in kwargs if k in str(e)), None)
                if dropped is None:
                    raise
                print(f"[paddle-classic] 参数 {dropped} 不受支持，已剔除（{e}）", flush=True)
                kwargs.pop(dropped)
    return _OCR


class OcrRequest(BaseModel):
    image_b64: str


@app.get("/health")
def health():
    return {"status": "ok", "model_loaded": _OCR is not None}


def box_to_quad(box):
    """四点多边形保持原样；矩形 [x1,y1,x2,y2] 转四点框"""
    if len(box) == 4 and not hasattr(box[0], "__len__"):
        x1, y1, x2, y2 = [float(v) for v in box]
        return [[x1, y1], [x2, y1], [x2, y2], [x1, y2]]
    return [[float(p[0]), float(p[1])] for p in box]


@app.post("/ocr")
def ocr(req: OcrRequest):
    raw = base64.b64decode(req.image_b64)
    image = Image.open(io.BytesIO(raw)).convert("RGB")
    array = np.array(image)

    result = get_ocr().predict(input=array)
    res = result[0]
    data = res.json["res"] if hasattr(res, "json") else dict(res)

    texts = list(data.get("rec_texts") or [])
    scores = [float(s) for s in (data.get("rec_scores") or [0.0] * len(texts))]
    polys = data.get("rec_polys")
    if polys is None:
        polys = data.get("rec_boxes") or []

    lines = []
    for i, text in enumerate(texts):
        box = polys[i] if i < len(polys) else []
        lines.append({
            "text": text,
            "score": scores[i] if i < len(scores) else 0.0,
            "box": box_to_quad(box) if len(box) else [],
        })

    # 阅读顺序：自上而下、同行从左到右
    def sort_key(item):
        box = item["box"]
        if not box:
            return (float("inf"), float("inf"))
        min_y = min(p[1] for p in box)
        min_x = min(p[0] for p in box)
        return (min_y, min_x)

    lines.sort(key=sort_key)
    return {"width": array.shape[1], "height": array.shape[0], "lines": lines}


def main():
    global _ARGS
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8113)
    parser.add_argument("--lang", default="ch")
    parser.add_argument("--preload", action="store_true", help="启动时立即加载模型")
    _ARGS = parser.parse_args()

    cache = os.environ.get("PADDLE_PDX_CACHE_HOME", "")
    print(f"[paddle-classic] lang={_ARGS.lang} cache={cache or '(default)'}", flush=True)

    if _ARGS.preload:
        print("[paddle-classic] 预加载模型…", flush=True)
        get_ocr()
        print("[paddle-classic] 模型就绪", flush=True)

    print(f"[paddle-classic] listening on http://{_ARGS.host}:{_ARGS.port}", flush=True)
    uvicorn.run(app, host=_ARGS.host, port=_ARGS.port, log_level="warning")


if __name__ == "__main__":
    sys.exit(main())
