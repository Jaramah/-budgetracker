# Reviewer sample statement

`Sample-Statement.pdf` — a **fully fictional** DBS-style credit-card statement to
attach in App Store Connect ▸ App Review Information ▸ **Attachment**, so the reviewer
can test PDF import in one tap.

- No real person, address, card number, or transaction — safe to share.
- Imports via **Cards ▸ Add Card ▸ open the card ▸ Upload Statement (PDF)**.
- Parses into **9 categorized transactions**; the PREVIOUS BALANCE, the payment
  (CR) line, and the TOTAL OUTSTANDING summary are correctly excluded.

> ⚠️ Never attach your own bank statements — they contain your real name and address.
> Use this file only.

Regenerate with: `swift make_reviewer_pdf.swift Sample-Statement.pdf`
