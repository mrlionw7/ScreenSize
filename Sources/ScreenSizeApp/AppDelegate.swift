import AppKit
import DisplayCatalog

/// AppKit owns presentation; ScreenController owns every display operation.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let controller = ScreenController()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu(title: "ScreenSize")
    private var lastMenuState: MenuState?
    private var refreshingMenu = false

    private var welcomeWindow: NSWindow?
    private var welcomeCurrent: NSTextField?
    private var welcomeStatus: NSTextField?
    private var deskDescription: NSTextField?
    private var remoteDescription: NSTextField?
    private var deskButton: NSButton?
    private var remoteButton: NSButton?

    private var confirmationPanel: ConfirmationPanel?
    private var confirmationMode: NSTextField?
    private var countdownLabel: NSTextField?
    private var keepButton: NSButton?
    private var revertButton: NSButton?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "ScreenSize")
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        controller.onChange = { [weak self] in self?.updateUI() }
        controller.refresh()
        updateUI()
        showWelcome(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.onChange = nil
        controller.quit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWelcome(nil)
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard !refreshingMenu else { return }
        refreshingMenu = true
        controller.refresh()
        updateUI()
        refreshingMenu = false
    }

    private var canSwitch: Bool {
        controller.canControl && !controller.busy && !controller.pendingConfirmation
    }

    private func updateUI() {
        let state = MenuState(controller)
        if state != lastMenuState {
            lastMenuState = state
            rebuildMenu()
        }
        let current = controller.current.map(Self.modeTitle) ?? "No display size available"
        statusItem?.button?.toolTip = "ScreenSize — \(controller.displayName)\n\(current)"
        statusItem?.button?.setAccessibilityLabel("ScreenSize. \(controller.displayName). \(current)")
        welcomeCurrent?.stringValue = "\(controller.displayName)\n\(current)"
        deskDescription?.stringValue = controller.desk.map(Self.shortModeTitle) ?? "Choose a preset in the menu"
        remoteDescription?.stringValue = controller.remote.map(Self.shortModeTitle) ?? "Choose a preset in the menu"
        deskButton?.isEnabled = canSwitch && controller.desk != nil
        remoteButton?.isEnabled = canSwitch && controller.remote != nil
        welcomeStatus?.stringValue = controller.errorMessage ?? controller.status ?? "Ready. Choose a preset or open the menu for more sizes."
        welcomeStatus?.textColor = controller.errorMessage == nil ? .secondaryLabelColor : .systemRed
        updateConfirmationPanel()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let heading = NSMenuItem(title: controller.displayName, action: nil, keyEquivalent: "")
        heading.attributedTitle = NSAttributedString(string: controller.displayName, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ])
        heading.isEnabled = false
        menu.addItem(heading)
        addInformation(controller.current.map { "Current: \(Self.modeTitle($0))" } ?? "No display size available")
        menu.addItem(.separator())

        addAction(presetTitle("Desk", controller.desk), #selector(useDesk(_:)), enabled: canSwitch && controller.desk != nil)
        addAction(presetTitle("Remote", controller.remote), #selector(useRemote(_:)), enabled: canSwitch && controller.remote != nil)

        let sizes = NSMenu(title: "Desktop sizes")
        sizes.autoenablesItems = false
        for mode in controller.choices {
            let item = modeItem(mode, action: #selector(useMode(_:)))
            item.state = controller.current == mode ? .on : .off
            sizes.addItem(item)
        }
        if controller.choices.isEmpty { sizes.addItem(disabledItem("No supported sizes available")) }
        addSubmenu("Desktop sizes", sizes, enabled: canSwitch)

        menu.addItem(.separator())
        addSubmenu("Set Desk preset", presetMenu(action: #selector(saveDesk(_:)), selected: controller.desk), enabled: canSwitch)
        addSubmenu("Set Remote preset", presetMenu(action: #selector(saveRemote(_:)), selected: controller.remote), enabled: canSwitch)
        addAction("Restore previous size", #selector(restorePrevious(_:)), enabled: canSwitch)

        if let message = controller.errorMessage ?? controller.status, !message.isEmpty {
            menu.addItem(.separator())
            let item = disabledItem(message)
            item.toolTip = message
            menu.addItem(item)
        }

        menu.addItem(.separator())
        addAction("Show ScreenSize…", #selector(showWelcome(_:)))
        addAction("Open Displays settings…", #selector(openDisplaysSettings(_:)))
        addAction("About ScreenSize", #selector(showAbout(_:)))
        let quit = addAction("Quit ScreenSize", #selector(quitApplication(_:)))
        quit.keyEquivalent = "q"
    }

    private func presetMenu(action: Selector, selected: DisplayMode?) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for mode in controller.allChoices {
            let item = modeItem(mode, action: action)
            item.state = selected == mode ? .on : .off
            submenu.addItem(item)
        }
        if controller.allChoices.isEmpty { submenu.addItem(disabledItem("No supported sizes available")) }
        return submenu
    }

    private func modeItem(_ mode: DisplayMode, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: Self.modeTitle(mode), action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = mode
        item.isEnabled = canSwitch
        item.toolTip = "Desktop: \(mode.size.width) × \(mode.size.height). Rendered pixels: \(mode.pixelSize.width) × \(mode.pixelSize.height)."
        return item
    }

    private func presetTitle(_ name: String, _ mode: DisplayMode?) -> String {
        mode.map { "\(name) — \(Self.shortModeTitle($0))" } ?? "\(name) — not configured"
    }

    private func addInformation(_ text: String) { menu.addItem(disabledItem(text)) }

    private func disabledItem(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @discardableResult
    private func addAction(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    private func addSubmenu(_ title: String, _ submenu: NSMenu, enabled: Bool) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.isEnabled = enabled
        menu.addItem(item)
    }

    static func shortModeTitle(_ mode: DisplayMode) -> String {
        "\(mode.size.width) × \(mode.size.height)"
    }

    static func modeTitle(_ mode: DisplayMode) -> String {
        let rate: String
        if mode.refreshRate > 0 {
            let number = mode.refreshRate.formatted(.number.precision(.fractionLength(0...2)))
            rate = "\(number) Hz"
        } else {
            rate = "refresh rate not reported"
        }
        return "\(shortModeTitle(mode)) · \(mode.isHiDPI ? "HiDPI" : "Standard") · \(rate)"
    }

    @objc private func useDesk(_ sender: Any?) { controller.applyDesk() }
    @objc private func useRemote(_ sender: Any?) { controller.applyRemote() }
    @objc private func useMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? DisplayMode else { return }
        controller.apply(mode)
    }
    @objc private func saveDesk(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? DisplayMode else { return }
        controller.saveDesk(mode)
    }
    @objc private func saveRemote(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? DisplayMode else { return }
        controller.saveRemote(mode)
    }
    @objc private func restorePrevious(_ sender: Any?) { controller.restorePrevious() }
    @objc private func keepSize(_ sender: Any?) { controller.keep() }
    @objc private func revertSize(_ sender: Any?) { controller.revert() }
    @objc private func quitApplication(_ sender: Any?) { NSApp.terminate(nil) }

    @objc private func openDisplaysSettings(_ sender: Any?) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "ScreenSize",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
            .version: "",
            .credits: NSAttributedString(string: "A small, local utility for switching your desktop size.\nUses display modes provided by macOS.")
        ])
    }

    @objc private func showMenu(_ sender: Any?) {
        statusItem.button?.performClick(nil)
    }

    @objc private func showWelcome(_ sender: Any?) {
        if welcomeWindow == nil { createWelcomeWindow() }
        updateUI()
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
        if controller.pendingConfirmation { confirmationPanel?.makeKeyAndOrderFront(nil) }
    }

    private func createWelcomeWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ScreenSize"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = NSView()
        window.contentView = content

        let title = label("A comfortable desktop size", size: 22, weight: .semibold)
        let introduction = label("Use Remote on a smaller screen. Use Desk when you return to your monitor.", size: 13, color: .secondaryLabelColor)
        let current = label("", size: 13, weight: .medium)
        welcomeCurrent = current

        let desk = button("Use Desk", action: #selector(useDesk(_:)))
        let remote = button("Use Remote", action: #selector(useRemote(_:)))
        deskButton = desk
        remoteButton = remote
        desk.setAccessibilityHelp("Switch the connected monitor to the saved Desk size.")
        remote.setAccessibilityHelp("Switch the connected monitor to the saved Remote size.")
        let deskDetail = label("", size: 11, color: .secondaryLabelColor)
        let remoteDetail = label("", size: 11, color: .secondaryLabelColor)
        deskDescription = deskDetail
        remoteDescription = remoteDetail
        let presets = NSStackView(views: [verticalStack([desk, deskDetail], spacing: 5), verticalStack([remote, remoteDetail], spacing: 5)])
        presets.orientation = .horizontal
        presets.distribution = .fillEqually
        presets.spacing = 16

        let explanation = label("This changes the connected monitor as well as your shared desktop. Windows may move or resize. Each change asks you to keep it; otherwise ScreenSize attempts to restore the previous size.", size: 12, color: .secondaryLabelColor)
        let persistence = label("Quitting ScreenSize returns to the display setting saved by macOS. Your Desk and Remote presets remain saved.", size: 12, color: .secondaryLabelColor)
        let status = label("", size: 12, color: .secondaryLabelColor)
        welcomeStatus = status
        status.setAccessibilityLabel("ScreenSize status")

        let menuButton = button("Choose sizes in the menu…", action: #selector(showMenu(_:)))
        let settingsButton = button("Displays settings…", action: #selector(openDisplaysSettings(_:)))
        settingsButton.controlSize = .small
        let actions = NSStackView(views: [menuButton, settingsButton])
        actions.orientation = .horizontal
        actions.spacing = 12
        actions.alignment = .centerY

        let stack = verticalStack([title, introduction, divider(), current, presets, explanation, persistence, status, actions], spacing: 15)
        pin(stack, in: content, inset: 24)
        window.center()
        welcomeWindow = window
    }

    private func updateConfirmationPanel() {
        guard controller.pendingConfirmation else {
            confirmationPanel?.orderOut(nil)
            return
        }
        if confirmationPanel == nil { createConfirmationPanel() }
        confirmationMode?.stringValue = controller.current.map { "Looks like \(Self.shortModeTitle($0))" } ?? "The desktop size has changed."
        let countdown = controller.busy ? "Updating display…" : "Reverting in \(max(0, controller.remainingSeconds)) seconds"
        countdownLabel?.stringValue = countdown
        countdownLabel?.setAccessibilityValue(countdown)
        keepButton?.isEnabled = !controller.busy
        revertButton?.isEnabled = !controller.busy
        if confirmationPanel?.isVisible == false {
            confirmationPanel?.center()
            NSApp.activate(ignoringOtherApps: true)
            confirmationPanel?.makeKeyAndOrderFront(nil)
        }
    }

    private func createConfirmationPanel() {
        let panel = ConfirmationPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 238),
                                      styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Confirm desktop size"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.controller.revert() }
        let content = NSView()
        panel.contentView = content
        let title = label("Keep this size?", size: 20, weight: .semibold)
        let mode = label("", size: 14, weight: .medium)
        confirmationMode = mode
        let help = label("Choose Keep if you can see and use the desktop. Otherwise, choose Revert or wait for the countdown.", size: 12, color: .secondaryLabelColor)
        let countdown = label("", size: 12, color: .secondaryLabelColor)
        countdown.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        countdownLabel = countdown

        let revert = button("Revert", action: #selector(revertSize(_:)))
        revert.keyEquivalent = "\r"
        revert.setAccessibilityHelp("Restore the previous desktop size. Return and Escape also revert.")
        let keep = button("Keep", action: #selector(keepSize(_:)))
        keep.setAccessibilityHelp("Keep this desktop size while ScreenSize is running.")
        keepButton = keep
        revertButton = revert
        let buttons = NSStackView(views: [revert, keep])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fillEqually
        let stack = verticalStack([title, mode, help, countdown, buttons], spacing: 13)
        pin(stack, in: content, inset: 22)
        confirmationPanel = panel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === confirmationPanel {
            controller.revert()
            return false
        }
        return true
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.maximumNumberOfLines = 0
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = spacing
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func pin(_ stack: NSStackView, in content: NSView, inset: CGFloat) {
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -inset)
        ])
    }
}

@MainActor
private final class ConfirmationPanel: NSPanel {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Countdown ticks should update the panel without rebuilding an open menu.
private struct MenuState: Equatable {
    let displayName: String
    let current: DisplayMode?
    let desk: DisplayMode?
    let remote: DisplayMode?
    let choices: [DisplayMode]
    let allChoices: [DisplayMode]
    let canControl: Bool
    let busy: Bool
    let pending: Bool
    let status: String?
    let error: String?

    @MainActor init(_ controller: ScreenController) {
        displayName = controller.displayName
        current = controller.current
        desk = controller.desk
        remote = controller.remote
        choices = controller.choices
        allChoices = controller.allChoices
        canControl = controller.canControl
        busy = controller.busy
        pending = controller.pendingConfirmation
        status = controller.status
        error = controller.errorMessage
    }
}
