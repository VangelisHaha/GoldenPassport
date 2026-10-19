import AppKit
import GoldenPassportCore

enum ScreenQRCodeCapture {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case captureFailed
        case noQRCode
        case multipleQRCodes

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return String(localized: "请在系统设置 → 隐私与安全性 → 屏幕录制中允许 GoldenPassport，然后重新启动应用。")
            case .captureFailed:
                return String(localized: "截图失败，请重试。")
            case .noQRCode:
                return String(localized: "截图中没有找到验证器二维码，请框选完整的二维码后重试。")
            case .multipleQRCodes:
                return String(localized: "截图中找到多个验证器二维码，请只框选要添加的那一个。")
            }
        }
    }

    /// nil 表示用户按 Esc 取消。截图和识别在后台进行，结束后恢复添加窗口。
    static func capture(completion: @escaping (Result<String?, Error>) -> Void) {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            completion(.failure(CaptureError.permissionDenied))
            return
        }
        let window = NSApp.keyWindow
        NSApp.hide(nil)
        // 让添加窗口先从屏幕移除，避免遮住网页中的二维码。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try captureURL() }
                DispatchQueue.main.async {
                    NSApp.unhide(nil)
                    activateApp()
                    window?.makeKeyAndOrderFront(nil)
                    completion(result)
                }
            }
        }
    }

    private static func captureURL() throws -> String? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoldenPassport-capture-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("capture.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", "-t", "png", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard FileManager.default.fileExists(atPath: file.path) else {
            guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permissionDenied }
            // 系统截图工具在 Esc 取消后可能返回 0 或 1，均不会生成文件。
            if process.terminationStatus == 0 || process.terminationStatus == 1 { return nil }
            throw CaptureError.captureFailed
        }
        guard process.terminationStatus == 0 else { throw CaptureError.captureFailed }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let urls = QRCodeReader.otpAuthURLs(in: file)
        guard let found = urls.first else { throw CaptureError.noQRCode }
        guard urls.count == 1 else { throw CaptureError.multipleQRCodes }
        return found
    }
}
