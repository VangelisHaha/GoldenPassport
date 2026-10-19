import Foundation
import GoldenPassportCore
import CoreImage

// Acceptance checks for the CLT/Swift 5.8 build, using synthetic accounts only.
@main
enum NativeSmoke {
    static func main() async throws {
        try MigrationFixtures.verify()
        let vectors: [(Double, String, String, String)] = [
            (59, "94287082", "46119246", "90693936"),
            (1111111109, "07081804", "68084774", "25091201"),
            (1111111111, "14050471", "67062674", "99943326"),
            (1234567890, "89005924", "91819424", "93441116"),
            (2000000000, "69279037", "90698825", "38618901"),
            (20000000000, "65353130", "77737706", "47863826"),
        ]
        for (time, sha1, sha256, sha512) in vectors {
            let date = Date(timeIntervalSince1970: time)
            precondition(TOTP(secret: Data("12345678901234567890".utf8), algorithm: .sha1, digits: 8).code(at: date) == sha1)
            precondition(TOTP(secret: Data("12345678901234567890123456789012".utf8), algorithm: .sha256, digits: 8).code(at: date) == sha256)
            precondition(TOTP(secret: Data("1234567890123456789012345678901234567890123456789012345678901234".utf8), algorithm: .sha512, digits: 8).code(at: date) == sha512)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gp-smoke-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = "otpauth://totp/Test?secret=MZXW6YTBOI"
        try verifyQRCodes(in: dir, url: url)
        try LegacyData.writeDictionary(["test": url], to: dir.appendingPathComponent(LegacyData.secretsFileName))
        let environment = AppEnvironment(dataDirectory: dir, seedDirectory: nil,
            defaults: .init(httpPort: 17304, hotkeysEnabled: true))
        let migration = try MigrationCheck.run(environment: environment)
        precondition(migration.isConsistent && migration.accountCount == 1)
        let store = AccountStore(directory: dir)
        let label = "测试 / 账户?#%"
        let normalized = try OTPAuthInput.normalizedURL("  mzxw 6ytb-oi\n", name: label)
        let parsed = try OTPAuthURL(string: normalized)
        precondition(parsed.label == label)
        precondition(parsed.totp == TOTP(secret: Data("foobar".utf8)))
        let preservedURL = try OTPAuthInput.normalizedURL(url, name: "test")
        precondition(preservedURL == url)
        let custom = "otpauth://totp/Test?secret=MZXW6YTBOI&algorithm=SHA512&digits=8&period=60"
        let preservedCustom = try OTPAuthInput.normalizedURL(custom, name: "test")
        precondition(preservedCustom == custom)
        for invalid in ["", "0189", "A", "not-a-secret!"] {
            do {
                _ = try OTPAuthInput.normalizedURL(invalid, name: "test")
                fatalError("Invalid secret accepted")
            } catch OTPAuthURLError.invalidSecret { }
        }
        do {
            _ = try OTPAuthInput.normalizedURL("MZXW6YTBOI", name: " ")
            fatalError("Empty name accepted")
        } catch AccountStoreError.emptyName { }
        let bare = try store.add(name: label, url: normalized)
        let date = Date(timeIntervalSince1970: 1111111109)
        precondition(store.code(named: label, at: date)?.displayCode == TOTP(secret: Data("foobar".utf8)).code(at: date))
        precondition(AccountStore(directory: dir).accounts.last?.url == normalized)
        try store.remove(id: bare.id)
        try store.rename(id: store.accounts[0].id, to: "中文 test")
        let second = try store.add(name: "second", url: url)
        try store.move(fromOffsets: IndexSet([1]), toOffset: 0)
        precondition(AccountStore(directory: dir).accounts.map(\.name) == ["second", "中文 test"])
        try store.remove(id: second.id)
        precondition(AccountStore(directory: dir).count == 1)
        let forbidden = HTTPRequest(method: "GET", path: "/", headers: ["host": "evil.example"])
        precondition(CodeAPI.handle(forbidden, store: store).status == 403)
        let request = HTTPRequest(method: "GET", path: "/code/中文%20test", headers: ["host": "localhost"])
        precondition(CodeAPI.handle(request, store: store).status == 200)
        let permissions = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(AccountStore.fileName).path)
        precondition((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let port = UInt16.random(in: 40000...60000)
        let server = LocalHTTPServer(port: port) { CodeAPI.handle($0, store: store) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            server.onStateChange = { state in
                if state == .running { continuation.resume() }
                if case .failed(let message) = state {
                    continuation.resume(throwing: NSError(domain: message, code: 1))
                }
            }
            server.start()
        }
        defer { server.stop() }
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        precondition((response as? HTTPURLResponse)?.statusCode == 200)
        precondition(String(data: data, encoding: .utf8)?.contains("charset=\"utf-8\"") == true)
        print("PASS: Google migration decode/import/duplicates/malformed input, QR image/screenshot decoding and negative cases, bare secret normalization/validation/persistence, URL preservation, RFC 6238 (18 vectors), migration, editing/order/persistence, permissions, Host rejection, real loopback HTTP")
    }

    private static func verifyQRCodes(in directory: URL, url: String) throws {
        func qrImage(_ text: String) -> CIImage {
            let generator = CIFilter(name: "CIQRCodeGenerator")!
            generator.setValue(Data(text.utf8), forKey: "inputMessage")
            generator.setValue("M", forKey: "inputCorrectionLevel")
            let qr = generator.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
            let background = CIImage(color: .white).cropped(to: qr.extent.insetBy(dx: -32, dy: -32))
            return qr.composited(over: background)
        }
        let image = qrImage(url)
        precondition(QRCodeReader.otpAuthURLs(in: qrImage(MigrationFixtures.singleURL)) == [MigrationFixtures.singleURL])
        precondition(QRCodeReader.otpAuthURLs(in: image) == [url])
        let file = directory.appendingPathComponent("synthetic-screen.png")
        let canvas = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1200, height: 800))
        let screenshot = image.transformed(by: CGAffineTransform(translationX: 100, y: 100)).composited(over: canvas)
        try CIContext().writePNGRepresentation(of: screenshot, to: file, format: .RGBA8,
                                               colorSpace: CGColorSpaceCreateDeviceRGB())
        precondition(QRCodeReader.otpAuthURLs(in: file) == [url])
        precondition(QRCodeReader.otpAuthURLs(in: qrImage("https://example.com")).isEmpty)
        precondition(QRCodeReader.otpAuthURLs(in: canvas).isEmpty)
        precondition(QRCodeReader.otpAuthURLs(in: directory.appendingPathComponent("missing.png")).isEmpty)
        let secondURL = "otpauth://totp/Second?secret=MZXW6YTBOI"
        let second = qrImage(secondURL).transformed(by: CGAffineTransform(translationX: 650, y: 100))
        precondition(Set(QRCodeReader.otpAuthURLs(in: second.composited(over: screenshot))) == Set([url, secondURL]))
    }
}
