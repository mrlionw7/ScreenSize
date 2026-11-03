import Testing
@testable import DisplayCatalog

struct ModeCatalogTests {
    private func mode(
        _ width: Int, _ height: Int, token: Int32 = 1, scale: Int = 1,
        rate: Double = 60, usable: Bool = true, interlaced: Bool = false,
        stretched: Bool = false, hidden: Bool = false
    ) -> DisplayMode {
        DisplayMode(token: token, size: .init(width: width, height: height),
                    pixelSize: .init(width: width * scale, height: height * scale),
                    refreshRate: rate, usable: usable, interlaced: interlaced,
                    stretched: stretched, hidden: hidden)
    }

    @Test func fourKMenuContainsFiveUsefulSizesAndPreservesDesk() {
        let desk = mode(3840, 2160, token: 99)
        let sizes = [(1280, 720), (1600, 900), (1920, 1080), (2048, 1152),
                     (2304, 1296), (2560, 1440), (3008, 1692), (3200, 1800)]
        let candidates = sizes.enumerated().map {
            mode($0.element.0, $0.element.1, token: Int32($0.offset), scale: 2)
        } + [desk, mode(3840, 2160, token: 100, scale: 2)]
        let result = ModeCatalog.shortlist(modes: candidates, desk: desk, preferredSizes: [])
        #expect(result.map(\.size.width) == [1600, 1920, 2560, 3008, 3840])
        #expect(result.last == desk)
    }

    @Test func hiDPIPreferredForSameSizeAndDeskNeedsExactSignature() {
        let desk = mode(3840, 2160, token: 99)
        let low = mode(1920, 1080, token: 1)
        let sharp = mode(1920, 1080, token: 2, scale: 2)
        let impostor = mode(3840, 2160, token: 99, scale: 2)
        let result = ModeCatalog.shortlist(modes: [low, sharp, impostor], desk: desk, preferredSizes: [])
        #expect(result == [sharp, impostor])
        #expect(!result.contains(desk), "A token match alone must not fabricate the saved desk mode")
    }

    @Test func rejectsUnsafeInvalidAndWrongAspectModes() {
        let desk = mode(3840, 2160, token: 99)
        let rejected = [
            mode(1920, 1080, usable: false), mode(1920, 1080, interlaced: true),
            mode(1920, 1080, stretched: true), mode(1920, 1080, hidden: true),
            mode(0, 1080), mode(1920, -1), mode(1920, 1080, scale: 0),
            mode(1920, 1080, rate: -.infinity), mode(1920, 1080, rate: .infinity),
            mode(1920, 1080, rate: .nan), mode(1920, 1080, rate: -1),
            mode(1920, 1200), mode(1024, 576), mode(4096, 2304)
        ]
        let preferred = rejected.map(\.size)
        #expect(ModeCatalog.shortlist(modes: rejected + [desk], desk: desk,
                                     preferredSizes: preferred) == [desk])
    }

    @Test func knownMatchingRefreshBeatsUnknownAndRejectsDifferentRates() {
        let desk = mode(3840, 2160, token: 99)
        let known = mode(1920, 1080, token: 1, rate: 59.94)
        let unknownSharp = mode(1920, 1080, token: 2, scale: 2, rate: 0)
        let slowSharp = mode(1920, 1080, token: 3, scale: 2, rate: 30)
        let fastSharp = mode(1920, 1080, token: 4, scale: 2, rate: 120)
        let unknownOnly = mode(1600, 900, token: 5, scale: 2, rate: 0)
        #expect(ModeCatalog.shortlist(modes: [desk, known, unknownSharp, slowSharp,
                                            fastSharp, unknownOnly], desk: desk,
                                     preferredSizes: []) == [unknownOnly, known, desk])
    }

    @Test func unavailableAnchorsAndPreferencesAreNeverFabricated() {
        let desk = mode(3840, 2160, token: 99)
        let only = mode(2304, 1296, token: 1, scale: 2)
        #expect(ModeCatalog.shortlist(modes: [only], desk: desk,
                                     preferredSizes: [.init(width: 1920, height: 1080)]) == [only])
        #expect(ModeCatalog.shortlist(modes: [], desk: desk, preferredSizes: [desk.size]).isEmpty)
    }

    @Test func requestedEligibleExtraSizeIsRetained() {
        let desk = mode(3840, 2160, token: 99)
        let sizes = [(1600, 900), (1920, 1080), (2048, 1152), (2560, 1440), (3008, 1692)]
        let candidates = sizes.enumerated().map {
            mode($0.element.0, $0.element.1, token: Int32($0.offset), scale: 2)
        } + [desk]
        let preferred = DesktopSize(width: 2048, height: 1152)
        let result = ModeCatalog.shortlist(modes: candidates, desk: desk, preferredSizes: [preferred])
        #expect(result.count == 6)
        #expect(result.contains { $0.size == preferred })
    }

    @Test func orderInvarianceAndDuplicateModes() {
        let desk = mode(3840, 2160, token: 99)
        let a = mode(1920, 1080, token: 2, scale: 2)
        let b = mode(1920, 1080, token: 1, scale: 2)
        let c = mode(1600, 900, token: 3, scale: 2)
        let candidates = [desk, a, b, c, b]
        let expected = ModeCatalog.shortlist(modes: candidates, desk: desk, preferredSizes: [])
        #expect(expected == [c, b, desk])
        for shift in 0..<candidates.count {
            let rotated = Array(candidates[shift...] + candidates[..<shift])
            #expect(ModeCatalog.shortlist(modes: rotated, desk: desk, preferredSizes: []) == expected)
            #expect(ModeCatalog.shortlist(modes: Array(rotated.reversed()), desk: desk,
                                         preferredSizes: []) == expected)
        }
    }

    @Test func smallDeskAndInvalidDesk() {
        let small = mode(1024, 576)
        #expect(ModeCatalog.shortlist(modes: [small], desk: small, preferredSizes: []) == [small])
        let invalid = mode(0, 0)
        #expect(ModeCatalog.shortlist(modes: [small], desk: invalid, preferredSizes: []).isEmpty)
        let invalidRate = mode(1920, 1080, rate: .nan)
        #expect(ModeCatalog.shortlist(modes: [small], desk: invalidRate, preferredSizes: []).isEmpty)
    }
}
