import Foundation
import Combine

struct Meter: Identifiable, Equatable {
    let id: String
    var used: Double?
    var reset: String?
}

@MainActor
final class Quotas: ObservableObject {
    @Published private(set) var meters: [Meter] = [
        Meter(id: "Codex"),
        Meter(id: "Cursor"),
        Meter(id: "Grok Bot")
    ]

    var onChange: (() -> Void)?

    func set(_ id: String, _ value: Double?, _ reset: String? = nil) {
        guard let index = meters.firstIndex(where: { $0.id == id }) else { return }
        let clamped = value.map { min(1, max(0, $0)) }
        if meters[index].used == clamped && meters[index].reset == reset { return }
        meters[index].used = clamped
        meters[index].reset = reset
        onChange?()
    }

    func refresh(interactive: Bool = false) {
        Task { await CodexQuota.read(into: self) }
        Task { await CursorSessionQuota.read(into: self, allowKeychainPrompt: interactive) }
    }
}
