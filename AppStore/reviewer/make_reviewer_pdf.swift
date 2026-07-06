import AppKit
import CoreText

// Fully fictional data — no real person, card, or address.
let lines: [String] = [
    "DBS BANK LTD",
    "Live Fresh Card — Monthly Statement",
    "",
    "ALEX TAN",
    "123 Orchard Road #04-56",
    "Singapore 238888",
    "",
    "Sample statement for App Store review — all names, addresses, card",
    "numbers and transactions below are entirely fictional.",
    "",
    "Card Number:      4321-XXXX-XXXX-9012",
    "Statement Date:   30 Jun 2026",
    "Payment Due Date: 20 Jul 2026",
    "Credit Limit:     8,000.00",
    "",
    "TRANSACTION DETAILS",
    "",
    "02 JUN PREVIOUS BALANCE 1,204.50",
    "05 JUN PAYMENT - THANK YOU",
    "1,204.50 CR",
    "03 JUN FAIRPRICE FINEST SG 62.40",
    "07 JUN SHELL SERVICE STATION 88.10",
    "10 JUN GRAB SINGAPORE 15.90",
    "12 JUN NETFLIX.COM 19.98",
    "15 JUN STARBUCKS ORCHARD 8.50",
    "18 JUN SHOPEE SINGAPORE 45.30",
    "21 JUN GOMO BY SINGTEL 20.99",
    "24 JUN COLD STORAGE TANGLIN 33.75",
    "27 JUN SPOTIFY STOCKHOLM SE 16.99",
    "",
    "TOTAL OUTSTANDING BALANCE 1,204.50",
]

let pageW: CGFloat = 595, pageH: CGFloat = 842   // A4 points
let margin: CGFloat = 56
let lineH: CGFloat = 20
let font = NSFont(name: "Menlo", size: 11) ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
guard let ctx = CGContext(outURL as CFURL, mediaBox: &mediaBox, nil) else {
    fatalError("cannot create PDF context")
}

ctx.beginPDFPage(nil)
var y = pageH - margin
for (i, text) in lines.enumerated() {
    if !text.isEmpty {
        let isHeader = i <= 1 || text == "TRANSACTION DETAILS"
        let f = isHeader ? (NSFont(name: "Menlo-Bold", size: 12) ?? font) : font
        let attr = NSAttributedString(string: text, attributes: [
            .font: f,
            .foregroundColor: NSColor.black
        ])
        let ctLine = CTLineCreateWithAttributedString(attr as CFAttributedString)
        ctx.textPosition = CGPoint(x: margin, y: y)
        CTLineDraw(ctLine, ctx)
    }
    y -= lineH
}
ctx.endPDFPage()
ctx.closePDF()
print("wrote \(outURL.path)")
