import SwiftUI
import OCRGUICore

/// 引擎编辑表单：保存（validate 通过才落盘）/ 删除
struct EngineEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var config: EngineConfig
    @State private var envText: String
    @State private var validationError: String?

    init(config: EngineConfig, onDone: @escaping (EngineConfig?) -> Void) {
        _config = State(initialValue: config)
        _envText = State(initialValue: config.launch?.environment
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "\n") ?? "")
        self.onDone = onDone
    }

    let onDone: (EngineConfig?) -> Void

    var body: some View {
        ScrollView {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $config.name)
                    if config.id != "vision" {
                        Picker("类型", selection: $config.kind) {
                            Text("OpenAI 兼容 HTTP").tag(EngineKind.openaiHTTP)
                            Text("JSON HTTP").tag(EngineKind.jsonHTTP)
                            if config.kind == .builtinVision {
                                Text("内置 Vision").tag(EngineKind.builtinVision)
                            }
                        }
                    }
                    TextField("说明（可选）", text: Binding(
                        get: { config.notes ?? "" },
                        set: { config.notes = $0.isEmpty ? nil : $0 }))
                }

                if config.kind != .builtinVision {
                    Section("服务地址") {
                        TextField("Base URL（如 http://127.0.0.1:8112/v1）", text: Binding(
                            get: { config.baseURL ?? "" },
                            set: { config.baseURL = $0.isEmpty ? nil : $0 }))
                        TextField("模型名/模型路径（可选）", text: Binding(
                            get: { config.model ?? "" },
                            set: { config.model = $0.isEmpty ? nil : $0 }))
                        TextField("提示词（可选）", text: Binding(
                            get: { config.prompt ?? "" },
                            set: { config.prompt = $0.isEmpty ? nil : $0 }))
                        TextField("兜底提示词（可选，主输出退化时用它重试）", text: Binding(
                            get: { config.fallbackPrompt ?? "" },
                            set: { config.fallbackPrompt = $0.isEmpty ? nil : $0 }))
                        TextField("API Key（可选）", text: Binding(
                            get: { config.apiKey ?? "" },
                            set: { config.apiKey = $0.isEmpty ? nil : $0 }))
                        Stepper("请求超时：\(Int(config.timeout))s", value: $config.timeout, in: 10...3600, step: 10)
                    }

                    Section("进程托管（留空表示连接已在运行的外部服务）") {
                        TextField("启动命令", text: launchRequiredBinding(\.command))
                        TextField("工作目录（可选）", text: launchOptionalBinding(\.cwd))
                        TextField("健康检查 URL", text: launchRequiredBinding(\.healthURL))
                        TextField("停止命令（可选，默认结束进程）", text: launchOptionalBinding(\.stopCommand))
                        Stepper("就绪等待：\(Int(config.launch?.readyTimeout ?? 180))s") {
                            ensureLaunch()
                            config.launch?.readyTimeout = min(600, (config.launch?.readyTimeout ?? 180) + 10)
                        } onDecrement: {
                            ensureLaunch()
                            config.launch?.readyTimeout = max(10, (config.launch?.readyTimeout ?? 180) - 10)
                        }
                        TextField("环境变量（每行 KEY=VALUE）", text: $envText, axis: .vertical)
                            .lineLimit(3...)
                    }
                }

                if let validationError {
                    Text(validationError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding()
        }
        .frame(width: 560, height: 560)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    onDone(nil)
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func launchRequiredBinding(_ keyPath: WritableKeyPath<EngineLaunch, String>) -> Binding<String> {
        Binding(
            get: { config.launch?[keyPath: keyPath] ?? "" },
            set: { newValue in
                self.ensureLaunch()
                self.config.launch?[keyPath: keyPath] = newValue
            })
    }

    private func launchOptionalBinding(_ keyPath: WritableKeyPath<EngineLaunch, String?>) -> Binding<String> {
        Binding(
            get: { config.launch?[keyPath: keyPath] ?? "" },
            set: { newValue in
                self.ensureLaunch()
                self.config.launch?[keyPath: keyPath] = newValue.isEmpty ? nil : newValue
            })
    }

    /// @State 的 wrappedValue 支持非变异赋值，普通函数即可
    private func ensureLaunch() {
        if config.launch == nil {
            config.launch = EngineLaunch(command: "", cwd: nil, environment: [:],
                                         healthURL: "", readyTimeout: 180, stopCommand: nil)
        }
    }

    private func save() {
        if var launch = config.launch {
            var env: [String: String] = [:]
            for line in envText.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                env[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1])
            }
            launch.environment = env
            // 全空 launch 视为不托管
            if launch.command.trimmingCharacters(in: .whitespaces).isEmpty
                && launch.healthURL.trimmingCharacters(in: .whitespaces).isEmpty {
                config.launch = nil
            } else {
                config.launch = launch
            }
        }
        do {
            try config.validate()
            try model.engineStore.save(config)
            onDone(config)
            dismiss()
        } catch {
            validationError = "校验失败：\(error.localizedDescription)"
        }
    }
}
