import Foundation
import Combine

struct Meter: Identifiable, Equatable {
    let id: String
    var used: Double?
    var resetAt: Date?
    var resetStyle: ResetStyle

    init(id: String, used: Double? = nil, resetAt: Date? = nil, resetStyle: ResetStyle? = nil) {
        self.id = id
        self.used = used
        self.resetAt = resetAt
        self.resetStyle = resetStyle ?? ResetStyle.forProvider(id)
    }

    var reset: String? {
        ResetFormat.string(for: resetAt, style: resetStyle)
    }
}

@MainActor
final class Quotas: ObservableObject {
    @Published private(set) var meters: [Meter] = [
        Meter(id: "Codex"),
        Meter(id: "Cursor"),
        Meter(id: "Grok Bot")
    ]

    var onChange: (() -> Void)?

    func set(_ id: String, _ value: Double?, resetAt: Date? = nil, style: ResetStyle? = nil) {
        guard let index = meters.firstIndex(where: { $0.id == id }) else { return }
        let clamped = value.map { min(1, max(0, $0)) }
        let resolvedStyle = style ?? ResetStyle.forProvider(id)
        if meters[index].used == clamped
            && meters[index].resetAt == resetAt
            && meters[index].resetStyle == resolvedStyle {
            return
        }
        meters[index].used = clamped
        meters[index].resetAt = resetAt
        meters[index].resetStyle = resolvedStyle
        onChange?()
    }

    func refresh(interactive: Bool = false) {
        Task { await CodexQuota.read(into: self) }
        Task { await CursorSessionQuota.read(into: self, allowKeychainPrompt: interactive) }
    }
}
