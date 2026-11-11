import Foundation

// MARK: - VinylWallpaperTime

/// Which light the vinyl wallpaper is shown in.
enum VinylWallpaperTime: String, CaseIterable, Identifiable, Sendable {
    /// Day from the morning time until the evening time, night otherwise.
    case automatic
    case day
    case night

    var id: String {
        self.rawValue
    }
}

// MARK: - VinylDaySchedule

/// Decides when the wallpaper switches between day and night. Times are minutes since midnight.
struct VinylDaySchedule: Equatable, Sendable {
    static let defaultNightStart = 22 * 60
    static let defaultNightEnd = 7 * 60

    var nightStart: Int
    var nightEnd: Int

    init(nightStart: Int = Self.defaultNightStart, nightEnd: Int = Self.defaultNightEnd) {
        self.nightStart = Self.clamp(nightStart)
        self.nightEnd = Self.clamp(nightEnd)
    }

    private static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, 0), 24 * 60 - 1)
    }

    /// Minutes since midnight in the calendar's time zone.
    static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// True if `date` falls in the night span. The span may cross midnight (22:00 to 07:00).
    func isNight(at date: Date, calendar: Calendar = .current) -> Bool {
        let now = Self.minutes(of: date, calendar: calendar)
        if self.nightStart == self.nightEnd { return false }
        if self.nightStart < self.nightEnd {
            return now >= self.nightStart && now < self.nightEnd
        }
        return now >= self.nightStart || now < self.nightEnd
    }

    /// The next moment the answer to `isNight` changes, or nil if it never does.
    func nextChange(after date: Date, calendar: Calendar = .current) -> Date? {
        guard self.nightStart != self.nightEnd else { return nil }
        let target = self.isNight(at: date, calendar: calendar) ? self.nightEnd : self.nightStart
        return calendar.nextDate(
            after: date,
            matching: DateComponents(hour: target / 60, minute: target % 60, second: 0),
            matchingPolicy: .nextTime
        )
    }
}
