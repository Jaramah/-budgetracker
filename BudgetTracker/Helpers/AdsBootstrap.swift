import SwiftUI
import AppTrackingTransparency
import AdSupport
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// Starts the ads stack: initialises the Google Mobile Ads SDK, then shows the App
/// Tracking Transparency prompt. Safe to call unconditionally — it does nothing for
/// Pro users and is a no-op until the AdMob package is added.
///
/// The SDK is started before the ATT prompt so banners can load regardless of the
/// user's tracking choice (denying ATT just means non-personalised ads).
enum AdsBootstrap {
    /// Call once shortly after launch, only for non-Pro users.
    static func start(isPro: Bool) async {
        guard !isPro else { return }

        #if canImport(GoogleMobileAds)
        MobileAds.shared.start(completionHandler: nil)
        #endif

        // ATT must be requested while the app is active; a brief delay avoids
        // racing the first frame and being silently dropped by the system.
        try? await Task.sleep(nanoseconds: 400_000_000)
        if #available(iOS 14, *) {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
    }
}
