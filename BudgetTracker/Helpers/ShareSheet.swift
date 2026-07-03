import SwiftUI
import UIKit

/// Thin SwiftUI wrapper around `UIActivityViewController` so the CSV export /
/// backup file can be shared via the standard iOS share sheet (AirDrop, Files,
/// Mail, etc.). Presented from Settings ▸ Export data.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
