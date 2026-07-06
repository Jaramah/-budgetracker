# Publishing Budget to the App Store

A step-by-step guide, tailored to this project. Budget ~1–2 hours for the first
submission, plus Apple's review time (usually 24–48h).

Most of the project-side prep is **already done** (bundle ID, Team, icon,
screenshots, preview). The checklist at the bottom shows what's left.

---

## 0. Prerequisites

- **A Mac with Xcode** (you have Xcode 26).
- **Apple Developer Program membership** — $99/year, at
  <https://developer.apple.com/programs/>. A free account only allows on-device
  testing; you cannot ship without the paid membership. Enrollment can take
  24–48h, so start it first if you haven't.

---

## 1. Identifiers & signing — ✅ done

Already configured in `project.yml` (regenerate with `xcodegen generate` after any change):

- `options.bundleIdPrefix: com.github.jaramah`
- App `PRODUCT_BUNDLE_IDENTIFIER: com.github.jaramah.BudgetTracker`
- `DEVELOPMENT_TEAM: V5LHDBRQYB`, `CODE_SIGN_STYLE: Automatic`

**One-time in Xcode:** open `BudgetTracker.xcodeproj`, select the **BudgetTracker**
target → **Signing & Capabilities** → check **Automatically manage signing**,
choose your Team. Xcode registers the App ID on the developer portal for you.
There's no widget, no App Group, and no entitlements file to edit.

---

## 2. Icon, version, build — ✅ done

- **App icon** — a 1024×1024 **opaque** PNG lives in
  `BudgetTracker/Assets.xcassets/AppIcon.appiconset` (the alpha channel was
  removed; the App Store rejects transparent icons).
- **Version / build** — `MARKETING_VERSION 1.0`, `CURRENT_PROJECT_VERSION 1` in
  `project.yml`. Bump the build number on every upload.

---

## 3. Create the app record in App Store Connect

<https://appstoreconnect.apple.com> → **Apps → + → New App**:

- **Platform:** iOS
- **Name:** the public store name must be **globally unique**. "Budget" is
  almost certainly taken — have a distinct name ready (e.g. "Budget — Statement
  Tracker", "Aurora Budget"). The on-device icon name stays "Budget".
- **Primary language**, **Bundle ID** → pick `com.github.jaramah.BudgetTracker`,
  **SKU** → any internal string, e.g. `budget-001`.
- **Category:** Finance.

---

## 4. Screenshots & App Preview — ✅ generated

Ready to upload from `AppStore/`:

- `AppStore/screenshots/6.9/` — five **1320×2868** PNGs (iPhone 6.9", the one
  required size; it also covers 6.7"/6.5"): Home, Cards, Budget, Analytics, Activity.
- `AppStore/previews/preview_6.9_1320x2868.mp4` — a ~16s App Preview.

To regenerate them after UI changes, see `AppStore/README.md`.

---

## 5. Privacy — required before you can submit

- **Face ID usage string** is already set (`NSFaceIDUsageDescription` in
  `Info.plist`) for the optional app lock.
- **App Privacy "nutrition label"** (App Store Connect → your app → **App
  Privacy**): the app now includes **Google AdMob** in the free version, so this is
  **no longer "Data Not Collected."** Declare the advertising data AdMob collects
  (Device ID / IDFA, advertising & usage data, diagnostics) — your **financial data
  is still never collected**. Exact checkboxes are in `AppStore/SUBMISSION.md §D`.
- **App Tracking Transparency**: `NSUserTrackingUsageDescription` is set in
  `Info.plist`; the app shows the ATT prompt on first launch (free version only).
- **Privacy Policy URL** is required. The ready page in `docs/privacy.html` already
  covers ads/tracking/IAP — publish it (e.g. GitHub Pages) and paste the URL.
  `docs/index.html` works as your **Support URL**.

See **`MONETIZATION.md`** for the one-time developer setup (AdMob SDK, AdMob account +
real ad IDs, and the Budget Pro in-app purchase).

---

## 6. Export compliance — ✅ pre-answered

`ITSAppUsesNonExemptEncryption = false` is already in `Info.plist`, so you won't
be prompted at each upload (the app uses only Apple's standard APIs; no custom
crypto).

---

## 7. Archive & upload

In Xcode:
1. Scheme **BudgetTracker**, destination **Any iOS Device (arm64)** — not a simulator.
2. **Product → Archive**.
3. In the Organizer: **Distribute App → App Store Connect → Upload** (defaults are fine).

Command-line alternative:
```sh
xcodebuild -project BudgetTracker.xcodeproj -scheme BudgetTracker \
  -destination 'generic/platform=iOS' -archivePath build/BudgetTracker.xcarchive archive
xcodebuild -exportArchive -archivePath build/BudgetTracker.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
# then upload build/export/*.ipa with Transporter or `xcrun altool`
```

Wait ~5–15 min for the build to finish processing (you'll get an email).

---

## 8. TestFlight (recommended)

Once processed, install the build on your own iPhone via **TestFlight** and run
the real flows against real statements: import a PDF from each bank, delete a
statement (its transactions should disappear), and confirm Face ID lock.

---

## 9. Submit for review

Back in App Store Connect → your version:
- Attach the uploaded **Build**, add **description / keywords / subtitle**.
- **Age rating:** Finance with no objectionable content → 4+.
- **App Review Information → Notes:** tell the reviewer how to test the core
  feature, e.g. *"Cards tab → Add Card → open it → Upload Statement → pick a bank
  PDF. Everything is processed on-device."* Optionally attach a **sample
  statement PDF** (a dummy one — never your real statements; they contain your
  name and address).
- **Export compliance:** exempt (see step 6).
- **Add for Review → Submit.**

Apple reviews it (usually 24–48h). Common first-timer rejections: missing privacy
policy URL, screenshots that don't match the app, or an unclear feature the
reviewer can't reach — the reviewer note above heads that off.

---

## 10. Release

After approval, release immediately or schedule it. Updates repeat steps 2, 7,
and 9 with a bumped version/build number.

### Quick checklist
- [ ] Developer Program active
- [x] Bundle ID + Team set, automatic signing (confirm Team once in Xcode)
- [x] Opaque 1024 icon
- [ ] App record created in App Store Connect (unique name)
- [x] Screenshots + App Preview generated (`AppStore/`)
- [ ] Privacy policy + support pages published (`docs/`), URLs pasted
- [ ] App Privacy label = **Data Not Collected**
- [ ] Reviewer note (+ optional dummy statement PDF)
- [ ] Archive uploaded, build attached, submitted
