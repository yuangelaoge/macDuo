import AppKit
import CoreGraphics
import IOKit

/// Display-topology questions, answered in one place.
///
/// These exist because two questions the app depends on are not answerable from
/// `NSScreen.main` or from the display lists alone:
///
///  - `NSScreen.main` is whichever screen holds the key window. With an
///    external monitor attached that is usually the *external* one, so
///    positioning the overlay there draws a lid-driven fold over a display the
///    lid has nothing to do with.
///  - In clamshell the built-in panel is asleep (and may have left the display
///    lists entirely), which is indistinguishable from a desktop Mac if you
///    only look at displays.
///
/// Both mistakes end the same way: the fold covering a monitor it does not
/// belong on. The fold is a rendering of the laptop's own panel folding, so the
/// built-in panel is the only screen it may ever occupy.
enum DisplayTopology {

    /// True on a portable (MacBook), false on a desktop Mac.
    ///
    /// Deliberately **not** `hw.model`. Apple Silicon model strings are not
    /// prefix-consistent — "MacBookPro18,3" for an M1 Pro, but "Mac15,12" for a
    /// MacBook Air M3 and "Mac14,3" for a Mac mini. A `hasPrefix("MacBook")`
    /// test answers "desktop" for every M2/M3-era laptop, i.e. exactly the
    /// machines the clamshell suppression has to protect.
    ///
    /// The clamshell switch in `IOPMrootDomain` only exists on portables, so its
    /// presence is decisive — and it is the same key the lid-closed check
    /// already reads. Hardware fact, so resolved once.
    static let isPortableHardware: Bool = {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let prop = IORegistryEntryCreateCFProperty(
            root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
        return prop != nil
    }()

    /// The `NSScreen` backed by the built-in panel, or nil when there is none
    /// (desktop Mac) or it is not in the active space (clamshell).
    ///
    /// Main-thread only — `NSScreen.screens` is not safe to read off-main.
    static func builtInScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let id = screen.deviceDescription[key] as? CGDirectDisplayID else { continue }
            if CGDisplayIsBuiltin(id) != 0 { return screen }
        }
        return nil
    }

    /// Built-in panel asleep-or-absent from ACTIVE space. Asleep displays stay
    /// in display space, so presence alone proves nothing — sleep state decides.
    static func isBuiltInPanelAsleepOrGone() -> Bool {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &displays, &count) == .success else { return false }
        for i in 0..<Int(count) {
            if CGDisplayIsBuiltin(displays[i]) != 0 {
                return CGDisplayIsAsleep(displays[i]) != 0
            }
        }
        // No built-in panel in the active space at all → gone (closed clamshell).
        return true
    }

    /// Is there a built-in panel in the ONLINE list? The online list retains
    /// sleeping displays, so this is the display-side portable test and the
    /// fallback for `isPortableHardware`.
    static func hasBuiltInPanelOnline() -> Bool {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return false }
        for i in 0..<Int(count) {
            if CGDisplayIsBuiltin(displays[i]) != 0 { return true }
        }
        return false
    }

    /// A laptop whose own panel is asleep or absent is in clamshell *desktop*
    /// mode: there is no laptop display to fold, and the fold must not be drawn
    /// anywhere else.
    ///
    /// Not to be confused with `AppSettings.isClamshellMode`, which means "this
    /// Mac has no continuous lid angle sensor, so drive the animation from the
    /// binary clamshell switch" — a different question about different hardware.
    ///
    /// Two things this deliberately does not do, both of which caused the fold
    /// to be painted over an external monitor:
    ///
    ///  - It does not require more than one screen. That is false in exactly the
    ///    case that matters: with the lid shut there is only the external
    ///    monitor left, so the count reads 1 and the suppression never arms.
    ///  - It does not consult the lid sensor. In clamshell the sensor is the one
    ///    thing that can be stale, unreadable or powered down, and a wrong
    ///    answer there is what let the fold through.
    static var isClamshellDesktop: Bool {
        (isPortableHardware || hasBuiltInPanelOnline()) && isBuiltInPanelAsleepOrGone()
    }

    /// Backing scale of the built-in panel, for sizing a capture of it. A
    /// capture is of the built-in panel, so its scale is the right one — using
    /// the main screen's would size the fold from an external monitor's scale
    /// and resample the laptop's own image.
    ///
    /// Main-thread only.
    static func builtInBackingScale() -> CGFloat {
        (builtInScreen() ?? NSScreen.main)?.backingScaleFactor ?? 2.0
    }
}
