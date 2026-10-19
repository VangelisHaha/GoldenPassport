import AppKit
import CoreImage
import GoldenPassportCore
import SwiftUI
import UniformTypeIdentifiers

/// Hosts a SwiftUI view in a reusable floating window for this accessory app.
class HostedWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func makeContent(close: @escaping () -> Void) -> AnyView {
        fatalError("subclass must override")
    }

    var title: String { "" }
    var resizable: Bool { false }

    func present() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent { [weak self] in
                self?.window?.close()
            }))
            window.title = title
            window.styleMask = resizable ? [.titled, .closable, .resizable] : [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        activateApp()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the window so the next presentation starts with fresh state.
        DispatchQueue.main.async { self.window = nil }
    }
}

// MARK: - Add account

final class AddAccountWindowController: HostedWindowController {
    private let store: AccountStore
    private let onAdded: () -> Void

    init(store: AccountStore, onAdded: @escaping () -> Void) {
        self.store = store
        self.onAdded = onAdded
    }

    override var title: String { String(localized: "添加认证") }

    override func makeContent(close: @escaping () -> Void) -> AnyView {
        AnyView(AddAccountView(store: store, onAdded: { [onAdded] in
            onAdded()
            close()
        }, onCancel: close))
    }
}

struct AddAccountView: View {
    let store: AccountStore
    let onAdded: () -> Void
    let onCancel: () -> Void

    @State private var url = ""
    @State private var name = ""
    @State private var nameEdited = false
    @State private var error: String?
    @State private var captureInProgress = false
    @State private var migration: GoogleAuthMigration?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                TextField("密钥或导入链接：", text: $url, prompt: Text("粘贴密钥、otpauth:// 或迁移链接"))
                    .onChange(of: url) { newValue in
                        error = nil
                        migration = nil
                        if GoogleAuthMigration.isMigrationURL(newValue) {
                            do {
                                migration = try GoogleAuthMigration(string: newValue)
                                if !nameEdited { name = migration?.entries.first?.name ?? "" }
                            } catch {
                                self.error = error.localizedDescription
                            }
                            return
                        }
                        if !nameEdited {
                            name = (try? OTPAuthURL(string: newValue))?.suggestedName ?? ""
                        }
                    }
                if migration == nil || migration?.entries.count == 1 {
                    TextField("标识：", text: Binding(get: { name }, set: {
                    name = $0
                    nameEdited = true
                    error = nil
                    }), prompt: Text("用于在菜单中识别此账号"))
                }
            }
            if let migration {
                Text("迁移包包含 \(migration.entries.count) 个账户，同名账户会跳过。")
                    .font(.caption)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(migration.entries.indices, id: \.self) { index in
                            Text(migration.entries[index].name)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 120)
                if migration.batchSize > 1 {
                    Text("这是第 \(migration.batchIndex + 1) / \(migration.batchSize) 批，请依次导入其余迁移二维码。")
                        .font(.caption)
                }
            } else {
                Text("直接粘贴密钥时，请填写标识；默认使用 SHA1、6 位验证码、30 秒刷新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("从二维码图片识别...", action: pickQRCode)
                Button("截图识别...", action: captureQRCode)
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button(migration == nil ? String(localized: "添加") : String(localized: "导入"), action: add)
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(captureInProgress)
        }
        .padding(20)
        .frame(width: 560)
    }

    private func add() {
        do {
            if GoogleAuthMigration.isMigrationURL(url) {
                var entries = try GoogleAuthMigration(string: url).entries
                if entries.count == 1 {
                    let editedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !editedName.isEmpty else { throw AccountStoreError.emptyName }
                    entries[0].name = editedName
                }
                let added = try store.importAccounts(entries)
                let skipped = entries.count - added
                onAdded()
                showAlert(String(localized: "成功导入 \(added) 条记录"),
                          informative: skipped > 0 ? String(localized: "\(skipped) 条因标识已存在而跳过。") : nil)
                return
            }
            let normalizedURL = try OTPAuthInput.normalizedURL(url, name: name)
            try store.add(name: name, url: normalizedURL)
            onAdded()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pickQRCode() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let fileURL = panel.url else { return }
        guard let found = QRCodeReader.otpAuthURLs(in: fileURL).first else {
            error = String(localized: "图片中没有找到验证器或迁移二维码。")
            return
        }
        url = found
    }

    private func captureQRCode() {
        guard !captureInProgress else { return }
        error = nil
        captureInProgress = true
        ScreenQRCodeCapture.capture { result in
            captureInProgress = false
            switch result {
            case .success(let found):
                if let found { url = found }
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }
}

// MARK: - HTTP port

final class PortConfigWindowController: HostedWindowController {
    private let currentPort: () -> Int
    private let onSave: (Int) -> Void

    init(currentPort: @escaping () -> Int, onSave: @escaping (Int) -> Void) {
        self.currentPort = currentPort
        self.onSave = onSave
    }

    override var title: String { String(localized: "HTTP 服务端口") }

    override func makeContent(close: @escaping () -> Void) -> AnyView {
        AnyView(PortConfigView(port: String(currentPort()), onSave: { [onSave] port in
            onSave(port)
            close()
        }, onCancel: close))
    }
}

struct PortConfigView: View {
    @State var port: String
    let onSave: (Int) -> Void
    let onCancel: () -> Void
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("端口：", text: $port)
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("确定") {
                    guard let value = Int(port.trimmingCharacters(in: .whitespaces)), (1...65535).contains(value) else {
                        error = String(localized: "端口号必须是 1–65535 之间的整数。")
                        return
                    }
                    onSave(value)
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
