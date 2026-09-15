import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

public final class ScreenCapture {
    public static let shared = ScreenCapture()

    // P0-3: WindowServer enumeration (SCShareableContent) IPCs + walks every
    // window — up to seconds with many windows. Cache content + filter with
    // short TTLs; force-refresh on miss. Never on the fold critical path twice.
    private var cachedContent: (content: SCShareableContent, date: Date)?
    private var cachedFilter: (filter: SCContentFilter, displayID: CGDirectDisplayID, width: Int, height: Int, date: Date)?
    private static let contentCacheTTL: TimeInterval = 5.0
    // Filters hold the window list from creation — windows born later
    // (including our own overlay on show) are NOT excluded. Short TTL +
    // explicit invalidation on show, not a failed capture.
    private static let filterCacheTTL: TimeInterval = 1.5
    private let permissionLock = NSLock()
    private var permissionCheckedAt: TimeInterval = -.infinity
    private var cachedPermission = false

    private init() {}

    public func invalidateFilterCache() {
        cachedFilter = nil
    }

    public func invalidateCaches() {
        cachedContent = nil
        cachedFilter = nil
    }

    /// Prefer the built-in panel in multi-display sets: mirror sets report
    /// several displays and `first` is arbitrary. Falls back to first.
    static func preferredDisplay(from content: SCShareableContent) -> SCDisplay? {
        if let builtin = content.displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) {
            return builtin
        }
        return content.displays.first
    }
    
    /// Status-only check. Shared by UI, stream and overlay; never prompts.
    /// The render/sensor clocks must not generate TCC IPC at 60–120 Hz.
    public func hasPermission(forceRefresh: Bool = false) -> Bool {
        permissionLock.lock()
        defer { permissionLock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        if forceRefresh || now - permissionCheckedAt >= 2.0 {
            cachedPermission = CGPreflightScreenCaptureAccess()
            permissionCheckedAt = now
        }
        return cachedPermission
    }
    
    /// Comprehensive async verification using both CoreGraphics and ScreenCaptureKit
    public func verifyPermissionAsync() async -> Bool {
        // SCShareableContent and screenshot calls can request access themselves.
        // Never use them as a background permission probe after a denial.
        return hasPermission(forceRefresh: true)
    }
    
    /// Request screen recording permission from macOS
    @discardableResult
    public func requestPermission() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        _ = hasPermission(forceRefresh: true)
        return granted
    }
    
    /// Open System Settings directly to Privacy & Security -> Screen Recording
    public func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Relaunch application to pick up updated TCC permissions
    public func relaunchApp() {
        let appUrl = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(at: appUrl, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
    
    /// Capture the screen or load appropriate image based on settings.
    /// scaleFactor is a multiplier on the panel's backing scale. It MUST stay
    /// at 1.0 (native Retina): FoldShaders.metal derives its blur radius from
    /// `uiPixel = 2.0 / imageSize`, which assumes exactly 2 texels per point.
    /// A half-res capture both softens the fold-start frame (upscaled 2x, so
    /// text reads as blocky) and doubles the blur radius in point terms, which
    /// starves the Vogel disc and shows the tap pattern as pixelation.
    public func fetchImage(scaleFactor: CGFloat = 1.0) async -> CGImage? {
        let settings = AppSettings.shared
        
        switch settings.imageSourceMode {
        case .liveCapture:
            // Permission gate FIRST, and no wallpaper fallback while it is
            // missing. This is the load-bearing half of the first-run fix:
            // the old code fell through to fetchWallpaperImage(), so a lid
            // that was not fully open at launch (any angle below startTiltAngle
            // already produces turn > 0) painted the desktop wallpaper as a
            // full-screen "fold" over the real desktop. It looked like a hung
            // app, and the user's only cue was that tilting the lid further
            // changed it. Returning nil instead means "no frame", which the
            // overlay's cold-texture gate already handles by never showing.
            guard hasPermission() else { return nil }
            // Hot path: fast synchronous preflight only. The full async probe
            // (enumeration + test capture) runs on didBecomeActive via
            // AppSettings.refreshPermissions — never per fold frame.
            if let img = await captureLiveScreen(scaleFactor: scaleFactor) {
                return img
            }
            // Capture failed with permission in hand (transient SCK error):
            // the wallpaper still beats an empty fold here.
            return fetchWallpaperImage() ?? fetchBundledDefaultImage()
            
        case .desktopWallpaper:
            return fetchWallpaperImage() ?? fetchBundledDefaultImage()
            
        case .bundledArtwork:
            return fetchBundledDefaultImage()
            
        case .customImage:
            if !settings.customImagePath.isEmpty,
               let image = NSImage(contentsOfFile: settings.customImagePath),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cgImage
            }
            return fetchBundledDefaultImage()
        }
    }
    
    /// Live display capture using ScreenCaptureKit.
    /// One-shot SCScreenshotManager (never a streaming SCStream): no stream
    /// setup/teardown, no queueDepth memory.
    /// scaleFactor 1.0 = native Retina, which the fold shader requires.
    public func captureLiveScreen(scaleFactor: CGFloat = 1.0) async -> CGImage? {
        do {
            let content = try await freshShareableContent()
            guard let display = Self.preferredDisplay(from: content) else { return nil }

            let filter = cachedDisplayFilter(for: display, in: content)
            let config = SCStreamConfiguration()
            // NSScreen is main-thread-only; this runs on background tasks.
            // The built-in panel's scale, because the built-in panel is what
            // preferredDisplay() captured — an external monitor's scale would
            // resample the laptop's own image.
            let scale = await MainActor.run { DisplayTopology.builtInBackingScale() }
            let targetW = max(2, Int(Double(display.width) * Double(scale) * Double(scaleFactor)))
            let targetH = max(2, Int(Double(display.height) * Double(scale) * Double(scaleFactor)))
            config.width = targetW
            config.height = targetH
            config.showsCursor = false
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            print("[ScreenCapture] ScreenCaptureKit error: \(error)")
            // Stale cache (display reconfigured) — drop it so next call re-enumerates.
            cachedContent = nil
            cachedFilter = nil
            return nil
        }
    }

    private func freshShareableContent() async throws -> SCShareableContent {
        if let cached = cachedContent,
           Date().timeIntervalSince(cached.date) < Self.contentCacheTTL {
            return cached.content
        }
        let content: SCShareableContent
        if #available(macOS 14.4, *) {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } else {
            content = try await SCShareableContent.current
        }
        cachedContent = (content, Date())
        return content
    }

    private func cachedDisplayFilter(for display: SCDisplay, in content: SCShareableContent) -> SCContentFilter {
        // Mode changes reuse displayIDs with new geometry — key by all three.
        if let cached = cachedFilter,
           cached.displayID == display.displayID,
           cached.width == display.width,
           cached.height == display.height,
           Date().timeIntervalSince(cached.date) < Self.filterCacheTTL {
            return cached.filter
        }
        // Exclude our own app's windows so the overlay never captures itself.
        let currentAppPID = NSRunningApplication.current.processIdentifier
        let excludedWindows = content.windows.filter { $0.owningApplication?.processID == currentAppPID }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        cachedFilter = (filter, display.displayID, display.width, display.height, Date())
        return filter
    }
    
    /// Get user's current desktop wallpaper
    public func fetchWallpaperImage() -> CGImage? {
        // The built-in panel's wallpaper: the fold stands in for that panel, so
        // its wallpaper is the right one even when an external monitor holds
        // focus. Falls back to the main screen on a desktop Mac.
        guard let screen = DisplayTopology.builtInScreen() ?? NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    /// Fallback to the bundled default.png artwork
    public func fetchBundledDefaultImage() -> CGImage? {
        if let bundleUrl = Bundle.main.url(forResource: "default", withExtension: "png"),
           let img = NSImage(contentsOf: bundleUrl) {
            return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        
        // Bundle-relative fallbacks only (portable across machines)
        if let classBundleUrl = Bundle(for: ScreenCapture.self).url(forResource: "default", withExtension: "png"),
           let img = NSImage(contentsOf: classBundleUrl) {
            return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        let fallbackPaths = [
            Bundle.main.bundlePath + "/Contents/Resources/default.png",
            Bundle.main.bundlePath + "/Resources/default.png",
            CommandLine.arguments[0].split(separator: "/").dropLast().joined(separator: "/") + "/Resources/default.png"
        ]
        for path in fallbackPaths {
            if let img = NSImage(contentsOfFile: path),
               let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cg
            }
        }
        return nil
    }
}
