import Foundation
import PDFKit

/// Detects which `Bank` issued a statement, from the file name and/or the
/// extracted text. Best-effort and always user-confirmed on the Review screen.
enum BankDetector {

    /// Detect from a file URL: checks the file name first (cheap), then, for PDFs,
    /// scans the first page's text. Returns `.unknown` if nothing matches.
    static func detect(url: URL) -> Bank {
        let name = url.lastPathComponent.lowercased()
        if let b = match(in: name) { return b }

        let ext = url.pathExtension.lowercased()
        if ext == "pdf", let doc = PDFDocument(url: url), !doc.isLocked {
            // First page usually carries the issuer name / logo text.
            let head = (0..<min(doc.pageCount, 2))
                .compactMap { doc.page(at: $0)?.string }
                .joined(separator: "\n")
                .lowercased()
            if let b = match(in: head) { return b }
        } else if ext == "csv" || ext == "txt" {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let b = match(in: String(text.prefix(2000)).lowercased()) {
                return b
            }
        }
        return .unknown
    }

    /// Detect from already-extracted text (e.g. when we've parsed once already).
    static func detect(text: String, fileName: String = "") -> Bank {
        if let b = match(in: fileName.lowercased()) { return b }
        return match(in: text.lowercased()) ?? .unknown
    }

    /// First bank whose keyword appears in `haystack`. Specific issuers are
    /// checked before generic ones so "standard chartered" wins over a stray "sc".
    private static func match(in haystack: String) -> Bank? {
        // Deterministic priority order (most specific / least ambiguous first).
        let order: [Bank] = [
            .standardChartered, .trust, .maybank, .citibank, .hsbc, .amex,
            .ocbc, .uob, .dbs
        ]
        for bank in order {
            for kw in bank.keywords where haystack.contains(kw) {
                return bank
            }
        }
        return nil
    }
}
