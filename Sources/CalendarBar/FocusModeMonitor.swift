import Intents

@MainActor
final class FocusModeMonitor {
    private(set) var isFocusActive = false
    var onFocusChange: ((Bool) -> Void)?

    func start() {
        requestAuthorizationIfNeeded()
    }

    func stop() {}

    func refresh() {
        let center = INFocusStatusCenter.default
        let active: Bool
        if center.authorizationStatus == .authorized {
            active = center.focusStatus.isFocused == true
        } else {
            active = false
        }

        guard active != isFocusActive else { return }
        isFocusActive = active
        onFocusChange?(active)
    }

    private func requestAuthorizationIfNeeded() {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .notDetermined else { return }
        center.requestAuthorization { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}
