import Foundation
import Testing
@testable import GoldenPassportCore

struct OTPAuthInputTests {
    @Test func bareSecretProducesStandardURL() throws {
        let name = "测试 / 账户?#%"
        let result = try OTPAuthInput.normalizedURL("  mzxw 6ytb-oi\n", name: name)
        let parsed = try OTPAuthURL(string: result)
        #expect(parsed.label == name)
        #expect(parsed.totp == TOTP(secret: Data("foobar".utf8)))
    }

    @Test func fullURLKeepsCustomParameters() throws {
        let url = "otpauth://totp/Test?secret=MZXW6YTBOI&algorithm=SHA512&digits=8&period=60"
        #expect(try OTPAuthInput.normalizedURL(" \(url)\n", name: "test") == url)
    }

    @Test(arguments: ["", "0189", "A", "not-a-secret!"])
    func rejectsInvalidSecrets(input: String) {
        #expect(throws: OTPAuthURLError.invalidSecret) {
            try OTPAuthInput.normalizedURL(input, name: "test")
        }
    }

    @Test func bareSecretNeedsName() {
        #expect(throws: AccountStoreError.emptyName) {
            try OTPAuthInput.normalizedURL("MZXW6YTBOI", name: " ")
        }
    }
}
