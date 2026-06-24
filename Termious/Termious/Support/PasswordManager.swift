import Foundation
import CryptoKit

/// Stores the sudo password (hashed) for the session. Default password is
/// "alpine" (the classic iOS password). Change it with `passwd`.
public final class PasswordManager {
    public static let shared = PasswordManager()

    private let key = "Termious.sudo.password.v1"
    private let saltKey = "Termious.sudo.salt.v1"

    public init() {
        if UserDefaults.standard.data(forKey: key) == nil {
            setPassword("alpine")
        }
    }

    public func setPassword(_ plaintext: String) {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let derived = derive(password: plaintext, salt: salt)
        UserDefaults.standard.set(derived, forKey: key)
        UserDefaults.standard.set(salt, forKey: saltKey)
    }

    public func verify(_ plaintext: String) -> Bool {
        guard let stored = UserDefaults.standard.data(forKey: key),
              let salt = UserDefaults.standard.data(forKey: saltKey) else {
            return false
        }
        let derived = derive(password: plaintext, salt: salt)
        return derived == stored
    }

    public func changePassword(oldPlaintext: String, newPlaintext: String) -> Bool {
        guard verify(oldPlaintext) else { return false }
        setPassword(newPlaintext)
        return true
    }

    private func derive(password: String, salt: Data) -> Data {
        let pwData = Data(password.utf8)
        var combined = salt; combined.append(pwData)
        var hash = SHA256.hash(data: combined).withUnsafeBytes { Data($0) }
        for _ in 0..<1000 {
            hash = SHA256.hash(data: hash).withUnsafeBytes { Data($0) }
        }
        return hash
    }
}