import SwiftUI

/// A bottom-anchored AdMob banner shown to free (non-Pro) users.
///
/// The whole file is guarded by `#if canImport(GoogleMobileAds)` so the app
/// compiles and runs perfectly **before** the Google Mobile Ads SPM package is
/// added — `AdBannerView` is simply an empty view until then. Once the package
/// is added (see PUBLISHING.md), real banners appear automatically with no other
/// code change.
#if canImport(GoogleMobileAds)
import GoogleMobileAds

/// SwiftUI wrapper around a GADBannerView using an adaptive banner sized to the
/// screen width.
struct AdBannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        // Standard 320×50 banner — stable across SDK versions and matches the 50pt slot.
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdConfig.bannerUnitID
        banner.rootViewController = Self.rootViewController
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    /// The banner needs a presenting view controller; grab the key window's root.
    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}

/// Fixed-height container so the banner reserves consistent layout space.
struct AdBannerSlot: View {
    var body: some View {
        AdBannerView()
            .frame(height: 50)
            .frame(maxWidth: .infinity)
    }
}

#else

/// Placeholder used until the Google Mobile Ads package is added. Renders nothing
/// and takes no space, so the app looks and behaves exactly as before.
struct AdBannerSlot: View {
    var body: some View { EmptyView() }
}

#endif
