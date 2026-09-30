#!/usr/bin/env python3
"""通用 transformers VLM → OpenAI Chat Completions 兼容服务（Apple Silicon 优先 MPS）。

用途：把任意 HuggingFace image-text-to-text 模型（如 Xiaomi-OCR-0）包装成
与 mlx_vlm.server 相同的 /v1/chat/completions 协议，供 OCR GUI 的
openai-http 引擎接入。

协议：
  GET  /v1/models                -> {"data": [{"id": "<model>"}]}
  GET  /health                   -> {"status": "ok"}
  POST /v1/chat/completions      标准 OpenAI 请求；图片以 data URL 放在
                                  content 段（{"type":"input_image","image_url":"data:image/png;base64,…"}
                                  或 {"type":"image_url","image_url":{"url":"data:…"}}），
                                  文本段取全部 {"type":"text"} 与纯字符串 content。

依赖：torch transformers pillow fastapi uvicorn
运行：python vlm_server.py --model /path/to/model --host 127.0.0.1 --port 8114
"""
import argparse
import base64
import io
import re
import sys

import torch
from PIL import Image
from fastapi import FastAPI
from pydantic import BaseModel
from typing import Any, List, Optional
import uvicorn

app = FastAPI(title="vlm-ocr-server")

_ARGS = None
_PROCESSOR = None
_MODEL = None
_DEVICE = "cpu"


def load_model():
    global _PROCESSOR, _MODEL, _DEVICE
    from transformers import AutoProcessor, AutoModelForImageTextToText

    if torch.backends.mps.is_available():
        _DEVICE = "mps"
        dtype = torch.float16
    elif torch.cuda.is_available():
        _DEVICE = "cuda"
        dtype = torch.bfloat16
    else:
        _DEVICE = "cpu"
        dtype = torch.float32

    print(f"[vlm-server] loading {_ARGS.model} on {_DEVICE} ({dtype}) …", flush=True)
    _PROCESSOR = AutoProcessor.from_pretrained(
        _ARGS.model, trust_remote_code=_ARGS.trust_remote_code)
    _MODEL = AutoModelForImageTextToText.from_pretrained(
        _ARGS.model,
        dtype=dtype,
        trust_remote_code=_ARGS.trust_remote_code,
    )
    _MODEL = _MODEL.to(_DEVICE)
    _MODEL.eval()
    print("[vlm-server] model ready", flush=True)


DATA_URL_RE = re.compile(r"^data:image/(png|jpeg|jpg|webp);base64,(.*)$", re.DOTALL)


def image_from_data_url(url: str) -> Image.Image:
    m = DATA_URL_RE.match(url.strip())
    if not m:
        raise ValueError("仅支持 data:image/*;base64 数据 URL")
    raw = base64.b64decode(m.group(2))
    return Image.open(io.BytesIO(raw)).convert("RGB")


class ChatMessage(BaseModel):
    role: str
    content: Any


class ChatRequest(BaseModel):
    model: Optional[str] = None
    messages: List[ChatMessage]
    max_tokens: Optional[int] = 4096
    temperature: Optional[float] = 0.0


@app.get("/health")
def health():
    return {"status": "ok", "model": _ARGS.model, "device": _DEVICE}


@app.get("/v1/models")
def models():
    return {"data": [{"id": _ARGS.model}]}


def extract_content(message: ChatMessage):
    """返回 (images: [PIL.Image], text: str)"""
    images, texts = [], []
    content = message.content
    if isinstance(content, str):
        texts.append(content)
        return images, texts
    if isinstance(content, list):
        for part in content:
            if not isinstance(part, dict):
                continue
            ptype = part.get("type")
            if ptype == "input_image":
                url = part.get("image_url")
                if isinstance(url, dict):
                    url = url.get("url", "")
                images.append(image_from_data_url(str(url)))
            elif ptype == "image_url":
                url = part.get("image_url")
                if isinstance(url, dict):
                    url = url.get("url", "")
                images.append(image_from_data_url(str(url)))
            elif ptype == "image":
                src = part.get("image")
                if isinstance(src, str) and src.startswith("data:"):
                    images.append(image_from_data_url(src))
            elif ptype == "text":
                texts.append(str(part.get("text", "")))
    return images, texts


@app.post("/v1/chat/completions")
def chat_completions(req: ChatRequest):
    images, prompt_parts = [], []
    for message in req.messages:
        if message.role != "user":
            continue
        imgs, texts = extract_content(message)
        images.extend(imgs)
        prompt_parts.extend(t for t in texts if t)
    if not prompt_parts:
        prompt_parts = ["Text Recognition:"]

    content = [{"type": "image", "image": img} for img in images]
    content.append({"type": "text", "text": " ".join(prompt_parts)})
    chat_messages = [{"role": "user", "content": content}]

    inputs = _PROCESSOR.apply_chat_template(
        chat_messages,
        add_generation_prompt=True,
        tokenize=True,
        return_dict=True,
        return_tensors="pt",
    )
    inputs = {k: (v.to(_DEVICE) if hasattr(v, "to") else v) for k, v in inputs.items()}
    if "dtype" in getattr(_PROCESSOR, "model_input_names", []) or "pixel_values" in inputs:
        if "pixel_values" in inputs and inputs["pixel_values"].dtype in (torch.uint8, torch.float64):
            inputs["pixel_values"] = inputs["pixel_values"].to(torch.float32 if _DEVICE == "cpu" else torch.float16)

    max_new = min(int(req.max_tokens or 4096), _ARGS.max_new_tokens)
    with torch.no_grad():
        output_ids = _MODEL.generate(
            **inputs,
            max_new_tokens=max_new,
            do_sample=float(req.temperature or 0.0) > 0,
            temperature=max(float(req.temperature or 0.0), 1e-5),
        )
    generated = output_ids[:, inputs["input_ids"].shape[1]:]
    text = _PROCESSOR.batch_decode(generated, skip_special_tokens=True)[0]

    return {
        "id": "vlm-ocr",
        "object": "chat.completion",
        "model": req.model or _ARGS.model,
        "choices": [{"index": 0, "message": {"role": "assistant", "content": text},
                     "finish_reason": "stop"}],
    }


def main():
    global _ARGS
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="模型目录或 HF repo id")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8114)
    parser.add_argument("--max-new-tokens", type=int, default=14000)
    parser.add_argument("--trust-remote-code", action="store_true")
    _ARGS = parser.parse_args()

    load_model()
    print(f"[vlm-server] listening on http://{_ARGS.host}:{_ARGS.port}", flush=True)
    uvicorn.run(app, host=_ARGS.host, port=_ARGS.port, log_level="warning")


if __name__ == "__main__":
    sys.exit(main())
