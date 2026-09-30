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

引擎配置是 JSON 文件，位于 `~/Library/Application Support/OCRGUI/Engines/<id>.json`。首次启动会自动生成 4 个：`vision`（启用）+ `paddle-classic` / `paddle-vl` / `xiaomi-ocr-0`（模板，禁用）。

### 方式一：运行 setup 脚本（推荐）

| 脚本 | 引擎 | 下载量 | 说明 |
|---|---|---|---|
| `scripts/setup_paddle_classic.sh` | Paddle 经典 PP-OCRv6（det+rec） | ~1.3GB | 行级坐标框+置信度，中文准确度好 |
| `scripts/setup_paddle_vl.sh` | PaddleOCR-VL 1.6（MLX 4bit） | ~1.4GB | 整页 Markdown 版面还原（公式/表格），Apple GPU 加速 |
| `scripts/setup_xiaomi.sh` | Xiaomi-OCR-0（实验性） | ~4-5GB | 小米 0.8B VLM（2026-09 发布），torch+transformers |
| `scripts/setup_all.sh` | 交互式选择 | — | 上面三者的菜单入口 |

脚本做三件事：在 `runtime/` 建独立 venv → 在 `models/` 下载模型 → 把**真实路径**写入引擎配置并启用。之后打开 App 设置（⌘,）点"启动"即可，或识别时自动拉起。

`runtime/`、`models/` 均在 .gitignore 中，不进版本库；共享项目 = 共享 git 仓库，对方 clone 后重跑 setup 脚本即可复现。

### 方式二：设置界面手动配置

App 设置 → 编辑/新增引擎，填写 Base URL、模型、提示词、启动命令等（字段说明见 `docs/引擎配置规范.md`）。

### 方式三：接入已在运行的外部服务

如果本机已有 OpenAI 兼容的 OCR 服务（例如 webUI 项目已部署的 `http://127.0.0.1:8111/v1`），新建引擎只填 `base_url`、`model`、`prompt`，不填 launch 即可直接连接——参见 `docs/engines-examples/paddle-vl-attach-8111.json`。

### 导入其他模型

任何 HuggingFace transformers 的 image-text-to-text 模型都能接入：

```zsh
scripts/fetch_model.sh <HF repo>              # 下载到 models/<名字>
# 然后设置里新增引擎：
#   类型 openai-http
#   启动命令 runtime/xiaomi-env/bin/python scripts/vlm_server.py --model <模型绝对路径> --port 8115
#   健康检查 http://127.0.0.1:8115/health
```

## 数据与隐私

- 识别全程本地：唯一网络连接是 `127.0.0.1` 本地推理服务
- 历史记录（含缩略图）保存在 `~/Library/Application Support/OCRGUI/History/`，可随时删除
- 模型/依赖下载仅发生在你显式运行 setup/fetch 脚本时

## 项目结构

```
Sources/OCRGUICore/     核心逻辑（可测试）：引擎协议/适配器、批处理、存储、导出
Sources/OCRGUI/         SwiftUI 界面
Tests/OCRGUITests/      52 个单元测试（Swift Testing）
scripts/                setup/make-app/smoke 脚本 + 两个 Python 推理服务
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
