import Foundation
import Testing
@testable import DisplayCatalog

struct RecoveryPolicyTests {
    private func mode(
        width: Int = 1920, height: Int = 1080, scale: Int = 2,
        rate: Double = 60, token: Int32 = 1, hidden: Bool = false
    ) -> DisplayMode {
        DisplayMode(token: token, size: .init(width: width, height: height),
                    pixelSize: .init(width: width * scale, height: height * scale),
                    refreshRate: rate, hidden: hidden)
    }

    @Test func timeoutUsesSuppliedClockAndExactDeadline() {
        var policy = RecoveryPolicy()
        let previous = mode(width: 3840, height: 2160, scale: 1)
        let target = mode()
        #expect(!policy.isExpired(now: 100))
        let began = policy.begin(previous: previous, target: target, now: 100)
        #expect(began)
        #expect(policy.pending?.deadline == 120)
        #expect(!policy.isExpired(now: 119.999))
        #expect(policy.isExpired(now: 120))
        #expect(policy.isExpired(now: 121))
        #expect(policy.pending?.previous == previous)
        #expect(policy.pending?.target == target)
    }

    @Test func keepRequiresMatchingTargetAndThenDisarms() {
        var policy = RecoveryPolicy()
        let previous = mode(width: 3840, height: 2160, scale: 1)
        let target = mode()
        let keptWithoutPending = policy.keep(current: target)
        #expect(!keptWithoutPending)
        let began = policy.begin(previous: previous, target: target, now: 0)
        #expect(began)
        let keptWrongMode = policy.keep(current: previous)
        #expect(!keptWrongMode)
        #expect(policy.pending != nil)
        let keptTarget = policy.keep(current: mode(rate: 59.94, token: 77))
        #expect(keptTarget)
        #expect(policy.pending == nil)
        #expect(!policy.isExpired(now: 100))
        #expect(!policy.shouldRestore(current: target))
    }

    @Test func cancelReturnsOriginalContextAndIsIdempotent() {
        var policy = RecoveryPolicy()
        let previous = mode(width: 3840, height: 2160, scale: 1)
        let target = mode()
        let cancelledWithoutPending = policy.cancel()
        #expect(cancelledWithoutPending == nil)
        let began = policy.begin(previous: previous, target: target, now: 5, timeout: 30)
        #expect(began)
        let cancelled = policy.cancel()
        #expect(cancelled?.previous == previous)
        #expect(cancelled?.target == target)
        #expect(cancelled?.deadline == 35)
        #expect(policy.pending == nil)
        let cancelledAgain = policy.cancel()
        #expect(cancelledAgain == nil)
    }

    @Test func concurrentSwitchCannotReplaceRecoveryContext() {
        var policy = RecoveryPolicy()
        let previous = mode(width: 3840, height: 2160, scale: 1)
        let target = mode()
        let otherTarget = mode(width: 1600, height: 900)
        let beganFirst = policy.begin(previous: previous, target: target, now: 10)
        #expect(beganFirst)
        let beganConcurrent = policy.begin(previous: target, target: otherTarget, now: 15)
        #expect(!beganConcurrent)
        #expect(policy.pending?.previous == previous)
        #expect(policy.pending?.target == target)
        #expect(policy.pending?.deadline == 30)
        policy.cancel()
        let beganAfterCancellation = policy.begin(previous: target, target: otherTarget, now: 16)
        #expect(beganAfterCancellation)
    }

    @Test func restoreOnlyWhileCurrentModeIsOurTarget() {
        var policy = RecoveryPolicy()
        let previous = mode(width: 3840, height: 2160, scale: 1)
        let target = mode()
        #expect(!policy.shouldRestore(current: target))
        let began = policy.begin(previous: previous, target: target, now: 0)
        #expect(began)
        #expect(policy.shouldRestore(current: target))
        #expect(policy.shouldRestore(current: mode(token: 99)))
        #expect(!policy.shouldRestore(current: nil))
        #expect(!policy.shouldRestore(current: previous))
        #expect(!policy.shouldRestore(current: mode(width: 2560, height: 1440)))
        #expect(!policy.shouldRestore(current: mode(scale: 1)))
        #expect(!policy.shouldRestore(current: mode(rate: 30)))
    }

    @Test func identityIgnoresTokenAndFlagsButRespectsModeSignature() {
        let identity = ModeIdentity(mode())
        #expect(identity.matches(mode(token: 321, hidden: true)))
        #expect(identity.matches(mode(rate: 59.94)))
        #expect(identity.matches(mode(rate: 59.9)))
        #expect(identity.matches(mode(rate: 60.1)))
        #expect(!identity.matches(mode(rate: 60.101)))
        #expect(!identity.matches(mode(width: 1600, height: 900)))
        #expect(!identity.matches(mode(scale: 1)))
        #expect(!identity.matches(mode(rate: 59.8)))
        #expect(!identity.matches(mode(rate: 0)))
        #expect(!identity.matches(mode(rate: .nan)))
        #expect(!ModeIdentity(mode(rate: .infinity)).matches(mode(rate: .infinity)))
        #expect(identity == ModeIdentity(mode(token: 99)))
        #expect(identity != ModeIdentity(mode(rate: 59.94)))
        #expect(Set([identity, ModeIdentity(mode(token: 99))]).count == 1)
    }

    @Test func identityRoundTripsWithoutTransientToken() throws {
        let identity = ModeIdentity(mode(token: 99))
        let encoded = try JSONEncoder().encode(identity)
        let restored = try JSONDecoder().decode(ModeIdentity.self, from: encoded)
        #expect(restored == identity)
        #expect(restored.matches(mode(token: 1)))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["token"] == nil)
    }

    @Test func invalidTimerInputsCannotArmOrExpireRecovery() {
        let previous = mode(width: 3840, height: 2160, scale: 1)
        let target = mode()
        var policy = RecoveryPolicy()
        for timeout in [0, -1, Double.nan, Double.infinity] {
            let beganWithInvalidTimeout = policy.begin(previous: previous, target: target, now: 0, timeout: timeout)
            #expect(!beganWithInvalidTimeout)
            #expect(policy.pending == nil)
        }
        let beganWithNaN = policy.begin(previous: previous, target: target, now: .nan)
        #expect(!beganWithNaN)
        let beganWithInfinity = policy.begin(previous: previous, target: target, now: .infinity)
        #expect(!beganWithInfinity)
        let beganWithOverflow = policy.begin(previous: previous, target: target,
                                             now: .greatestFiniteMagnitude, timeout: .greatestFiniteMagnitude)
        #expect(!beganWithOverflow)
        let beganWithValidClock = policy.begin(previous: previous, target: target, now: 0)
        #expect(beganWithValidClock)
        #expect(!policy.isExpired(now: .nan))
        #expect(!policy.isExpired(now: .infinity))
    }
}
