import Foundation
import os

/// Centralized logging for the Snowdrop app.
enum DiagnosticsLogger {
    /// Logger for authentication-related events.
    static let auth = Logger(subsystem: "com.varlaam.Snowdrop", category: "Auth")

    /// Logger for API-related events.
    static let api = Logger(subsystem: "com.varlaam.Snowdrop", category: "API")

    /// Logger for WebKit-related events.
    static let webKit = Logger(subsystem: "com.varlaam.Snowdrop", category: "WebKit")

    /// Logger for player-related events.
    static let player = Logger(subsystem: "com.varlaam.Snowdrop", category: "Player")

    /// Logger for UI-related events.
    static let ui = Logger(subsystem: "com.varlaam.Snowdrop", category: "UI")

    /// Logger for notification-related events.
    static let notification = Logger(subsystem: "com.varlaam.Snowdrop", category: "Notification")

    /// Logger for AI/Foundation Models-related events.
    static let ai = Logger(subsystem: "com.varlaam.Snowdrop", category: "AI")

    /// Logger for haptic feedback-related events.
    static let haptic = Logger(subsystem: "com.varlaam.Snowdrop", category: "Haptic")

    /// Logger for network connectivity-related events.
    static let network = Logger(subsystem: "com.varlaam.Snowdrop", category: "Network")

    /// Logger for updater/general app events.
    static let updater = Logger(subsystem: "com.varlaam.Snowdrop", category: "Updater")

    /// Logger for app lifecycle and URL handling events.
    static let app = Logger(subsystem: "com.varlaam.Snowdrop", category: "App")

    /// Logger for AppleScript scripting events.
    static let scripting = Logger(subsystem: "com.varlaam.Snowdrop", category: "Scripting")

    /// Logger for App Intents (Shortcuts, Siri, Spotlight) events.
    static let appIntents = Logger(subsystem: "com.varlaam.Snowdrop", category: "AppIntents")

    /// Logger for AirPlay-related events.
    static let airplay = Logger(subsystem: "com.varlaam.Snowdrop", category: "AirPlay")

    /// Logger for scrobbling-related events (Last.fm, etc.).
    static let scrobbling = Logger(subsystem: "com.varlaam.Snowdrop", category: "Scrobbling")

    /// Logger for web extension management events.
    static let extensions = Logger(subsystem: "com.varlaam.Snowdrop", category: "Extensions")

    /// Logger for listening history-related events.
    static let history = Logger(subsystem: "com.varlaam.Snowdrop", category: "History")

    /// Logger for the equalizer subsystem (process tap, HAL I/O, DSP).
    static let equalizer = Logger(subsystem: "com.varlaam.Snowdrop", category: "Equalizer")
}
