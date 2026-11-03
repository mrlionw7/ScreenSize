/// Pure confirmation state. The controller supplies a monotonic clock and
/// performs OS calls; this policy never changes the display itself.
public struct RecoveryPolicy: Sendable {
    public struct Pending: Sendable {
        public let previous: DisplayMode
        public let target: DisplayMode
        public let deadline: Double
    }

    public private(set) var pending: Pending?

    public init() {
        pending = nil
    }

    /// Arm recovery before attempting a switch. A pending change cannot be
    /// replaced, so repeated clicks cannot discard its original restore mode.
    @discardableResult
    public mutating func begin(
        previous: DisplayMode,
        target: DisplayMode,
        now: Double,
        timeout: Double = 20
    ) -> Bool {
        guard pending == nil, now.isFinite, timeout.isFinite, timeout > 0 else {
            return false
        }
        let deadline = now + timeout
        guard deadline.isFinite, deadline > now else { return false }
        pending = Pending(previous: previous, target: target, deadline: deadline)
        return true
    }

    /// Acknowledge only the mode that was requested, never a stale UI snapshot
    /// or a mode subsequently selected by another app.
    @discardableResult
    public mutating func keep(current: DisplayMode) -> Bool {
        guard let pending, ModeIdentity(pending.target).matches(current) else {
            return false
        }
        self.pending = nil
        return true
    }

    /// Disarm and return the context to the controller for a possible restore.
    @discardableResult
    public mutating func cancel() -> Pending? {
        defer { pending = nil }
        return pending
    }

    public func isExpired(now: Double) -> Bool {
        guard let pending, now.isFinite else { return false }
        return now >= pending.deadline
    }

    /// Do not overwrite an external change or guess when a display is absent.
    /// Call before cancel(), while the pending target is still available.
    public func shouldRestore(current: DisplayMode?) -> Bool {
        guard let pending, let current else { return false }
        return ModeIdentity(pending.target).matches(current)
    }
}
