import SwiftUI
import OCRGUICore

/// 应用内"添加模型"：填 HF repo → 应用调用仓库安装脚本下载模型/复用 venv/写引擎配置
struct AddModelSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var backend: ModelInstallRequest.Backend = .mlx
    @State private var repo = ModelInstallRequest.Backend.mlx.sampleRepo
    @State private var displayName = ""
    @State private var port = ""
    @State private var promptPreset = PromptPreset.markdownLaTeX
    @State private var prompt = PromptPreset.markdownLaTeX.text
    @State private var fallbackPrompt = ""
    @State private var pipMirror = "https://pypi.tuna.tsinghua.edu.cn/simple"
    @State private var hfMirror = "https://hf-mirror.com"
    @State private var projectDir = ""
    @State private var advancedVisible = false

    /// 常用提示词预设（装好后仍可在引擎配置里改）
    enum PromptPreset: String, CaseIterable, Identifiable {
        case markdownLaTeX = "Markdown + LaTeX（推荐，文档/书籍）"
        case plainText = "纯文本提取（最快）"
        case custom = "自定义"

        var id: String { rawValue }

        var text: String {
            switch self {
            case .markdownLaTeX:
                return "把图片中的内容完整转写为 Markdown。所有数学公式用 LaTeX 表示（行内用 $...$），不要遗漏任何文字，不要总结。"
            case .plainText:
                return "Task: Text Extraction."
            case .custom:
                return ""
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isInstallingModel {
                installingView
            } else {
                formView
            }
        }
        .frame(width: 620, height: 560)
        .onAppear {
            if projectDir.isEmpty { projectDir = model.projectDirectory }
            if port.isEmpty { port = String(suggestPort()) }
        }
    }

    // MARK: - 表单

    private var formView: some View {
        ScrollView {
            Form {
                Section("模型来源") {
                    Picker("后端", selection: $backend) {
                        ForEach(ModelInstallRequest.Backend.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .onChange(of: backend) { _, new in
                        repo = new.sampleRepo
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("HuggingFace 仓库", text: $repo)
                        Text("如 \(backend.sampleRepo)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    TextField("显示名（留空用模型名）", text: $displayName)
                    TextField("端口", text: $port)
                        .onSubmit { port = String(suggestPort(from: port)) }
                }

                Section("提示词") {
                    Picker("预设", selection: $promptPreset) {
                        ForEach(PromptPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .onChange(of: promptPreset) { _, new in
                        if new != .custom {
                            prompt = new.text
                            fallbackPrompt = new == .plainText ? "" : fallbackPrompt
                        }
                    }
                    TextField("识别提示词", text: $prompt, axis: .vertical)
                        .lineLimit(2...)
                    if backend == .transformersVLM {
                        TextField("兜底提示词（可选，输出退化时重试）", text: $fallbackPrompt)
                    }
                    Text("结果可导出 txt / md / json / csv / tex")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Section {
                    Toggle("高级选项", isOn: $advancedVisible)
                    if advancedVisible {
                        TextField("pip 镜像（空=直连）", text: $pipMirror)
                        TextField("HuggingFace 镜像（空=直连）", text: $hfMirror)
                        HStack {
                            TextField("OCR GUI 项目目录（含 scripts/）", text: $projectDir)
                            Button("选择…") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.message = "选择 ocrGUI 仓库根目录（包含 scripts/）"
                                if panel.runModal() == .OK, let url = panel.url {
                                    projectDir = url.path
                                }
                            }
                        }
                        Text("下载量参考：MLX 后端首次约 700MB（venv）+ 模型大小；transformers 后端首次约 3GB（torch）。已装过的部分自动跳过。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let done = model.installDoneMessage {
                    Text(done).foregroundStyle(.green)
                }
                if let error = model.installError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .padding()
            .frame(maxWidth: 540)
            .environment(\.defaultMinListRowHeight, 10)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("下载并添加") { install() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(repo.trimmingCharacters(in: .whitespaces).isEmpty
                              || projectDir.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - 安装中视图

    private var installingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("正在安装 \(displayName.isEmpty ? repo : displayName)…")
            Text("下载模型可能需要几分钟到几十分钟，可随时取消；已存在的 venv/模型自动跳过")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(model.installLog.isEmpty ? "（等待输出…）" : model.installLog)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .background(.quaternary.opacity(0.3))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            Button("取消安装", role: .destructive) {
                // ModelInstaller 的取消依赖 Task 取消；此处直接终止脚本进程
                Task { await model.cancelInstall() }
            }
        }
        .padding(16)
    }

    private func install() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let engineID = ModelInstaller.defaultEngineID(forRepo: repo)
        let request = ModelInstallRequest(
            backend: backend,
            repo: repo.trimmingCharacters(in: .whitespaces),
            engineID: engineID,
            displayName: name.isEmpty ? engineID : name,
            port: Int(port) ?? 8114,
            prompt: prompt,
            fallbackPrompt: fallbackPrompt.isEmpty ? nil : fallbackPrompt,
            projectDirectory: projectDir.trimmingCharacters(in: .whitespaces),
            pipMirror: pipMirror.isEmpty ? nil : pipMirror,
            hfMirror: hfMirror.isEmpty ? nil : hfMirror)
        model.installModel(request)
    }

    /// 建议 8116+ 起的端口（简单递增避免常用端口冲突）
    private func suggestPort(from current: String? = nil) -> Int {
        if let current, let value = Int(current), (8112...8199).contains(value) {
            return value
        }
        return 8116
    }
}
