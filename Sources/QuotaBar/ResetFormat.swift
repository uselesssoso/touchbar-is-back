import Foundation

enum ResetStyle: Equatable {
    case hours
    case days
    case absolute

    static func forProvider(_ id: String) -> ResetStyle {
        switch id {
        case "Cursor": return .absolute
        case "Grok Bot": return .days
        default: return .hours
        }
    }
}

enum ResetFormat {
    static func string(for date: Date?, style: ResetStyle, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return nil }

        switch style {
        case .hours:
            return hoursStyle(remaining: remaining)
        case .days:
            return daysStyle(remaining: remaining)
        case .absolute:
            return absoluteStyle(date: date)
        }
    }

    static func date(from value: Any?) -> Date? {
        if let seconds = (value as? NSNumber)?.doubleValue {
            let epoch = seconds > 10_000_000_000 ? seconds / 1000 : seconds
            return Date(timeIntervalSince1970: epoch)
        }
        guard let text = value as? String, !text.isEmpty else { return nil }
        if let seconds = Double(text) {
            let epoch = seconds > 10_000_000_000 ? seconds / 1000 : seconds
            return Date(timeIntervalSince1970: epoch)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: text)
    }

    private static func hoursStyle(remaining: TimeInterval) -> String {
        if remaining < 3600 {
            let minutes = max(1, Int(ceil(remaining / 60)))
            return relative("minute", minutes)
        }
        let hours = max(1, Int((remaining / 3600).rounded()))
        return relative("hour", hours)
    }

    private static func daysStyle(remaining: TimeInterval) -> String {
        if remaining >= 86_400 {
            let days = max(1, Int((remaining / 86_400).rounded()))
            return relative("day", days)
        }
        return hoursStyle(remaining: remaining)
    }

    private static func relative(_ unit: String, _ count: Int) -> String {
        let noun = count == 1 ? unit : unit + "s"
        return "resets in \(count) \(noun)"
    }

    private static func absoluteStyle(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }
}
