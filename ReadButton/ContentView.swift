import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ReadButtonModel
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                switch model.step {
                case .address: addressView
                case .pin: pinView
                case .ready: remoteView
                }
            }
            .overlay { if model.isWorking { ProgressView() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.syncCurrentPage() }
            }
        }
    }

    private var addressView: some View {
        Form {
            TextField("DPT 地址", text: $model.host)
                .textInputAutocapitalization(.never)
            Button("测试连接") { Task { await model.testConnection() } }
            Button("开始配对") { Task { await model.beginPairing() } }
            status
        }
        .navigationTitle("ReadButton")
    }

    private var pinView: some View {
        Form {
            Text("输入 DPT 屏幕上的 PIN")
                .font(.caption)
            TextField("PIN", text: $model.pin)
            Button("完成配对") { Task { await model.finishPairing() } }
                .disabled(model.pin.isEmpty)
            status
        }
        .navigationTitle("设备配对")
    }

    private var remoteView: some View {
        VStack(spacing: 10) {
            if let document = model.selectedDocument {
                Text(document.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 44)
                    .padding(.top, 10)
                NavigationLink {
                    PageJumpView(model: model)
                } label: {
                    Text("第 \(document.currentPage) / \(document.totalPages) 页")
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("跳转到页码")
            } else {
                Text("请选择正在阅读的文档")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 82)
            }

            HStack(spacing: 10) {
                pageButton("chevron.left", label: "上一页", disabled: model.selectedDocument?.currentPage == 1) {
                    await model.changePage(by: -1)
                }
                pageButton("chevron.right", label: "下一页", disabled: model.selectedDocument.map { $0.currentPage >= $0.totalPages } ?? true) {
                    await model.changePage(by: 1)
                }
            }

            status
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    DocumentPicker(model: model)
                } label: {
                    Image(systemName: "book")
                }
                .accessibilityLabel("选择文档")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("设置", systemImage: "gear") { showingSettings = true }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
        }
        .task { await model.loadOnStart() }
    }

    private func pageButton(
        _ image: String,
        label: String,
        disabled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: image)
                .font(.title.bold())
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(label)
        .disabled(disabled || model.isWorking)
    }

    @ViewBuilder private var status: some View {
        if !model.message.isEmpty {
            Text(model.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: ReadButtonModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("DPT 地址", text: $model.host)
                    .textInputAutocapitalization(.never)
                Button("测试连接") { Task { await model.testConnection() } }
                NavigationLink("选择文档") {
                    DocumentPicker(model: model)
                }
                Toggle("按最近阅读排序", isOn: Binding(
                    get: { model.sortByRecent },
                    set: { model.setSortByRecent($0) }
                ))
                Button("清除配对", role: .destructive) {
                    model.reset()
                    dismiss()
                }
                if !model.message.isEmpty {
                    Text(model.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct DocumentPicker: View {
    @ObservedObject var model: ReadButtonModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(model.documents) { document in
            Button {
                Task {
                    if await model.select(document) {
                        dismiss()
                    }
                }
            } label: {
                VStack(alignment: .leading) {
                    Text(document.name).lineLimit(2)
                    Text("\(document.currentPage) / \(document.totalPages)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.isWorking)
        }
        .navigationTitle("选择文档")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新", systemImage: "arrow.clockwise") {
                    Task { await model.refreshDocuments() }
                }
                .disabled(model.isWorking)
            }
        }
        .task {
            await model.refreshDocuments()
        }
    }
}

private struct PageJumpView: View {
    @ObservedObject var model: ReadButtonModel
    @Environment(\.dismiss) private var dismiss
    @State private var pageText = ""

    var body: some View {
        Form {
            if let document = model.selectedDocument {
                Text("当前：\(document.currentPage) / \(document.totalPages)")
                    .font(.caption)
                TextField("页码", text: $pageText)
                Button("打开此页") {
                    guard let page = Int(pageText) else { return }
                    Task {
                        await model.jumpToPage(page)
                        dismiss()
                    }
                }
                .disabled(Int(pageText) == nil || model.isWorking)
            } else {
                Text("请先选择文档")
            }
        }
        .navigationTitle("跳转页码")
        .onAppear {
            if let page = model.selectedDocument?.currentPage { pageText = String(page) }
        }
    }
}
