import AppKit
import Foundation

// MARK: - UpdaterService

/// Checks GitHub Releases for a newer Snowdrop, downloads its DMG and swaps the app in place.
///
/// There is no update feed and no signing key: the release page is the source of truth, the DMG
/// is fetched over HTTPS, and before installing the new bundle must carry this app's bundle
/// identifier and a higher version. The swap itself is done by a small script that waits for this
/// process to exit, so the running app is never overwritten underneath itself.
@MainActor
@Observable
final class UpdaterService {
    // MARK: Types

    struct UpdateInfo: Equatable {
        let version: String
        let notes: String
        let downloadURL: URL
        let pageURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case downloading
        case installing
        case failed(String)
    }

    private enum Keys {
        static let automatic = "updater.automaticChecks"
        static let lastCheck = "updater.lastCheck"
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/varla-am/kaset-snowdrop/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    // MARK: State

    private(set) var state: State = .idle

    var automaticChecksEnabled: Bool {
        didSet { self.defaults.set(self.automaticChecksEnabled, forKey: Keys.automatic) }
    }

    private(set) var lastUpdateCheckDate: Date?

    var canCheckForUpdates: Bool {
        switch self.state {
        case .checking, .downloading, .installing: false
        default: true
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var promptedVersion: String?

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    ) {
        self.defaults = defaults
        self.session = session
        self.currentVersion = currentVersion
        self.automaticChecksEnabled = defaults.object(forKey: Keys.automatic) as? Bool ?? true
        self.lastUpdateCheckDate = defaults.object(forKey: Keys.lastCheck) as? Date
    }

    // MARK: Scheduling

    /// Starts the background schedule: a first check shortly after launch, then whenever a day has passed.
    func startAutomaticChecks() {
        guard self.scheduleTask == nil else { return }
        self.scheduleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            while !Task.isCancelled {
                guard let self else { return }
                if self.automaticChecksEnabled, self.isCheckDue, self.canCheckForUpdates {
                    await self.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    private var isCheckDue: Bool {
        guard let last = self.lastUpdateCheckDate else { return true }
        return Date().timeIntervalSince(last) >= Self.checkInterval
    }

    // MARK: Checking

    /// "Check Now" and the app menu item.
    func checkForUpdates() {
        guard self.canCheckForUpdates else { return }
        Task { await self.check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        self.state = .checking
        do {
            var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Snowdrop/\(self.currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await self.session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }

            self.lastUpdateCheckDate = Date()
            self.defaults.set(self.lastUpdateCheckDate, forKey: Keys.lastCheck)

            guard let info = Self.parseRelease(data), Self.isNewer(info.version, than: self.currentVersion) else {
                self.state = .upToDate
                if userInitiated { self.presentUpToDate() }
                return
            }
            self.state = .available(info)
            DiagnosticsLogger.updater.info("Update available: \(info.version, privacy: .public)")
            // Ask once per version in the background; a manual check always asks.
            if userInitiated || self.promptedVersion != info.version {
                self.promptedVersion = info.version
                self.presentAvailable(info)
            }
        } catch {
            DiagnosticsLogger.updater.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            self.state = userInitiated ? .failed(error.localizedDescription) : .idle
            if userInitiated { self.presentFailure(error.localizedDescription) }
        }
    }

    // MARK: Installing

    func installAvailableUpdate() {
        guard case let .available(info) = self.state else { return }
        Task { await self.install(info) }
    }

    private func install(_ info: UpdateInfo) async {
        do {
            let destination = Bundle.main.bundleURL
            try Self.validateInstallLocation(destination)

            self.state = .downloading
            let (downloaded, response) = try await self.session.download(from: info.downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }

            self.state = .installing
            let workDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SnowdropUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            let dmg = workDirectory.appendingPathComponent("update.dmg")
            try FileManager.default.moveItem(at: downloaded, to: dmg)

            let staged = try await Self.stageApp(fromDMG: dmg, in: workDirectory)
            try Self.validateStagedApp(staged, expectedVersion: info.version, currentVersion: self.currentVersion)

            let script = workDirectory.appendingPathComponent("install.sh")
            try Self.installerScript.write(to: script, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), staged.path, destination.path]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()

            DiagnosticsLogger.updater.info("Installing \(info.version, privacy: .public); quitting for the swap")
            NSApp.terminate(nil)
        } catch {
            DiagnosticsLogger.updater.error("Update install failed: \(error.localizedDescription, privacy: .public)")
            self.state = .failed(error.localizedDescription)
            self.presentFailure(error.localizedDescription)
        }
    }

    // MARK: Alerts

    private func presentAvailable(_ info: UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Snowdrop \(info.version) is available")
        alert.informativeText = String(localized: "You have \(self.currentVersion). Snowdrop will download the update, replace itself and restart.")
            + (info.notes.isEmpty ? "" : "\n\n" + String(info.notes.prefix(600)))
        alert.addButton(withTitle: String(localized: "Install and Restart"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            self.installAvailableUpdate()
        }
    }

    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Snowdrop is up to date")
        alert.informativeText = String(localized: "Version \(self.currentVersion) is the latest.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    private func presentFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't update Snowdrop")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}

// MARK: - Pure helpers

extension UpdaterService {
    enum UpdateError: LocalizedError {
        case badResponse
        case notInstalled
        case notWritable
        case mountFailed
        case noAppInImage
        case wrongBundle

        var errorDescription: String? {
            switch self {
            case .badResponse: String(localized: "GitHub didn't answer as expected. Try again later.")
            case .notInstalled: String(localized: "Move Snowdrop to the Applications folder first, then update.")
            case .notWritable: String(localized: "Snowdrop's folder isn't writable, so it can't replace itself.")
            case .mountFailed: String(localized: "The downloaded disk image couldn't be opened.")
            case .noAppInImage: String(localized: "The downloaded disk image doesn't contain Snowdrop.")
            case .wrongBundle: String(localized: "The downloaded app doesn't match this one, so it was not installed.")
            }
        }
    }

    /// "release-v1.2.1" → "1.2.1"; "v1.2" → "1.2".
    nonisolated static func version(fromTag tag: String) -> String {
        var version = tag
        if version.hasPrefix("release-") { version.removeFirst("release-".count) }
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }
        return version
    }

    /// Numeric, component-wise comparison ("1.10" > "1.9", "1.2" == "1.2.0").
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ string: String) -> [Int] {
            string.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let lhs = parts(candidate), rhs = parts(current)
        for index in 0 ..< max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// The release JSON from `/releases/latest`; nil for drafts, prereleases or a release without a DMG.
    nonisolated static func parseRelease(_ data: Data) -> UpdateInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]],
              let download = assets.compactMap({ asset -> URL? in
                  guard let name = asset["name"] as? String, name.lowercased().hasSuffix(".dmg"),
                        let url = asset["browser_download_url"] as? String
                  else { return nil }
                  return URL(string: url)
              }).first
        else { return nil }
        return UpdateInfo(
            version: Self.version(fromTag: tag),
            notes: json["body"] as? String ?? "",
            downloadURL: download,
            pageURL: page
        )
    }

    /// Waits for the app to quit, swaps the bundle (restoring the old one if the copy fails) and relaunches.
    nonisolated static let installerScript = """
    #!/bin/sh
    PID="$1"; NEW="$2"; DEST="$3"
    while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
    rm -rf "$DEST.old"
    if mv "$DEST" "$DEST.old" && ditto "$NEW" "$DEST"; then
        xattr -cr "$DEST"
        rm -rf "$DEST.old"
    else
        rm -rf "$DEST"
        [ -d "$DEST.old" ] && mv "$DEST.old" "$DEST"
    fi
    open "$DEST"
    rm -rf "$(dirname "$NEW")"
    """

    private static func validateInstallLocation(_ bundle: URL) throws {
        // A quarantined app runs from a read-only, randomized "translocation" path.
        if bundle.path.hasPrefix("/private/var/") || bundle.path.hasPrefix("/Volumes/") { throw UpdateError.notInstalled }
        guard FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) else {
            throw UpdateError.notWritable
        }
    }

    /// Mounts the DMG, copies the app out and unmounts.
    private static func stageApp(fromDMG dmg: URL, in directory: URL) async throws -> URL {
        let mountPoint = directory.appendingPathComponent("mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent("Snowdrop.app")

        try await Task.detached {
            guard Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-mountpoint", mountPoint.path, dmg.path]) else {
                throw UpdateError.mountFailed
            }
            defer { _ = Self.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

            let contents = (try? FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)) ?? []
            guard let app = contents.first(where: { $0.pathExtension == "app" }) else { throw UpdateError.noAppInImage }
            guard Self.run("/usr/bin/ditto", [app.path, staged.path]) else { throw UpdateError.noAppInImage }
            _ = Self.run("/usr/bin/xattr", ["-cr", staged.path])
        }.value
        return staged
    }

    private static func validateStagedApp(_ app: URL, expectedVersion: String, currentVersion: String) throws {
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              Self.isNewer(version, than: currentVersion)
        else { throw UpdateError.wrongBundle }
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
