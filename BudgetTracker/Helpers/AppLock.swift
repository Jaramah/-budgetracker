import SwiftUI
import LocalAuthentication

/// Optional biometric (Face ID / Touch ID) gate for the app's financial data.
/// Opt-in via Settings ("appLockEnabled"). Locks whenever the app leaves the
/// foreground and requires authentication to return.
@MainActor
final class AppLock: ObservableObject {
    /// True when the app is currently locked and content should be hidden.
    @Published var isLocked: Bool

    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: "appLockEnabled")
    }

    init() {
        // Start locked if the feature is on.
        self.isLocked = UserDefaults.standard.bool(forKey: "appLockEnabled")
    }

    /// Whether the device can do biometrics at all (for the Settings toggle).
    static var biometricsAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static var biometryLabel: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch ctx.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        default:        return "passcode"
        }
    }

    /// Called when the app returns to foreground.
    func lockIfNeeded() {
        if enabled { isLocked = true }
    }

    /// Prompt for biometrics / passcode and unlock on success.
    func authenticate() {
        guard enabled else { isLocked = false; return }
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics/passcode set up → don't trap the user out.
            isLocked = false
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "Unlock your budget") { [weak self] success, _ in
            Task { @MainActor in
                if success { self?.isLocked = false }
            }
        }
    }
}

/// The lock screen overlay shown while `isLocked`.
struct LockScreenView: View {
    let onUnlock: () -> Void
    var body: some View {
        ZStack {
            DS.bgBase.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(DS.accent)
                Text("Budget is locked")
                    .font(.headline)
                    .foregroundStyle(DS.inkPrimary)
                Button {
                    onUnlock()
                } label: {
                    Text("Unlock with \(AppLock.biometryLabel)")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(DS.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
