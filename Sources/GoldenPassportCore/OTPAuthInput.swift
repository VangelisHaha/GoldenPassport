import Foundation

/// 将添加窗口或 CLI 的输入统一转换为存储使用的标准验证器 URL。
public enum OTPAuthInput {
    public static func normalizedURL(_ rawInput: String, name rawName: String) throws -> String {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.contains(":") {
            _ = try OTPAuthURL(string: input)
            return input
        }
        guard let decoded = Base32.decode(input), !decoded.isEmpty else {
            throw OTPAuthURLError.invalidSecret
        }
        return try makeURL(secret: decoded, name: rawName)
    }

    /// 普通密钥与迁移包共用标准地址生成器，避免丢失算法、位数与发行方。
    public static func makeURL(secret: Data, name rawName: String, issuer: String? = nil,
                               algorithm: OTPAlgorithm = .sha1, digits: Int = 6, period: Int = 30) throws -> String {
        guard !secret.isEmpty else { throw OTPAuthURLError.invalidSecret }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AccountStoreError.emptyName }
        var components = URLComponents()
        components.scheme = "otpauth"
        components.host = "totp"
        // 编码标识中的 /、?、# 等字符，保证完整保留账户名称。
        let labelCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        guard let label = name.addingPercentEncoding(withAllowedCharacters: labelCharacters) else {
            throw OTPAuthURLError.invalidURL
        }
        components.percentEncodedPath = "/" + label
        components.queryItems = [
            URLQueryItem(name: "secret", value: Base32.encode(secret)),
            URLQueryItem(name: "algorithm", value: algorithm.rawValue),
            URLQueryItem(name: "digits", value: String(digits)),
            URLQueryItem(name: "period", value: String(period)),
        ]
        if let issuer, !issuer.isEmpty { components.queryItems?.append(URLQueryItem(name: "issuer", value: issuer)) }
        guard let url = components.string else { throw OTPAuthURLError.invalidURL }
        _ = try OTPAuthURL(string: url)
        return url
    }
}
