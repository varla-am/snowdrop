import Foundation

// MARK: - UpdaterService

/// Placeholder for the update checker.
///
/// Snowdrop is not distributed through an update feed, so this service keeps the
/// interface the views expect but never checks for updates.
@MainActor
@Observable
final class UpdaterService {
    var automaticChecksEnabled: Bool = false

    var canCheckForUpdates: Bool {
        false
    }

    var lastUpdateCheckDate: Date? {
        nil
    }

    init() {
        DiagnosticsLogger.updater.info("UpdaterService disabled")
    }

    func checkForUpdates() {
        DiagnosticsLogger.updater.info("Update checks are disabled")
    }
}
