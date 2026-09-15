import Foundation
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private func setupQuitShortcut() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appMenu = NSMenu()
        appMenu.addItem(
            NSMenuItem(
                title: "退出 macTilt",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory app with menu bar item, but allow the settings window to activate
        NSApp.setActivationPolicy(.accessory)
        setupQuitShortcut()
        
        // Initialize subsystems
        _ = MenuBarController.shared
        _ = OverlayWindowController.shared
        
        let sensor = LidSensor.shared
        sensor.onTurnUpdate = { turn, angle, target in
            OverlayWindowController.shared.update(turn: turn, angle: angle, target: target)
            MenuBarController.shared.updateAngleDisplay(angle: angle, isConnected: AppSettings.shared.isSensorConnected)
        }
        sensor.start()
        
        // On first launch, open the Apple HCI Onboarding window; otherwise open Settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !AppSettings.shared.hasCompletedOnboarding {
                MenuBarController.shared.openOnboardingWindow()
            } else {
                MenuBarController.shared.openSettingsWindow()
            }
        }
        
        // Setup updates and check in background
        if AppSettings.shared.automaticallyCheckForUpdates {
            UpdateChecker.shared.requestNotificationPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                UpdateChecker.shared.checkForUpdates(userInitiated: false)
            }
        }
    }
    
    /// Escape hatch for the "隐藏菜单栏图标" setting: with no status item and
    /// an .accessory activation policy there is no Dock icon either, so
    /// relaunching macTilt from Finder is the only way back. Reopen Settings in
    /// that case instead of activating to nothing.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MenuBarController.shared.openSettingsWindow()
        }
        return true
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        LidSensor.shared.stop()
    }
}
