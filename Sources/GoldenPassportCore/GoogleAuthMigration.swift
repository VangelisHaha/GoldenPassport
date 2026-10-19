import Foundation

public enum GoogleAuthMigrationError: Error, Equatable, LocalizedError {
    case invalidData
    case noAccounts
    case unsupportedType
    case unsupportedAlgorithm
    case unsupportedDigits

    public var errorDescription: String? {
        switch self {
        case .invalidData: return String(localized: "迁移链接不完整或格式无效，请重新复制或扫描。")
        case .noAccounts: return String(localized: "迁移包中没有账户。")
        case .unsupportedType: return String(localized: "迁移包包含暂不支持的 HOTP 或未知类型账户，本次未导入。")
        case .unsupportedAlgorithm: return String(localized: "迁移包包含不支持的算法，本次未导入。")
        case .unsupportedDigits: return String(localized: "迁移包包含不支持的验证码位数，本次未导入。")
        }
    }
}

/// Google Authenticator 的离线 Protobuf 迁移链接。只在本地解析，不发网络请求。
public struct GoogleAuthMigration {
    public let entries: [(name: String, url: String)]
    public let batchSize: Int
    public let batchIndex: Int

    public static func isMigrationURL(_ input: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("otpauth-migration:")
    }

    public init(string input: String) throws {
        guard let components = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "otpauth-migration", components.host?.lowercased() == "offline",
              let values = components.queryItems?.filter({ $0.name == "data" }), values.count == 1,
              var encoded = values.first?.value, encoded.count <= 1_400_000 else {
            throw GoogleAuthMigrationError.invalidData
        }
        encoded = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard encoded.count % 4 != 1 else { throw GoogleAuthMigrationError.invalidData }
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded), data.count <= 1_048_576 else {
            throw GoogleAuthMigrationError.invalidData
        }
        var reader = ProtoReader(data)
        var accounts: [(name: String, url: String)] = []
        var size: UInt64 = 1, index: UInt64 = 0
        while let field = try reader.next() {
            switch field.number {
            case 1:
                guard accounts.count < 1000 else { throw GoogleAuthMigrationError.invalidData }
                accounts.append(try Self.account(from: field.bytes(), index: accounts.count))
            case 3: size = try field.integer()
            case 4: index = try field.integer()
            default: break // version、batch_id 及后续扩展字段不影响单个账户解码。
            }
        }
        guard !accounts.isEmpty else { throw GoogleAuthMigrationError.noAccounts }
        guard size >= 1, size <= 1000, index < size else { throw GoogleAuthMigrationError.invalidData }
        entries = accounts
        batchSize = Int(size)
        batchIndex = Int(index)
    }

    private static func account(from data: Data, index: Int) throws -> (name: String, url: String) {
        var reader = ProtoReader(data)
        var secret = Data(), name = "", issuer = ""
        var algorithm: UInt64 = 0, digits: UInt64 = 0, type: UInt64 = 0
        while let field = try reader.next() {
            switch field.number {
            case 1: secret = try field.bytes()
            case 2: name = try field.string()
            case 3: issuer = try field.string()
            case 4: algorithm = try field.integer()
            case 5: digits = try field.integer()
            case 6: type = try field.integer()
            default: break
            }
        }
        guard type == 2 else { throw GoogleAuthMigrationError.unsupportedType }
        guard !secret.isEmpty else { throw GoogleAuthMigrationError.invalidData }
        let algorithms: [UInt64: OTPAlgorithm] = [0: .sha1, 1: .sha1, 2: .sha256, 3: .sha512, 4: .md5]
        let digitCounts: [UInt64: Int] = [0: 6, 1: 6, 2: 8, 3: 7]
        guard let algorithm = algorithms[algorithm] else { throw GoogleAuthMigrationError.unsupportedAlgorithm }
        guard let digits = digitCounts[digits] else { throw GoogleAuthMigrationError.unsupportedDigits }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        issuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = issuer.isEmpty ? String(localized: "未命名 \(index + 1)") : issuer }
        let url = try OTPAuthInput.makeURL(secret: secret, name: name, issuer: issuer,
                                           algorithm: algorithm, digits: digits)
        return (name, url)
    }
}

/// 有界 Protobuf wire reader：支持 varint、长度字段及可跳过的 fixed32/fixed64。
/// 解析错误统一返回格式错误，避免把密钥或原始数据带到错误消息中。
private struct ProtoReader {
    struct Field {
        let number: UInt64
        let value: UInt64?
        let data: Data?
        func integer() throws -> UInt64 {
            guard let value else { throw GoogleAuthMigrationError.invalidData }
            return value
        }
        func bytes() throws -> Data {
            guard let data else { throw GoogleAuthMigrationError.invalidData }
            return data
        }
        func string() throws -> String {
            guard let text = String(data: try bytes(), encoding: .utf8) else { throw GoogleAuthMigrationError.invalidData }
            return text
        }
    }
    private let bytes: [UInt8]
    private var offset = 0
    init(_ data: Data) { bytes = Array(data) }

    mutating func next() throws -> Field? {
        guard offset < bytes.count else { return nil }
        let tag = try varint(), number = tag >> 3
        guard number > 0, number <= 536_870_911 else { throw GoogleAuthMigrationError.invalidData }
        switch tag & 7 {
        case 0: return Field(number: number, value: try varint(), data: nil)
        case 2:
            let length = try varint()
            guard length <= UInt64(bytes.count - offset) else { throw GoogleAuthMigrationError.invalidData }
            let end = offset + Int(length)
            let data = Data(bytes[offset..<end])
            offset = end
            return Field(number: number, value: nil, data: data)
        case 1, 5:
            let length = tag & 7 == 1 ? 8 : 4
            guard bytes.count - offset >= length else { throw GoogleAuthMigrationError.invalidData }
            offset += length
            return Field(number: number, value: nil, data: nil)
        default: throw GoogleAuthMigrationError.invalidData
        }
    }

    private mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        for byteIndex in 0..<10 {
            guard offset < bytes.count else { throw GoogleAuthMigrationError.invalidData }
            let byte = bytes[offset]
            offset += 1
            guard byteIndex < 9 || byte <= 1 else { throw GoogleAuthMigrationError.invalidData }
            result |= UInt64(byte & 127) << UInt64(byteIndex * 7)
            if byte & 128 == 0 { return result }
        }
        throw GoogleAuthMigrationError.invalidData
    }
}
