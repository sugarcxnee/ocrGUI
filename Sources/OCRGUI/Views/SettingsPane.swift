import SwiftUI
import OCRGUICore

/// 设置窗口：引擎管理（启用/启停/编辑/新增/删除）、配置目录、服务日志
struct SettingsPane: View {
    @Environment(AppModel.self) private var model
    @State private var editingConfig: EngineConfig?
    @State private var creatingNew = false
    @State private var addingModel = false
    @State private var pendingDeleteID: String?
    @State private var restoringSnapshot: String?

    var body: some View {
        VStack(spacing: 0) {
            engineList
            Divider()
            bottomBar
            if !model.engineStore.loadErrors.isEmpty {
                Divider()
                Text("存在无法解析的配置文件：\(model.engineStore.loadErrors.joined(separator: "；"))")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            Divider()
            engineLogView
        }
        .frame(width: 640, height: 560)
        .sheet(isPresented: $creatingNew) {
            EngineEditView(config: EngineConfig(
                id: "my-engine-\(Int(Date().timeIntervalSince1970) % 100000)",
                name: "新引擎",
                kind: .openaiHTTP, enabled: true,
                baseURL: "http://127.0.0.1:8115/v1", model: nil, prompt: "Text Recognition:",
                apiKey: nil, timeout: 300,
                launch: EngineLaunch(command: "", cwd: nil, environment: [:],
                                     healthURL: "http://127.0.0.1:8115/health", readyTimeout: 180,
                                     stopCommand: nil),
                notes: nil)) { result in
                if case .saved(let saved) = result {
                    try? model.engineStore.save(saved)
                }
            }
        }
        .sheet(item: $editingConfig) { selected in
            // 用 id 从 store 取最新副本：底层列表重绘不会让 sheet 消失
            EngineEditView(config: model.engineStore.configs.first { $0.id == selected.id } ?? selected) { result in
                switch result {
                case .saved(let saved):
                    try? model.engineStore.save(saved)
                case .deleted(let id):
                    try? model.engineStore.delete(id: id)
                case .canceled:
                    break
                }
            }
        }
        .sheet(isPresented: $addingModel) {
            AddModelSheet()
        }
        .confirmationDialog("从快照恢复引擎配置",
                            isPresented: Binding(get: { restoringSnapshot != nil },
                                                 set: { if !$0 { restoringSnapshot = nil } }),
                            titleVisibility: .visible) {
            ForEach(Array(model.engineStore.availableBackups().prefix(5)), id: \.self) { name in
                Button("恢复 \(name)") {
                    try? model.engineStore.restoreBackup(name)
                    restoringSnapshot = nil
                }
            }
            Button("取消", role: .cancel) { restoringSnapshot = nil }
        } message: {
            Text("恢复会覆盖当前所有引擎配置（当前配置也会先被快照）。")
        }
    }

    private var engineList: some View {
        List {
            Section("OCR 引擎") {
                ForEach(model.engineStore.configs) { config in
                    EngineRow(config: config, health: model.engineHealths[config.id]) {
                        editingConfig = config
                    }
                }
            }
            Section("通用") {
                Stepper("PDF 渲染精度：\(Int(model.pdfDPI)) DPI", value: Binding(
                    get: { model.pdfDPI },
                    set: { model.pdfDPI = $0 }), in: 72...600, step: 18)
                    .help("越高越清晰，识别更准但更慢（默认 150）")
                HStack {
                    Button("打开历史记录目录") {
                        NSWorkspace.shared.open(model.history.directory)
                    }
                    Spacer()
                    Text("\(model.history.records.count) 条记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .task { await model.refreshEngineHealths() }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                addingModel = true
            } label: {
                Label("添加模型…", systemImage: "square.and.arrow.down")
                    .bold()
            }
            .help("从 HuggingFace 下载并安装新模型（推荐，自动完成环境与配置）")

            Button {
                creatingNew = true
            } label: {
                Label("连接外部服务…", systemImage: "network")
            }
            .help("高级：手动填写配置，连接已在运行的 OpenAI 兼容服务或自定义引擎")

            Spacer()
            Button("刷新状态") {
                Task { await model.refreshEngineHealths() }
            }
            Button("打开配置目录") {
                NSWorkspace.shared.open(model.engineStore.directory)
            }
            Menu("快照") {
                Button("立即备份") { model.engineStore.snapshotBackup() }
                Button("恢复快照…") { restoringSnapshot = "" }
            }
        }
        .padding(8)
    }

    private var engineLogView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("服务日志（最近输出）")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
            ScrollView {
                Text(model.engineLog.isEmpty ? "（暂无输出）" : model.engineLog)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(height: 120)
        }
    }
}

// MARK: - 单个引擎行

private struct EngineRow: View {
    @Environment(AppModel.self) private var model
    let config: EngineConfig
    let health: EngineHealth?
    var onEdit: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(config.name).bold()
                    Text(kindLabel)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    Text(healthText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(config.notes ?? config.baseURL ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if case .failed(let reason) = health {
                    Text(reason).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                if config.kind != .builtinVision {
                    Button("启动") {
                        Task { await model.startEngine(config) }
                    }
                    .disabled(health == .starting)
                    Button("停止") {
                        Task { await model.stopEngine(config) }
                    }
                    .disabled(health != .ready)
                }
                Button("编辑…", action: onEdit)
                if config.id != "vision" {
                    Button("删除…", role: .destructive) {
                        confirmDelete = true
                    }
                    .confirmationDialog("删除引擎 \(config.name)？",
                                        isPresented: $confirmDelete,
                                        titleVisibility: .visible) {
                        Button("删除（可从快照恢复）", role: .destructive) {
                            model.engineStore.snapshotBackup()
                            try? model.engineStore.delete(id: config.id)
                            Task { await model.refreshEngineHealths() }
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("删除前会自动创建快照，可在右下角\"快照 → 恢复快照\"找回。")
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private var healthText: String {
        switch health {
        case .ready: return "就绪"
        case .starting: return "启动中…"
        case .notRunning, .none: return "未运行"
        case .failed: return "失败"
        }
    }

    private var statusColor: Color {
        switch health {
        case .ready: return .green
        case .starting: return .orange
        case .notRunning, .none: return .gray
        case .failed: return .red
        }
    }

    private var kindLabel: String {
        switch config.kind {
        case .builtinVision: return "内置 Vision"
        case .openaiHTTP: return "OpenAI 兼容"
        case .jsonHTTP: return "JSON HTTP"
        }
    }
}
