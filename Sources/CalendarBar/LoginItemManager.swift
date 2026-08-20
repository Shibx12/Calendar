import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}
