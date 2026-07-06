# BudgetTracker

A native iOS personal finance app built with SwiftUI and SwiftData (iOS 17+).

## Features

- 💳 **Cash & Credit Tracking** — manage multiple credit cards with billing cycles
- 📄 **PDF Statement Import** — upload bank statements with intelligent parsing (supports DBS, OCBC, UOB, Trust, Standard Chartered)
- 🎯 **Auto-categorization** — smart category assignment with learning
- 📊 **Budget Management** — set monthly budgets per category
- 🔄 **Recurring Transactions** — auto-post rent, salary, subscriptions
- 💰 **Bills & Goals** — track payment due dates and savings targets
- 🔒 **Privacy First** — all data stays on your device, no cloud sync
- ⚙️ **Settings** — currency, Face ID lock, notifications, data export

## Tech Stack

- SwiftUI (declarative UI)
- SwiftData (persistence)
- Swift Charts (visualizations)
- PDFKit (statement parsing)
- LocalAuthentication (Face ID / Touch ID)

## Setup

1. Clone the repo
2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen):
   ```bash
   brew install xcodegen
   ```
3. Generate the Xcode project:
   ```bash
   cd BudgetTracker
   xcodegen generate
   ```
4. Open `BudgetTracker.xcodeproj` in Xcode
5. Update signing: **Signing & Capabilities** → select your team
6. Build and run (⌘R)

## Statement Parser

The app includes a coordinate-based PDF parser that rebuilds the visual table layout from word bounding boxes. This handles:
- Multi-column layouts (Standard Chartered)
- Wrapped descriptions (Trust)
- Trailing date columns (Standard Chartered: DESC AMOUNT DATE DATE)
- Leading date columns (DBS/OCBC/UOB: DATE DESC AMOUNT)
- Credits are automatically excluded (only debits/charges imported)

See `CoordinateStatementParser.swift` and `LineStatementParser.swift` for implementation details.

### Tests

Unit tests live in `BudgetTrackerTests/` and cover the deterministic parsing logic
(`parseDate`, `parseAmount`, and the line-based parser's credit-exclusion / noise
handling). Run them with:

```bash
xcodebuild -project BudgetTracker.xcodeproj -scheme BudgetTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The primary **coordinate** parser depends on PDFKit's per-glyph `characterBounds`,
which synthetic (renderer-generated) PDFs don't reproduce faithfully — so it's
validated against **real** bank statements using this manual checklist:

- [ ] DBS statement — charges imported, `… CR` payments/credits excluded
- [ ] OCBC statement — `(123.45)` parenthesised credits excluded
- [ ] UOB / Standard Chartered — trailing-date layout (`DESC AMOUNT DATE DATE`) parsed
- [ ] Trust statement — wrapped merchant names joined into one description
- [ ] Any statement — dates land in the correct month/year; rows that fail to parse
      a date show the orange ⚠️ "needs a quick check" flag rather than today's date
- [ ] Totals on the Review screen match the statement's "new transactions" subtotal

## Project Structure

```
BudgetTracker/
├── Models/              # SwiftData models
├── Views/               # SwiftUI screens
├── Helpers/             # Parsers, formatters, utilities
├── Parsers/             # Statement parsing logic
├── Theme/               # Design system
└── project.yml          # XcodeGen config
```

## Design

Aurora dark-fintech theme:
- Deep blue accent (`#3B82F6`)
- Near-black backgrounds
- Glass-card UI with subtle borders
- Haptic feedback

## License

Private project — all rights reserved.
