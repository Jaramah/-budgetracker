# App Store Connect — submission sheet

Everything to type into App Store Connect, field by field, ready to paste. Work
top to bottom. For the *mechanical* archive/upload steps see `PUBLISHING.md`.

> ★ **Finalize these first, then find-and-replace throughout this file:**
> - **App name:** `Coinfold`  ← swap for your final, unique choice
> - **Copyright holder:** `Jeremy Soh`
> - **Review contact phone:** `+65 XXXX XXXX`
> - **Pages URLs** (see “Publish the docs site” at the bottom): currently
>   `https://jaramah.github.io/-budgetracker/`

---

## A. App Information  (App Store Connect ▸ your app ▸ App Information)

| Field | Value |
|---|---|
| **Name** (max 30) | `Coinfold` |
| **Subtitle** (max 30) | `Budget & card statements` |
| **Bundle ID** | `com.github.jaramah.BudgetTracker` |
| **SKU** | `budgettracker-ios-2026` |
| **Primary language** | English (U.S.) |
| **Primary category** | Finance |
| **Secondary category** | (optional) Productivity |
| **Content rights** | *Does not contain, show, or access third-party content* |
| **Age rating** | 4+ (see section E) |
| **Privacy Policy URL** | `https://jaramah.github.io/-budgetracker/privacy.html` |

---

## B. Pricing and Availability

| Field | Value |
|---|---|
| **Price** | Free (Tier 0) — with one In-App Purchase |
| **Availability** | All countries and regions |
| **Pre-orders** | Off |
| **Distribution** | Public — App Store |

### In-App Purchase — create this before submitting

App Store Connect ▸ your app ▸ **In-App Purchases** ▸ **+** :

| Field | Value |
|---|---|
| **Type** | Non-Consumable |
| **Reference Name** | Budget Pro |
| **Product ID** | `com.github.jaramah.BudgetTracker.pro`  ← must match the app exactly |
| **Price** | S$3.98 (≈ US$2.99) — pick the tier closest to this |
| **Display Name** | Budget Pro |
| **Description** | Unlock unlimited cards and remove ads — a one-time purchase. |
| **Review screenshot** | A screenshot of the in-app paywall (Settings ▸ Unlock Pro) |
| **Review notes** | "Non-consumable that removes banner ads and lifts the one-card limit." |

> The IAP must be **submitted together with the app's first version** (attach it to the
> 1.0 build in the Version page under "In-App Purchases"), or it won't be reviewed.

---

## C. Version 1.0  (the “1.0 Prepare for Submission” page)

**Promotional Text** (max 170, editable anytime without review):
```
Upload your bank's PDF statement and see exactly where your money goes —
categorized automatically, kept private on your device. No logins, no bank connections.
```

**Description** (max 4000):
```
Coinfold turns your credit-card statements into a clear picture of where your money goes — privately, on your iPhone.

Upload the PDF statement your bank already gives you and Coinfold reads it automatically, sorts each purchase into a category, and shows you exactly what you spent. No manual typing, no linking your bank login, and nothing ever leaves your phone.

IMPORT STATEMENTS, NOT LOGINS
• Upload PDF statements from major banks — DBS, OCBC, UOB, Standard Chartered and Trust
• Purchases are parsed and categorized for you automatically
• Review every line before it's saved — you're always in control

SEE WHERE IT GOES
• Spending-by-category breakdown with a clean donut chart
• Monthly budgets with budget-vs-actual progress
• Analytics: top categories, spending by week, averages

STAY ON TOP OF IT
• Keep every card and its balance in one place
• Upcoming bills with due-date reminders
• Savings goals to work toward

PRIVATE BY DESIGN
• Your transactions, cards, and statements stay on your device — never uploaded or shared
• No accounts and no bank logins
• Optional Face ID lock for an extra layer of protection

FREE, WITH AN OPTIONAL UPGRADE
• Free to use with one card and banner ads
• Budget Pro (a one-time purchase) removes ads, unlocks unlimited cards, and adds a
  subscription tracker that spots recurring charges and reminds you before they renew

Coinfold is a simple, beautiful way to understand your spending — without handing your bank credentials to anyone.
```

**Keywords** (max 100, comma-separated, no spaces):
```
budget,expense,tracker,spending,statement,credit,card,finance,bills,savings,money,pdf,goals
```

| Field | Value |
|---|---|
| **Support URL** | `https://jaramah.github.io/-budgetracker/` |
| **Marketing URL** (optional) | leave blank or same as Support |
| **Version** | `1.0` |
| **Copyright** | `© 2026 Jeremy Soh` |

**App Previews and Screenshots** — upload under **iPhone 6.9" Display**:
- Screenshots: `AppStore/screenshots/6.9/01-Home.png` … `05-Activity.png`
- App Preview: `AppStore/previews/preview_6.9_1320x2868.mp4`
- (6.9" is the only required size; it fills the 6.7"/6.5"/6.1" slots automatically.)

**Version Release:** *Manually release this version* (so you control go-live after approval).

**Routing App Coverage File / In-App Events / etc.:** leave blank.

---

## D. App Privacy  (App Store Connect ▸ your app ▸ App Privacy)

> ⚠️ **This changed because the app now includes Google AdMob.** The old "Data Not
> Collected" answer is no longer accurate — AdMob collects advertising signals. Answer
> **Yes**, then declare only what AdMob collects (never your financial data).

| Question | Answer |
|---|---|
| Do you or your partners collect data from this app? | **Yes** |

Declare these data types (all collected by **Google AdMob**, none by you). For each,
purpose = **Third-Party Advertising** (also Analytics for Usage/Diagnostics):

| Data type | Category | Linked to user? | Used for tracking? |
|---|---|---|---|
| **Device ID** (Advertising Identifier / IDFA) | Identifiers | No | **Yes** |
| **Advertising Data** (ads seen/tapped) | Usage Data | No | **Yes** |
| **Product Interaction** | Usage Data | No | No |
| **Crash / Performance / Other Diagnostic Data** | Diagnostics | No | No |
| **Coarse Location** *(optional — declare if unsure)* | Location | No | **Yes** |

Notes for the label:
- **"Used for tracking" = Yes** for the identifier and advertising data (that's why the
  app shows the App Tracking Transparency prompt). This turns on the "Tracking" section.
- Your **financial data is NOT collected** — it never leaves the device, so it is not
  declared here at all.
- Source of truth for exactly what to check:
  [AdMob data-collection disclosures](https://support.google.com/admob/answer/9755590)
  and [Google's Apple privacy-details guidance](https://developers.google.com/admob/ios/privacy).
- **Budget Pro** users see no ads; the label still must reflect the free-version behaviour.

---

## E. Age Rating questionnaire  →  results in **4+**

Answer every content question **None / No**:

- Cartoon or Fantasy Violence — None
- Realistic Violence — None
- Sexual Content or Nudity — None
- Profanity or Crude Humor — None
- Alcohol, Tobacco, or Drug Use — None
- Mature/Suggestive Themes — None
- Horror/Fear Themes — None
- Medical/Treatment Info — None
- Gambling — No
- Contests — No
- Unrestricted Web Access — No
- (Kids Category) — Do **not** enroll in the Kids category

Result: **4+**.

---

## F. App Review Information

| Field | Value |
|---|---|
| **Sign-in required** | No (uncheck “Sign-in required”) |
| **First / Last name** | Jeremy / Soh |
| **Phone** | `+65 XXXX XXXX` |
| **Email** | `jarasoh@gmail.com` |

**Notes to reviewer** (paste):
```
This app has no account or login. Your financial data is stored only on-device.

The app opens with sample categories, bills, and a savings goal already set up. It
starts with no transactions, so to see it fully:

1) Tap the + button to add a transaction manually, OR
2) Go to the Cards tab → Add Card → open the card → "Upload Statement (PDF)" and
   import a credit-card PDF statement. The statement is parsed entirely on-device.

MONETIZATION:
- The free version shows a Google AdMob banner above the tab bar and asks the App
  Tracking Transparency prompt on first launch.
- "Budget Pro" is a one-time non-consumable in-app purchase (product ID
  com.github.jaramah.BudgetTracker.pro) that removes ads and lifts the one-card limit.
- To test Pro: Settings → Budget Pro → Unlock Pro, or the paywall shown when adding a
  second card (Cards → Add Card). Use a Sandbox Apple ID. "Restore Purchases" is in
  Settings → Budget Pro.

The Budget tab has a month selector (top-right) to view spending by category. Optional
Face ID lock can be enabled in Settings.
```

**Attachment (recommended):** attach **`AppStore/reviewer/Sample-Statement.pdf`** — a
fully fictional statement (fake name/address/card/transactions) that imports in one tap
and parses into 9 categorized transactions. *Never attach your real statements — they
contain your name and address.* See `AppStore/reviewer/README.md`.

---

## G. Export Compliance  — already handled

`ITSAppUsesNonExemptEncryption = false` is in `Info.plist`, so App Store Connect
will **not** prompt you at upload. The app uses only Apple's standard APIs (no
custom cryptography). If ever asked: **Exempt**.

---

## H. Advertising Identifier (IDFA)

At final submission you're asked "Does this app use the Advertising Identifier (IDFA)?" →
**Yes** (Google AdMob uses it). Then check the boxes that apply:

- ☑ **Serve advertisements within the app**
- ☐ Attribute this app installation to a previously served advertisement
- ☐ Attribute an action taken within this app to a previously served advertisement
- ☑ **Confirm the app uses the App Tracking Transparency framework** and only uses IDFA
  while the permission is granted (the app calls `ATTrackingManager` on first launch).

---

## Publish the docs site (for the Support & Privacy URLs)

The two URLs above must resolve before you can submit.

1. Commit `docs/` (already created: `index.html` = support, `privacy.html` = policy).
2. On GitHub: **Settings ▸ Pages ▸ Build from a branch ▸ `main` / `/docs`** → Save.
3. Wait ~1 min, then confirm both load:
   - `https://jaramah.github.io/-budgetracker/`
   - `https://jaramah.github.io/-budgetracker/privacy.html`

> ⚠️ The repo name `-budgetracker` starts with a dash, which makes an ugly, sometimes
> flaky Pages URL. Consider renaming the GitHub repo (e.g. to `coinfold`) — then the
> URLs become `https://jaramah.github.io/coinfold/…`. Update both URLs here and in
> App Store Connect if you do.

---

## The smooth-publish order (start to finish)

1. **Apple Developer Program** active (enroll if not — 24–48h).  → `PUBLISHING.md §0`
2. **Monetization setup** (one-time): add the AdMob SDK, your real AdMob IDs, and test
   the Budget Pro purchase locally.  → `MONETIZATION.md`
3. **Xcode signing:** open project, BudgetTracker target ▸ Signing & Capabilities ▸
   Automatically manage signing ▸ your Team.  → `§1`
4. **Publish `docs/`** via GitHub Pages; confirm both URLs load (above).
5. **Create the app record** in App Store Connect (Section A) — pick a unique Name.
6. **Create the In-App Purchase** `…​.pro` (Section B) — non-consumable, S$3.98.
7. **Fill Sections A–H** with the values in this sheet.
8. **Upload screenshots + preview** from `AppStore/` (Section C).
9. **Archive & upload the build** in Xcode (Any iOS Device ▸ Product ▸ Archive ▸
   Distribute ▸ App Store Connect).  → `PUBLISHING.md §7`
10. Wait for the build to finish **processing** (~5–15 min), then **attach** it to v1.0,
    and **attach the IAP** to the version.
11. **App Privacy** (D — now declares AdMob data), **Age Rating** (E), **Review Info** (F),
    **IDFA** (H — answer **Yes**).
12. **Add for Review → Submit** (app + IAP together). Choose *Manually release*.
13. (Recommended) Test the same build via **TestFlight** on your iPhone first, including a
    Sandbox purchase of Budget Pro.

Typical review time: 24–48h. Rejections at this stage are almost always: missing/
broken privacy-policy URL, screenshots that don't match the app, or the reviewer
not finding the core feature — all covered above.
