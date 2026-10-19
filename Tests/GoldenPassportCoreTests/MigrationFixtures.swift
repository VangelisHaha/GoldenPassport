import Foundation
import GoldenPassportCore

/// 使用合成密钥构造独立 wire fixture，供 Swift Testing 和本机 Swift 5.8 验收共用。
enum MigrationFixtures {
    static func integer(_ value: UInt64) -> Data {
        var value = value, bytes = Data()
        repeat {
            let byte = UInt8(value & 127)
            value >>= 7
            bytes.append(byte | (value == 0 ? 0 : 128))
        } while value != 0
        return bytes
    }

    static func field(_ number: UInt64, _ value: UInt64) -> Data {
        integer(number << 3) + integer(value)
    }

    static func field(_ number: UInt64, _ value: Data) -> Data {
        integer((number << 3) | 2) + integer(UInt64(value.count)) + value
    }

    static func account(name: String = "Synthetic", secret: String = "12345678901234567890",
                        algorithm: UInt64 = 1, digits: UInt64 = 1, type: UInt64 = 2) -> Data {
        field(1, Data(secret.utf8)) + field(2, Data(name.utf8)) + field(3, Data("Test issuer".utf8))
            + field(4, algorithm) + field(5, digits) + field(6, type)
    }

    static func payload(_ accounts: [Data], size: UInt64 = 1, index: UInt64 = 0) -> Data {
        accounts.reduce(Data()) { $0 + field(1, $1) }
            + field(2, 2) + field(3, size) + field(4, index) + field(5, 777)
    }

    static func url(_ data: Data) -> String {
        let base64 = data.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return "otpauth-migration://offline?data=" + base64
    }

    static var singleURL: String { url(payload([account()])) }

    static func verify() throws {
        for (plain, encoded) in [("f", "MY"), ("fo", "MZXQ"), ("foo", "MZXW6"), ("foobar", "MZXW6YTBOI")] {
            precondition(Base32.encode(Data(plain.utf8)) == encoded)
            precondition(Base32.decode(encoded) == Data(plain.utf8))
        }
        let parsed = try GoogleAuthMigration(string: singleURL)
        precondition(parsed.entries.count == 1 && parsed.entries[0].name == "Synthetic")
        precondition(parsed.batchSize == 1 && parsed.batchIndex == 0)
        let otp = try OTPAuthURL(string: parsed.entries[0].url)
        precondition(otp.issuer == "Test issuer")
        precondition(otp.totp.secret == Data("12345678901234567890".utf8))
        precondition(otp.totp.code(at: Date(timeIntervalSince1970: 59)) == "287082")
        let customized = account(name: "中文 / ?#%", secret: "12345678901234567890123456789012", algorithm: 2, digits: 2)
        let batch = try GoogleAuthMigration(string: url(payload([account(), customized], size: 3, index: 1)))
        precondition(batch.entries.count == 2 && batch.batchSize == 3 && batch.batchIndex == 1)
        let second = try OTPAuthURL(string: batch.entries[1].url)
        precondition(second.label == "中文 / ?#%" && second.totp.digits == 8 && second.totp.algorithm == .sha256)
        precondition(second.totp.code(at: Date(timeIntervalSince1970: 59)) == "46119246")
        let raw = payload([account()]).base64EncodedString()
        let urlSafe = raw.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let alternative = try GoogleAuthMigration(string: "otpauth-migration://offline?data=" + urlSafe)
        precondition(alternative.entries[0].url == parsed.entries[0].url)
        // 未知扩展字段应被跳过，而不是破坏账户解码。
        let extended = try GoogleAuthMigration(string: url(payload([account()]) + field(99, Data([1, 2]))))
        precondition(extended.entries[0].url == parsed.entries[0].url)
        func rejects(_ input: String, _ expected: GoogleAuthMigrationError) {
            do {
                _ = try GoogleAuthMigration(string: input)
                preconditionFailure("Invalid migration accepted")
            } catch {
                precondition(error as? GoogleAuthMigrationError == expected)
            }
        }
        rejects("otpauth-migration://offline?data=not-valid!", .invalidData)
        rejects("otpauth-migration://online?data=AA==", .invalidData)
        rejects("otpauth-migration://offline", .invalidData)
        rejects(url(Data([0])), .invalidData)
        rejects(url(Data([10, 255, 255, 255, 255, 127])), .invalidData)
        rejects(url(Data([128, 128, 128, 128, 128, 128, 128, 128, 128, 2])), .invalidData)
        rejects(url(field(1, 1)), .invalidData)
        rejects(url(payload([])), .noAccounts)
        rejects(url(payload([account(type: 1)])), .unsupportedType)
        rejects(url(payload([account(algorithm: 9)])), .unsupportedAlgorithm)
        rejects(url(payload([account(digits: 9)])), .unsupportedDigits)
        rejects(url(payload([account()], size: 1, index: 1)), .invalidData)
        rejects(url(payload([account(secret: "")])), .invalidData)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gp-migration-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountStore(directory: directory)
        let added = try store.importAccounts(batch.entries)
        precondition(added == 2)
        let repeated = try store.importAccounts(batch.entries)
        precondition(repeated == 0 && AccountStore(directory: directory).count == 2)
        // 混合 TOTP/HOTP 包整体拒绝，已有账户保持不变。
        rejects(url(payload([account(), account(type: 1)])), .unsupportedType)
        precondition(AccountStore(directory: directory).count == 2)
    }
}
