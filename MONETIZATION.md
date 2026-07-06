# Monetization setup (ads + Budget Pro)

The app is **free with banner ads**, and a one-time **Budget Pro** purchase removes
the ads and unlocks unlimited cards. The code is already written and wired; this file
is the one-time setup only you can do (accounts, real IDs, the SPM package, the IAP
product).

## What's already in the app

| Piece | Where | Status |
|---|---|---|
| Pro entitlement (StoreKit 2) | `Helpers/ProStore.swift` | ✅ done |
| Paywall UI + Restore | `Views/PaywallView.swift`, Settings → Budget Pro | ✅ done |
| Free = 1 card gate | `Views/AccountsView.swift` (`store.canAddCard`) | ✅ done |
| Banner ad slot (bottom of every tab) | `Views/AdBannerView.swift`, `RootView` | ✅ code done, needs SDK |
| ATT prompt + SDK start | `Helpers/AdsBootstrap.swift` | ✅ done |
| AdMob IDs / SKAdNetwork / ATT string | `project.yml` (Info.plist) | ⚠️ using **test** IDs |
| Local StoreKit testing | `BudgetTracker.storekit` (wired to the Run scheme) | ✅ done |

The ad code is guarded by `#if canImport(GoogleMobileAds)`, so **the app builds and
runs right now with no banner** — the banner appears automatically once you add the
SDK package below.

---

## 1. Add the Google Mobile Ads SDK (Swift Package Manager)

In Xcode: **File ▸ Add Package Dependencies…** and add:

```
https://github.com/googleads/swift-package-manager-google-mobile-ads
```

Pick the latest version and add the **GoogleMobileAds** product to the **BudgetTracker**
target.

> Prefer keeping it in `project.yml` so `xcodegen generate` doesn't drop it? Add this
> under the `BudgetTracker` target and re-run `xcodegen generate`:
>
> ```yaml
>     dependencies:
>       - package: GoogleMobileAds
>   # and at the top level:
>   packages:
>     GoogleMobileAds:
>       url: https://github.com/googleads/swift-package-manager-google-mobile-ads
>       from: 12.0.0
> ```

The banner code targets the **modern GoogleMobileAds API (v12+)** — `BannerView`,
`Request()`, `MobileAds.shared`. If you pin an older major version whose symbols are
`GAD`-prefixed, adjust the names in `Views/AdBannerView.swift` / `Helpers/AdsBootstrap.swift`.

## 2. Create an AdMob account and real ad IDs

1. Sign up at <https://admob.google.com>, then **Add app** (iOS) for Budget.
2. Copy your **App ID** (looks like `ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY`).
3. Create a **Banner** ad unit; copy its **Ad unit ID**
   (`ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ`).

Then replace the **test** IDs the repo ships with:

- `project.yml` → `GADApplicationIdentifier` → your **App ID**, then `xcodegen generate`.
- `Helpers/AdConfig.swift` → `productionBannerUnitID` → your **banner Ad unit ID**.

> DEBUG builds keep using Google's test unit (`AdConfig.testBannerUnitID`) on purpose —
> tapping your own real ads can get your AdMob account suspended. Release builds use
> your real unit.

The `SKAdNetworkItems` list is already in `project.yml`; keep it current against
<https://developers.google.com/admob/ios/3p-skadnetworks> if you add mediation partners.

## 3. Create the Budget Pro in-app purchase

In App Store Connect, create a **Non-Consumable** IAP with product ID
`com.github.jaramah.BudgetTracker.pro`. Full field values are in
`AppStore/SUBMISSION.md §B` — and it must be attached to the 1.0 build for review.

## 4. Test before shipping

- **Purchases (local, no account):** the Run scheme already points at
  `BudgetTracker.storekit`, so in the Simulator you can buy/restore Pro without App
  Store Connect. Reset state via **Debug ▸ StoreKit ▸ Manage Transactions** in Xcode.
- **Purchases (real):** create a **Sandbox Apple ID** (App Store Connect ▸ Users and
  Access ▸ Sandbox) and test on device.
- **Ads:** run on device/simulator after adding the SDK — you should see Google **test**
  ads at the bottom. Buy Pro → the banner disappears and the ATT prompt no longer shows.

## 5. Ship checklist

- [ ] SDK package added; app builds in **Release**.
- [ ] Real `GADApplicationIdentifier` (project.yml) and `productionBannerUnitID` (AdConfig.swift).
- [ ] IAP `com.github.jaramah.BudgetTracker.pro` created and attached to v1.0.
- [ ] App Privacy label updated per `AppStore/SUBMISSION.md §D` (no longer "Data Not Collected").
- [ ] IDFA question answered **Yes** + ATT box checked (`§H`).
- [ ] `docs/privacy.html` published (already updated for ads/tracking/IAP).
