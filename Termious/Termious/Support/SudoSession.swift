import Foundation

/// Tracks sudo authentication state. Once authenticated, subsequent sudo
/// commands within the timeout window don't re-prompt for a password.
public final class SudoSession {
    public static let shared = SudoSession()

    private(set) var lastAuthenticated: Date? = nil
    public var timeout: TimeInterval = 300 // 5 minutes

    public init() {}

    public var isAuthenticated: Bool {
        guard let last = lastAuthenticated else { return false }
        return Date().timeIntervalSince(last) < timeout
    }

    public func markAuthenticated() {
        lastAuthenticated = Date()
    }

    public func invalidate() {
        lastAuthenticated = nil
    }
}