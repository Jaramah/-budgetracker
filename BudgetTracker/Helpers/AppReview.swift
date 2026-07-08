import StoreKit
import UIKit

/// App Store identity + deep links. Fill in the numeric App Store ID once the
/// listing exists (App Store Connect ▸ App Information ▸ "Apple ID").
enum AppInfo {
    /// TODO: replace with your numeric App Store ID (e.g. "6499123456").
    static let appStoreID = "0000000000"

    static var isConfigured: Bool { appStoreID != "0000000000" && !appStoreID.isEmpty }

    /// The public App Store listing.
    static var listingURL: URL? {
        isConfigured ? URL(string: "https://apps.apple.com/app/id\(appStoreID)") : nil
    }

    /// Deep link that opens the App Store straight to the "write a review" sheet.
    static var writeReviewURL: URL? {
        isConfigured ? URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review") : nil
    }
}

/// In-app ratings prompt (`SKStoreReviewController`), asked at a genuinely positive
/// moment and throttled to at most once per app version (on top of Apple's own
/// system-wide limit of ~3 prompts/year).
@MainActor
enum AppReview {
    private static let actionCountKey = "reviewPositiveActions"
    private static let lastVersionKey = "reviewLastPromptedVersion"
    /// Ask only from the 2nd happy moment onward — never on someone's very first action.
    private static let promptThreshold = 2

    /// Record a "happy" moment (e.g. a successful statement import). Prompts for a
    /// review when appropriate; safe to call every time.
    static func recordPositiveAction() {
        let d = UserDefaults.standard
        let count = d.integer(forKey: actionCountKey) + 1
        d.set(count, forKey: actionCountKey)

        guard count >= promptThreshold else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        guard d.string(forKey: lastVersionKey) != version else { return }   // once per version
        d.set(version, forKey: lastVersionKey)

        // Let any presenting sheet finish dismissing first.
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            requestReview()
        }
    }

    /// Show the system rating prompt immediately (used by the Settings "Rate" row
    /// when there's no App Store ID configured yet).
    static func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        SKStoreReviewController.requestReview(in: scene)
    }
}
