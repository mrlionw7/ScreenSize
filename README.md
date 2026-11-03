# ScreenSize

A small native macOS menu-bar app for choosing a comfortable desktop size at the
desk or over Screen Sharing. Pick a saved **Desk** or **Remote** size, or choose
from a short list of supported sizes. No subscription, third-party dependencies,
background service, or display driver.

**Version 0.1.0 is a preview for one directly connected, non-mirrored monitor.**
It changes the actual Mac desktop, including the physical monitor. It does not
create a virtual display or change Screen Sharing's video encoding.

## Use

1. Start with the monitor at your usual desk resolution, then open ScreenSize.
   The app appears in the menu bar, without a Dock icon.
2. Open its menu and choose a saved size or one of the suggested sizes.
3. Check that the desktop remains visible and readable. Choose **Keep** within
   20 seconds to keep that size, or **Revert** to restore the previous size.
   An unanswered confirmation restores the previous mode when the timer runs.
4. Switch back to **Desk** when you return to the monitor.

The initial workflow uses a 3840 × 2160 Desk size and a 1920 × 1080 Remote size,
when supported by the monitor. Saved preferences belong to the monitor; an
unavailable mode must not be silently replaced with a different one.

Switches are app-scoped rather than changes to the permanent display setting.
Quitting ScreenSize returns control to the permanent macOS display configuration.
A saved preset remembers a choice; starting the app does not automatically apply
it. Avoid changing resolutions in BetterDisplay or System Settings during a
ScreenSize confirmation.

## How sizes are chosen

ScreenSize reads supported display modes from CoreGraphics. Its shortlist is an
explicit product policy, not a replica of Apple's undisclosed System Settings
ranking:

- Use modes suitable for the desktop; exclude interlaced, stretched, and hidden
  modes.
- Preserve the Desk aspect ratio and refresh rate where macOS reports one.
- Prefer a sharp HiDPI mode for each apparent desktop size, while preserving the
  exact saved Desk mode.
- Choose approximately five useful sizes from the modes the monitor supports,
  spaced around scale factors of 1, 1.25, 1.5, 2, and 2.4 relative to Desk. Retain
  eligible saved preferences too.

For the development monitor, the shortlist is 1600 × 900, 1920 × 1080,
2560 × 1440, 3008 × 1692, and 3840 × 2160. Other monitors can produce different
choices. A refresh rate reported as zero means unknown.

**Desktop size and rendering resolution are different.** A 1920 × 1080 HiDPI
desktop may render at 3840 × 2160 backing pixels. It makes controls larger and
sharper, but does not promise less Screen Sharing traffic. Assess readability and
responsiveness through the remote connection you actually use.

## Build and install locally

Requirements: macOS 14 or later and a Swift 6 toolchain, from a compatible Xcode
or Apple Command Line Tools installation. No package dependencies are downloaded.
Run these commands from the repository directory:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
```

The script creates `dist/ScreenSize.app` and verifies its ad-hoc code signature.
To install it for your own macOS account, quit an existing copy first, then run:

```sh
mkdir -p "$HOME/Applications"
ditto dist/ScreenSize.app "$HOME/Applications/ScreenSize.app"
open "$HOME/Applications/ScreenSize.app"
```

This app does not need Screen Recording or Accessibility permission to change a
supported display mode. Run it in the logged-in desktop session; a restricted
execution sandbox may expose no displays.

The bundle is signed for local development. It is **not Developer ID signed or
notarized**, and the script is not a public binary-release pipeline. macOS can
restrict downloaded builds. A future downloadable release needs its own signing,
notarization, and clean-machine installation checks; do not disable Gatekeeper.

To uninstall, quit ScreenSize and remove `~/Applications/ScreenSize.app` in
Finder. Quitting the app is also the first recovery step for an unwanted size.

## Development

The display catalogue and selection policy are separate from the native app.
Swift Testing covers selection and switching/recovery logic without changing a
real monitor. The explicit test flag avoids requiring XCTest on Command Line
Tools installations. CI runs these tests and packages the app on macOS; it does
not exercise a physical display or publish a binary.

The read-only inspector helps diagnose supported modes:

```sh
swift run screen-size-inspect
swift run screen-size-inspect --json
```

Keep machine-specific diagnostic output outside the repository. Transient macOS
mode IDs are diagnostic values, not persistent preset identities.

## Manual acceptance checks

Tested locally on 3 October 2026 with an Apple silicon Mac mini, macOS 26.6.2,
and one BenQ MA320U at 60 Hz. All 16 automated tests and the release build passed.
Hardware checks passed for 3840 × 2160 standard and 1920 × 1080 HiDPI switching,
Keep, explicit Revert, unattended confirmation timeout, menu-bar preset selection,
app-exit restoration, and relaunch without applying a mode. The app was installed
from the ad-hoc signed local build. Remote-session disconnection, sleep/wake,
monitor reconnection, and multiple-display scenarios remain untested.

A passing build cannot establish remote-display reliability. Before relying on a
new version away from home, test the following with access to the physical Mac:

| Check | Expected result |
| --- | --- |
| Launch at the usual Desk size | A menu-bar item appears; the mode does not change. |
| Select Remote and choose Keep | The desktop becomes comfortably readable; the menu reports the chosen size. |
| Select Desk and choose Keep | The original Desk mode, including refresh rate, returns. |
| Select another size and choose Revert | The immediately previous mode returns. |
| Select another size and do nothing | The previous mode returns after the 20-second confirmation timeout. |
| Disconnect Screen Sharing during confirmation | After reconnecting, check that the timeout restored the previous mode. |
| Quit after keeping a different size | The permanent macOS display setting returns. |
| Relaunch | Saved choices remain; no mode is applied automatically. |
| Sleep/wake or disconnect/reconnect the monitor | The app refreshes its display state and handles missing modes clearly. |
| Attach a second display or enable mirroring | Unsupported topology is explained; switching is unavailable. |

Also check remote responsiveness, window placement, and idle CPU in Activity
Monitor. Record the exact hardware and macOS version with results; do not infer
support for other configurations from one successful machine.

## Recovery and current limits

A mode change may briefly blank the monitor, interrupt Screen Sharing, or move
windows. Wait for the confirmation timeout if the remote view becomes unusable.
If the size remains wrong, quit ScreenSize from its menu or Activity Monitor,
then use System Settings → Displays to select your normal size.

The confirmation timer runs in the app. Display operations run away from the
main thread; if one takes more than eight seconds, the app exits to release its
temporary display configuration. Failed restoration or an unsupported layout
during confirmation also causes an exit, with a message shown on next launch.
This cannot guarantee recovery from a stalled process or macOS display server.
Apple's documented app-exit restoration still needs physical testing on each
supported configuration.

This preview intentionally covers a single physical monitor. Automatic remote
session detection, custom timings, virtual displays, brightness controls,
launch-at-login, multi-monitor layouts, and a public binary updater are outside
its scope.

## References

- [Apple: available modes](https://developer.apple.com/documentation/coregraphics/cgdisplaycopyalldisplaymodes(_:_:))
- [Apple: mode suitability](https://developer.apple.com/documentation/coregraphics/cgdisplaymode/isusablefordesktopgui())
- [Apple: Displays settings](https://support.apple.com/guide/mac-help/displays-settings-mh40768/mac)
- [Apple: app-scoped mode switching](https://developer.apple.com/documentation/coregraphics/cgdisplaysetdisplaymode(_:_:_:))
- [Apple: macOS distribution](https://developer.apple.com/macos/distribution/)
