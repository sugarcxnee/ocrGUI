# OCR GUI — macOS 本地通用 OCR 桌面应用

**当前版本：v0.2.0**（2026-10-01，见文末[版本历史](#版本历史)）

原生 SwiftUI 应用，离线优先、数据不出本机。支持多种本地 OCR 引擎插拔（内置 Vision 零配置可用，可接入 Paddle 经典 / PaddleOCR-VL / Xiaomi-OCR-0 等），支持图片、PDF、文件夹、剪贴板、截图输入，批量识别带进度与取消，结果可编辑、复制、导出，历史记录持久保存。

## 特性

- **零配置内置引擎**：系统 Vision 框架（中英文、行级坐标框+置信度、完全离线）
- **可插拔引擎**：引擎 = 一个 JSON 配置 + 内置适配器（OpenAI 兼容 HTTP / JSON HTTP），新增引擎不改核心 UI；**设置内“添加模型”粘贴 HF 仓库地址一键安装**（实时日志、可取消、国内镜像预填）
- **引擎托管**：App 自动拉起/停止本地推理服务，冷启动等待 + 状态灯；全部引擎直接可选（未配置的会标注）
- **多输入**：图片多选、文件夹递归、拖放、剪贴板、交互截图（选区）
- **批量管线**：队列、**页级进度条 + 已用时间/预计剩余**、随时取消、单文件失败不影响其余；**页级断点续跑**（取消/崩溃不丢已完成页，重跑自动跳过）
- **实时反馈**：识别中的大文件逐页实时显示识别文本；已完成文件随时点开浏览（不打断批次）
- **PDF**：逐页渲染（DPI 可调 72–600，默认 150），多页分别识别与预览；预览支持 1:1 实际像素 / 32× 缩放、大文档页码直达
- **结果处理**：编辑保存（多页记录带页界标记、切页联动定位）、复制、导出 **txt / md / json / csv / tex**（多页 Markdown 自动“装订”：去页眉页码、公式分隔符规范化、标题层级、坐标框 overlay）
- **性能**：大文档编辑用 NSTextView（数十万字符流畅）、PDF 单页异步渲染、缩略图缓存
- **历史记录**：JSON + 缩略图 + 识别用时落盘，重启仍在，可搜索、可删除
- **配置安全**：引擎配置启动自动快照（保留 5 份）、删除需确认、设置内一键恢复快照

## 环境要求

- macOS 14+（Apple Silicon 或 Intel）
- Xcode 15+（含 Swift 工具链；本仓库用 Xcode 27 / Swift 6.4 验证）
- 可选：联网（仅首次下载 Vision 语言资源、以及运行 setup 脚本下载第三方引擎模型时）

## 快速开始

```zsh
git clone <本仓库> && cd ocrGUI

# 1. 构建 & 测试
swift build
swift test          # 94 个单元测试应全绿

# 2. 打包 .app（产出 dist/OCR GUI.app）
zsh scripts/make-app.sh
open "dist/OCR GUI.app"
```

也可以直接 `swift run OCRGUI` 运行（开发模式）。

首次启动即可用内置 Vision 引擎识别中英文图片——无需任何配置。

> 提示：Vision 的中文语言资源可能在首次识别时联网下载一次，之后完全离线。若首次识别结果为空且当时断网，联网重试一次即可。

## 引擎配置

引擎与具体模型解耦：**GUI 只认三种通用适配器**（builtin-vision / openai-http / json-http），装什么模型由你决定。配置是 JSON 文件，位于 `~/Library/Application Support/OCRGUI/Engines/<id>.json`；首次启动自动生成 `vision` + `custom-vlm` / `paddle-classic`（中性模板）。**所有引擎在选择器中直接可选**，未安装环境的会标注“（未配置）”。

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
Tests/OCRGUITests/      94 个单元测试（Swift Testing，含真实渲染回归）
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
swift build && swift test     # TDD，94 测试
zsh scripts/smoke_paddle_classic.sh   # 经典引擎服务冒烟（需先 setup 或传入可用 python）
zsh scripts/smoke_vlm.sh 8114         # VLM 服务冒烟（服务启动后）
```

许可证：MIT（见 LICENSE）。

## 版本历史

### v0.2.0（2026-10-01）

- 应用内“添加模型”安装器（设置 → 添加模型：粘贴 HF 仓库即装，实时日志/可取消/镜像预填）
- 引擎中立化重构：通用安装器（`setup_vlm_engine.sh` / `setup_mlx_engine.sh`）+ `scripts/recipes/` 配方；默认模板不再预置第三方模型
- 新增引擎配方：GLM-OCR（MLX 4bit，实测 8–15s/页）、PaddleOCR-VL（MLX，5.7s/页）
- 页级断点续跑（CheckpointStore）：取消/崩溃不丢已完成页，重跑自动跳过
- 页级进度条 + 已用时间/预计剩余；批次结束计时冻结、进度条自动收起
- 识别中实时文本预览；已完成文件即时浏览（不打断批次）
- 大文档体验：NSTextView 编辑（流畅）、PDF 单页异步渲染（修整本渲染卡顿）、预览 1:1/32× 缩放、页码直达输入框
- 导出新增 .tex（ctexart）；多页 Markdown“装订”（页眉页码清理、公式分隔符规范化、标题层级）；`fallback_prompt` 退化兜底（跨引擎安全）
- 多页编辑视图分页标记 + 切页联动定位；历史记录显示识别用时
- 引擎配置快照（启动自动备份、删除确认、一键恢复）
- 引擎勾选框移除：添加即可选，未配置引擎标注
- 设置入口：主窗口工具栏齿轮按钮

### v0.1.0（2026-09-30）

MVP：Vision 内置引擎、三适配器引擎系统（OpenAI 兼容 / JSON HTTP）、进程托管、批量管线（取消/失败隔离）、PDF 逐页、四格式导出、历史持久化、三引擎真机验证（Paddle 经典 / PaddleOCR-VL@8111 / Xiaomi-OCR-0）。
