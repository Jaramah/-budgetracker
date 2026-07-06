import SwiftUI
import AppTrackingTransparency
import AdSupport

/// Starts the ads stack: shows the App Tracking Transparency prompt once, then
/// initialises the Google Mobile Ads SDK. Safe to call unconditionally — it does
/// nothing meaningful for Pro users and is a no-op until the AdMob package is
/// added.
enum AdsBootstrap {
    /// Call once shortly after launch, only for non-Pro users.
    static func start(isPro: Bool) async {
        guard !isPro else { return }

        // ATT must be requested while the app is active; a brief delay avoids
        // racing the first frame and being silently dropped by the system.
        try? await Task.sleep(nanoseconds: 400_000_000)
        if #available(iOS 14, *) {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }

        #if canImport(GoogleMobileAds)
        GoogleMobileAds.MobileAds.shared.start(completionHandler: nil)
        #endif
    }
}
