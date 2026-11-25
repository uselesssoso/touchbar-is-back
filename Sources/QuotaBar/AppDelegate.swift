import AppKit
import SwiftUI
import TouchBarPrivate

extension NSTouchBarItem.Identifier {
    static let quotaTray = NSTouchBarItem.Identifier("com.uselesssoso.quotabar.tray")
    static let quotaCodex = NSTouchBarItem.Identifier("com.uselesssoso.quotabar.codex")
    static let quotaCursor = NSTouchBarItem.Identifier("com.uselesssoso.quotabar.cursor")
    static let quotaGrok = NSTouchBarItem.Identifier("com.uselesssoso.quotabar.grok")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    let quotas = Quotas()
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var quotaTouchBar: NSTouchBar?
    private var trayItem: NSCustomTouchBarItem?
    private var stripViews: [String: QuotaStripView] = [:]
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "◉"

        let menu = NSMenu()
        menu.addItem(withTitle: "Show quotas", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Show on Touch Bar", action: #selector(presentTouchBarAgain), keyEquivalent: "t")
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 150),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "touchbar-is-back"
        panel.contentView = NSHostingView(rootView: QuotaPanel(quotas: quotas))
        panel.isFloatingPanel = true
        panel.level = .floating

        quotas.onChange = { [weak self] in
            self?.reloadStrips()
        }
        quotas.refresh(interactive: true)
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.quotas.refresh(interactive: false)
            }
        }

        installTouchBar()
        observeAppSwitches()
    }

    @objc func showPanel() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func refresh() {
        quotas.refresh(interactive: true)
    }

    @objc func quit() {
        if let bar = quotaTouchBar {
            QBDismissSystemModalTouchBar(bar)
        }
        if let trayItem {
            QBRemoveSystemTrayItem(trayItem)
        }
        NSApp.terminate(nil)
    }

    @objc func presentTouchBarAgain() {
        guard let bar = quotaTouchBar else { return }
        _ = QBPresentSystemModalTouchBar(bar, 0, .quotaTray)
    }

    private func installTouchBar() {
        guard QBTouchBarPrivateAvailable() else { return }

        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("com.uselesssoso.quotabar")
        bar.defaultItemIdentifiers = [.quotaCodex, .quotaCursor, .quotaGrok]
        bar.escapeKeyReplacementItemIdentifier = nil
        quotaTouchBar = bar

        QBSetSystemModalShowsCloseBoxWhenFrontMost(false)

        let tray = NSCustomTouchBarItem(identifier: .quotaTray)
        tray.view = NSButton(title: "◉", target: self, action: #selector(presentTouchBarAgain))
        trayItem = tray
        QBAddSystemTrayItem(tray)
        QBSetControlStripPresence(.quotaTray, true)

        _ = QBPresentSystemModalTouchBar(bar, 0, .quotaTray)
    }

    private func observeAppSwitches() {
        let workspace = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.presentTouchBarAgain()
            }
        }
        let unlock = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.presentTouchBarAgain()
            }
        }
        observers.append(contentsOf: [workspace, unlock])
    }

    private func reloadStrips() {
        for meter in quotas.meters {
            stripViews[meter.id]?.update(meter)
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let meterId: String
        switch identifier {
        case .quotaCodex: meterId = "Codex"
        case .quotaCursor: meterId = "Cursor"
        case .quotaGrok: meterId = "Grok Bot"
        case .quotaTray:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "◉", target: self, action: #selector(presentTouchBarAgain))
            return item
        default:
            return nil
        }

        let item = NSCustomTouchBarItem(identifier: identifier)
        let view = QuotaStripView(frame: NSRect(x: 0, y: 0, width: 140, height: 30))
        if let meter = quotas.meters.first(where: { $0.id == meterId }) {
            view.update(meter)
        }
        stripViews[meterId] = view
        item.view = view
        return item
    }
}

final class QuotaStripView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "n/a")
    private let track = NSView()
    private let fill = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor

        for label in [titleLabel, valueLabel] {
            label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            label.textColor = .white
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        valueLabel.alignment = .right
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        track.layer?.cornerRadius = 1.5
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        fill.layer?.cornerRadius = 1.5
        addSubview(track)
        track.addSubview(fill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var fraction: CGFloat = 0

    override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 30) }

    override func layout() {
        super.layout()
        let inset: CGFloat = 8
        let width = bounds.width
        titleLabel.frame = NSRect(x: inset, y: 12, width: width * 0.55, height: 14)
        valueLabel.frame = NSRect(x: width * 0.5, y: 12, width: width * 0.5 - inset, height: 14)
        track.frame = NSRect(x: inset, y: 6, width: width - inset * 2, height: 3)
        fill.frame = NSRect(x: 0, y: 0, width: max(0, track.bounds.width * fraction), height: 3)
    }

    func update(_ meter: Meter) {
        titleLabel.stringValue = meter.id
        if let used = meter.used {
            valueLabel.stringValue = "\(Int((used * 100).rounded()))%"
            fraction = CGFloat(used)
        } else {
            valueLabel.stringValue = "n/a"
            fraction = 0
        }
        needsLayout = true
    }
}

struct QuotaPanel: View {
    @ObservedObject var quotas: Quotas

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(quotas.meters) { meter in
                HStack {
                    Text(meter.id).frame(width: 78, alignment: .leading)
                    if let used = meter.used {
                        ProgressView(value: used)
                        Text("\(Int((used * 100).rounded()))%").monospacedDigit()
                    } else {
                        Text("Unavailable").foregroundStyle(.secondary)
                    }
                    if let reset = meter.reset {
                        Text(reset).font(.caption)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 380)
    }
}
