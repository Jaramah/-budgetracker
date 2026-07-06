import Foundation

/// AdMob configuration in one place.
///
/// The IDs below are Google's **official test IDs** — they always return test
/// ads and are safe to ship during development. Before release, replace
/// `productionBannerUnitID` with your real AdMob banner ad-unit ID and set your
/// real app ID as `GADApplicationIdentifier` in `Info.plist` (see PUBLISHING.md).
///
/// Using a real ad-unit ID with your own device during testing can get your
/// AdMob account flagged, so DEBUG builds always use the test unit.
enum AdConfig {
    /// Google's public test banner unit — never bills, never risks the account.
    static let testBannerUnitID = "ca-app-pub-3940256099942544/2934735716"

    /// TODO: replace with your real AdMob banner ad-unit ID before shipping.
    static let productionBannerUnitID = "ca-app-pub-3940256099942544/2934735716"

    /// Resolved unit ID for the current build configuration.
    static var bannerUnitID: String {
        #if DEBUG
        return testBannerUnitID
        #else
        return productionBannerUnitID
        #endif
    }
}
