import Foundation
import Combine

/// Retain page state when returning to the workspace. Each application has its
/// own page instance, even when companies reuse the same recruitment URL.
@MainActor final class ApplicationBrowserPool: ObservableObject {
    private var sessions: [String: ApplicationBrowserSession] = [:]
    func link(key: String, to original: String) { if let value = sessions[original] { sessions[key] = value } }
    func session(key: String, url: URL) -> ApplicationBrowserSession {
        if let existing = sessions[key] { return existing }
        let value = ApplicationBrowserSession(url: url)
        sessions[key] = value
        return value
    }
}
