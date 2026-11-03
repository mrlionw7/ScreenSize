import AppKit
import Foundation
import DisplayCatalog
import DisplayRuntime

private struct SavedProfiles: Codable {
    var desk: ModeIdentity
    var remote: ModeIdentity?
}

@MainActor
final class ScreenController {
    private(set) var displayName = "Finding display…"
    private(set) var current: DisplayMode?
    private(set) var desk: DisplayMode?
    private(set) var remote: DisplayMode?
    private(set) var choices: [DisplayMode] = []
    private(set) var allChoices: [DisplayMode] = []
    private(set) var busy = false
    var pendingConfirmation: Bool { recovery.pending != nil }
    private(set) var remainingSeconds = 0
    private(set) var status: String?
    private(set) var errorMessage: String?
    private(set) var canControl = false
    var onChange: (() -> Void)?

    private let service = NativeDisplayService()
    private var display: ConnectedDisplay?
    private var profiles: SavedProfiles?
    private var recovery = RecoveryPolicy()
    private var previous: (identity: String, mode: DisplayMode)?
    private var timer: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var generation = 0
    private let clockStart = ContinuousClock.now
    private var observers: [NSObjectProtocol] = []

    init() {
        errorMessage = UserDefaults.standard.string(forKey: "lastRecoveryMessage")
        UserDefaults.standard.removeObject(forKey: "lastRecoveryMessage")
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.revert() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        refresh()
    }

    private var now: Double {
        let duration = clockStart.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    func refresh() {
        guard !busy else { return }
        let request = generation
        Task {
            do {
                let attached = try await service.displays()
                guard generation == request, !busy else { return }
                guard attached.count == 1, let found = attached.first,
                      !found.mirrored, !found.builtIn else {
                    if pendingConfirmation {
                        exitForRecovery("The display setup changed during confirmation.")
                        return
                    }
                    clearPending()
                    canControl = false
                    displayName = attached.isEmpty ? "No display connected" : "Unsupported display setup"
                    status = "Connect one external, non-mirrored display to use this preview."
                    current = nil; desk = nil; remote = nil; choices = []; allChoices = []
                    display = nil
                    onChange?()
                    return
                }
                if pendingConfirmation, found.identity != display?.identity {
                    exitForRecovery("The selected display disconnected during confirmation.")
                    return
                }
                if pendingConfirmation, !recovery.shouldRestore(current: found.current) {
                    clearPending()
                    status = "Display changed elsewhere; the pending change was cancelled."
                }
                update(found)
                onChange?()
            } catch {
                if pendingConfirmation {
                    exitForRecovery("The pending display change could not be checked.")
                    return
                }
                canControl = false
                errorMessage = error.localizedDescription
                onChange?()
            }
        }
    }

    private func update(_ found: ConnectedDisplay) {
        let changedDisplay = display?.identity != found.identity
        display = found
        current = found.current
        canControl = true
        displayName = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == found.id
        })?.localizedName ?? "External display"
        if changedDisplay || profiles == nil {
            let key = "profiles.v1.\(found.identity)"
            profiles = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(SavedProfiles.self, from: $0) }
            if profiles == nil {
                let initial = ModeCatalog.shortlist(modes: found.modes, desk: found.current,
                                                    preferredSizes: [.init(width: 1920, height: 1080)])
                profiles = SavedProfiles(desk: ModeIdentity(found.current),
                                         remote: initial.first(where: { $0.size == .init(width: 1920, height: 1080) }).map(ModeIdentity.init))
                persist()
            }
            if changedDisplay { previous = nil }
        }
        desk = found.modes.first { profiles?.desk.matches($0) == true }
        remote = found.modes.first { profiles?.remote?.matches($0) == true }
        let reference = desk ?? found.current
        choices = ModeCatalog.shortlist(modes: found.modes, desk: reference,
                                        preferredSizes: [desk?.size, remote?.size].compactMap { $0 })
        var seen = Set<ModeIdentity>()
        let aspect = Double(reference.size.width) / Double(reference.size.height)
        allChoices = found.modes.filter {
            $0.usable && !$0.interlaced && !$0.stretched && !$0.hidden
                && $0.size.width >= 1280 && $0.size.height >= 720
                && abs((Double($0.size.width) / Double($0.size.height)) / aspect - 1) < 0.01
                && ($0.refreshRate == 0 || reference.refreshRate == 0 || abs($0.refreshRate - reference.refreshRate) <= 0.5)
        }.sorted {
            if $0.size.width != $1.size.width { return $0.size.width < $1.size.width }
            if $0.isHiDPI != $1.isHiDPI { return $0.isHiDPI }
            if $0.refreshRate != $1.refreshRate { return $0.refreshRate > $1.refreshRate }
            return $0.token < $1.token
        }.filter { seen.insert(ModeIdentity($0)).inserted }
    }

    func applyDesk() { if let desk { apply(desk) } }
    func applyRemote() { if let remote { apply(remote) } }

    func apply(_ mode: DisplayMode) {
        guard canControl, !busy, !pendingConfirmation,
              let display, let current else { return }
        if ModeIdentity(mode).matches(current) { status = "This size is already active."; onChange?(); return }
        guard recovery.begin(previous: current, target: mode, now: now) else { return }
        errorMessage = nil
        remainingSeconds = 20
        status = "Applying display size…"
        beginOperation()
        Task {
            do {
                let actual = try await service.apply(identity: display.identity, mode: ModeIdentity(mode),
                                                     expectedCurrent: ModeIdentity(current))
                endOperation()
                self.current = actual
                status = "Keep this size? It will revert automatically if you do nothing."
                startCountdown()
                onChange?()
            } catch {
                endOperation()
                if let failure = error as? DisplayFailure {
                    switch failure {
                    case .changeFailed, .readbackFailed:
                        exitForRecovery(failure.localizedDescription)
                        return
                    default: break
                    }
                }
                // If the driver partially changed anything, inspect before
                // deciding whether an explicit restore is still appropriate.
                errorMessage = error.localizedDescription
                revert()
            }
        }
    }

    func keep() {
        guard !busy, let display else { return }
        if recovery.isExpired(now: now) { revert(); return }
        beginOperation()
        Task {
            do {
                let found = try await service.displays().first { $0.identity == display.identity }
                endOperation()
                guard let found, let pending = recovery.pending, recovery.keep(current: found.current) else {
                    clearPending(); status = "The display changed; nothing was confirmed."; refresh(); return
                }
                previous = (display.identity, pending.previous)
                timer?.cancel(); timer = nil; remainingSeconds = 0
                update(found)
                status = "Size kept. Quitting restores the macOS display setting."
                onChange?()
            } catch {
                endOperation(); errorMessage = error.localizedDescription; revert()
            }
        }
    }

    func revert() {
        guard !busy, let pending = recovery.cancel(), let display else { return }
        timer?.cancel(); timer = nil; remainingSeconds = 0
        beginOperation()
        Task {
            do {
                let attached = try await service.displays()
                guard let found = attached.first(where: { $0.identity == display.identity }) else {
                    throw DisplayFailure.unavailable
                }
                if ModeIdentity(pending.target).matches(found.current) {
                    _ = try await service.apply(identity: display.identity, mode: ModeIdentity(pending.previous),
                                                expectedCurrent: ModeIdentity(pending.target))
                    status = "Previous size restored."
                } else if ModeIdentity(pending.previous).matches(found.current) {
                    status = "The previous size is still active."
                } else {
                    status = "Display changed elsewhere; that setting was left alone."
                }
                endOperation(); refresh(); onChange?()
            } catch {
                endOperation()
                exitForRecovery("The previous size could not be restored. \(error.localizedDescription)")
            }
        }
    }

    func restorePrevious() {
        guard let previous, previous.identity == display?.identity else {
            status = "No previous confirmed size to restore."; onChange?(); return
        }
        apply(previous.mode)
    }

    func saveDesk(_ mode: DisplayMode) {
        guard !busy, !pendingConfirmation, allChoices.contains(mode) else { return }
        profiles?.desk = ModeIdentity(mode); persist()
        if let display { update(display) }
        status = "Desk size saved."; onChange?()
    }

    func saveRemote(_ mode: DisplayMode) {
        guard !busy, !pendingConfirmation, allChoices.contains(mode) else { return }
        profiles?.remote = ModeIdentity(mode); persist()
        if let display { update(display) }
        status = "Remote size saved."; onChange?()
    }

    func quit() { timer?.cancel(); watchdog?.cancel() }

    private func persist() {
        guard let display, let profiles, let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: "profiles.v1.\(display.identity)")
    }

    private func clearPending() {
        _ = recovery.cancel(); timer?.cancel(); timer = nil; remainingSeconds = 0
    }

    private func startCountdown() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let pending = recovery.pending else { return }
                remainingSeconds = max(0, Int(ceil(pending.deadline - now)))
                if recovery.isExpired(now: now), !busy { revert(); return }
                onChange?()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private func beginOperation() {
        busy = true; generation += 1
        watchdog?.cancel()
        // A stalled synchronous CoreGraphics call must not also block recovery.
        // Exit this unprivileged app after 8 seconds so macOS can release its
        // app-scoped configuration. This is not a driver/WindowServer guarantee.
        watchdog = Task {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            exitForRecovery("A display operation stopped responding.")
        }
        onChange?()
    }

    private func endOperation() { watchdog?.cancel(); watchdog = nil; busy = false }

    private func exitForRecovery(_ reason: String) {
        let message = "ScreenSize closed to release its temporary display setting. \(reason)"
        UserDefaults.standard.set(message, forKey: "lastRecoveryMessage")
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        NSApp.terminate(nil)
    }
}
