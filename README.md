# OCR GUI — macOS 本地通用 OCR 桌面应用

原生 SwiftUI 应用，离线优先、数据不出本机。支持多种本地 OCR 引擎插拔（内置 Vision 零配置可用，可接入 Paddle 经典 / PaddleOCR-VL / Xiaomi-OCR-0 等），支持图片、PDF、文件夹、剪贴板、截图输入，批量识别带进度与取消，结果可编辑、复制、导出，历史记录持久保存。

## 特性

- **零配置内置引擎**：系统 Vision 框架（中英文、行级坐标框+置信度、完全离线）
- **可插拔引擎**：引擎 = 一个 JSON 配置 + 内置适配器（OpenAI 兼容 HTTP / JSON HTTP），新增引擎不改核心 UI
- **引擎托管**：App 自动拉起/停止本地推理服务，冷启动等待 + 状态灯
- **多输入**：图片多选、文件夹递归、拖放、剪贴板、交互截图（选区）
- **批量管线**：队列、页级进度、随时取消、单文件失败不影响其余
- **PDF**：逐页渲染（DPI 可调 72–600，默认 150），多页分别识别与预览
- **结果处理**：编辑保存、复制、导出 txt / md / json / csv（与 webUI 导出格式兼容）
- **历史记录**：JSON + 缩略图落盘，重启仍在，可搜索、可删除

## 环境要求

- macOS 14+（Apple Silicon 或 Intel）
- Xcode 15+（含 Swift 工具链；本仓库用 Xcode 27 / Swift 6.4 验证）
- 可选：联网（仅首次下载 Vision 语言资源、以及运行 setup 脚本下载第三方引擎模型时）

## 快速开始

```zsh
git clone <本仓库> && cd ocrGUI

# 1. 构建 & 测试
swift build
swift test          # 52 个单元测试应全绿

# 2. 打包 .app（产出 dist/OCR GUI.app）
zsh scripts/make-app.sh
open "dist/OCR GUI.app"
```

也可以直接 `swift run OCRGUI` 运行（开发模式）。

首次启动即可用内置 Vision 引擎识别中英文图片——无需任何配置。

> 提示：Vision 的中文语言资源可能在首次识别时联网下载一次，之后完全离线。若首次识别结果为空且当时断网，联网重试一次即可。

## 引擎配置

引擎与具体模型解耦：**GUI 只认三种通用适配器**（builtin-vision / openai-http / json-http），装什么模型由你决定。配置是 JSON 文件，位于 `~/Library/Application Support/OCRGUI/Engines/<id>.json`；首次启动自动生成 `vision`（启用）+ `custom-vlm` / `paddle-classic`（中性模板，禁用）。

### 方式零：应用内安装（推荐，无需终端）

设置（⌘,）→ **“添加模型…”** → 选后端（MLX / transformers VLM）→ 粘贴 HF 仓库地址 → “下载并添加”。应用会自动调用安装脚本完成下载（实时日志、可取消、国内镜像已预填），完成后引擎直接出现在列表里。首次使用需选一次 ocrGUI 项目目录（含 scripts/ 的仓库根目录，之后记住）。

### 方式一：通用安装器（任意模型，终端）

```zsh
# 任意 HuggingFace transformers VLM 模型（torch 只装一次，多引擎共享 venv）
scripts/setup_vlm_engine.sh --repo SeerRay-Lab/Xiaomi-OCR-0 --port 8114 \
    --fallback-prompt "Task: Text Extraction."
scripts/setup_vlm_engine.sh --repo Qwen/Qwen3.5-VL-2B-Instruct --port 8115

# 任意 mlx-community 模型（Apple GPU 加速）
scripts/setup_mlx_engine.sh --repo mlx-community/PaddleOCR-VL-1.6-4bit --port 8112

# 项目自带的 Paddle 经典引擎（det+rec，行级坐标框+置信度）
scripts/setup_paddle_classic.sh

# 交互式菜单
scripts/setup_all.sh
```

安装器做三件事：建/复用 `runtime/` 下 venv → 下载模型到 `models/` → 把真实路径写入引擎配置并启用。之后在 App 设置（⌘,）点"启动"，或识别时自动拉起。

### 方式二：示例配方

`scripts/recipes/` 下是几行的小配方（给通用安装器传参），可直接跑也可当模板写自己的：

```zsh
scripts/recipes/xiaomi-ocr-0.sh    # Xiaomi-OCR-0（0.8B VLM，2026-09）
scripts/recipes/paddle-vl.sh       # PaddleOCR-VL 1.6（MLX 4bit）
scripts/recipes/glm-ocr.sh         # GLM-OCR（智谱 0.9B，MLX 4bit）
```

### 方式三：设置界面手动配置 / 外接已有服务

设置 → 编辑/新增引擎（字段说明见 `docs/引擎配置规范.md`）。连接已在运行的 OpenAI 兼容服务（如 webUI 部署的 `http://127.0.0.1:8111/v1`）只需填 `base_url`、`model`、`prompt`，不填 launch——示例：`docs/engines-examples/paddle-vl-attach-8111.json`。

### 提示词建议（VLM 类引擎，均可在设置里改）

| 场景 | prompt | fallback_prompt |
|---|---|---|
| Markdown+LaTeX 转写（书籍/文档） | 把图片中的内容完整转写为 Markdown。所有数学公式用 LaTeX 表示… | `Task: Text Extraction.` |
| 快速纯文本 | `Task: Text Extraction.` | —（可不填） |
| PaddleOCR-VL | `Text Recognition:` | — |

主提示词输出退化（图形页重复循环等）时会自动用 fallback_prompt 重试，并在导出时标注"纯文本兜底"。

## 数据与隐私

- 识别全程本地：唯一网络连接是 `127.0.0.1` 本地推理服务
- 历史记录（含缩略图）保存在 `~/Library/Application Support/OCRGUI/History/`，可随时删除
- 模型/依赖下载仅发生在你显式运行 setup/fetch 脚本时

## 项目结构

```
Sources/OCRGUICore/     核心逻辑（可测试）：引擎协议/适配器、批处理、存储、导出
Sources/OCRGUI/         SwiftUI 界面
Tests/OCRGUITests/      52 个单元测试（Swift Testing）
scripts/                通用安装器 + recipes 配方 + Python 推理服务（通用 vlm_server / paddle_classic）
docs/                   引擎配置规范、验收说明
runtime/ models/        venv 与模型（gitignore）
```

## 常见问题（FAQ）

**Q: Vision 首次识别很慢/结果为空？**
中文语言资源可能首次使用才下载。联网状态下先识别一次；之后完全离线。Vision 中文准确度中等，追求精度请配置 Paddle 或 Xiaomi 引擎。

**Q: 截图没反应/黑屏？**
`screencapture` 需要屏幕录制权限：系统设置 → 隐私与安全性 → 屏幕录制 → 允许 OCR GUI（或你运行终端的 App）。首次使用系统会弹窗。

**Q: 外部引擎启动失败？**
设置 → 引擎行会显示失败原因；底部"服务日志"有服务进程输出。常见：模型路径不对、端口被占用、venv 未建好（重跑 setup 脚本）。

**Q: MLX/Paddle 服务冷启动要多久？**
PaddleOCR-VL（MLX）约 40 秒；Paddle 经典预加载约 10-30 秒；Xiaomi 首次加载约 20-40 秒。状态灯显示"启动中…"。

**Q: 如何彻底清理？**
删除 `~/Library/Application Support/OCRGUI/`（配置+历史）、项目下 `runtime/`、`models/`。

**Q: setup 脚本下载太慢？**
国内网络建议先设置镜像再运行：
```zsh
export PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"   # pip 清华镜像
export HF_ENDPOINT="https://hf-mirror.com"                        # HuggingFace 镜像（模型下载）
zsh scripts/setup_xiaomi.sh
```

## 开发

```zsh
swift build && swift test     # TDD，52 测试
zsh scripts/smoke_paddle_classic.sh   # 经典引擎服务冒烟（需先 setup 或传入可用 python）
zsh scripts/smoke_vlm.sh 8114         # VLM 服务冒烟（服务启动后）
```

许可证：MIT（见 LICENSE）。
