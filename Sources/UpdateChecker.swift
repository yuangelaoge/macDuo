import Foundation
import AppKit
import SwiftUI
import UserNotifications

public final class UpdateChecker: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = UpdateChecker()
    
    // Remote release URLs
    private let repoOwner = "lqSky7"
    private let repoName = "iphone-duo-macos-animation"
    
    @Published public var isChecking: Bool = false
    @Published public var updateAvailable: Bool = false
    @Published public var latestVersion: String = ""
    @Published public var latestReleaseUrl: URL? = nil
    @Published public var latestDmgUrl: URL? = nil
    @Published public var lastCheckDate: Date? = nil
    @Published public var statusMessage: String = ""
    @Published public var hasChecked: Bool = false
    
    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.29"
    }
    
    public var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "30"
    }
    
    public override init() {
        super.init()
        setupNotifications()
    }
    
    private func setupNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }
    
    public func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    // MARK: - Check for Updates
    
    public func checkForUpdates(userInitiated: Bool = false) {
        guard Bundle.main.bundleIdentifier == "com.lqsky7.mactilt" else {
            statusMessage = "当前为本地 Duo 整合版，上游发行版不包含这些修改。"
            hasChecked = true
            return
        }
        guard !isChecking else { return }
        
        DispatchQueue.main.async {
            self.isChecking = true
            self.statusMessage = "正在检查 GitHub 更新…"
        }
        
        Task {
            // Strategy 1: Resolve latest release tag via GitHub HTTP redirect (immune to REST API rate limits)
            let resolvedTag = await resolveLatestTagViaRedirect()
            
            await MainActor.run {
                self.isChecking = false
                self.lastCheckDate = Date()
                self.hasChecked = true
                
                guard let remoteTag = resolvedTag, !remoteTag.isEmpty else {
                    self.statusMessage = "无法检查更新，请检查网络连接。"
                    if userInitiated {
                        self.showErrorAlert(message: "无法从 GitHub 获取最新版本信息，请检查网络连接。")
                    }
                    return
                }
                
                let cleanRemote = remoteTag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                let isNewer = self.isVersion(cleanRemote, newerThan: self.currentVersion)
                
                let releasePage = URL(string: "https://github.com/\(self.repoOwner)/\(self.repoName)/releases/tag/\(remoteTag)")
                let dmgDownload = URL(string: "https://github.com/\(self.repoOwner)/\(self.repoName)/releases/download/\(remoteTag)/macTilt.dmg")
                
                self.latestVersion = "v\(cleanRemote)"
                self.latestReleaseUrl = releasePage
                self.latestDmgUrl = dmgDownload
                self.updateAvailable = isNewer
                
                if isNewer {
                    self.statusMessage = "发现新版本：v\(cleanRemote)"
                    self.postNotificationIfAvailable(version: "v\(cleanRemote)", url: releasePage ?? dmgDownload)
                    
                    if userInitiated {
                        self.showUpdateAvailableAlert(version: "v\(cleanRemote)")
                    }
                } else {
                    self.statusMessage = "macTilt v\(self.currentVersion) 已是最新版本。"
                    if userInitiated {
                        self.showUpToDateAlert()
                    }
                }
                
                MenuBarController.shared.refreshUpdateMenuState()
            }
        }
    }
    
    // MARK: - Version Comparison
    
    public func isVersion(_ remote: String, newerThan current: String) -> Bool {
        let rParts = remote.split(separator: ".").compactMap { Int($0) }
        let cParts = current.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(rParts.count, cParts.count)
        for i in 0..<maxCount {
            let rVal = i < rParts.count ? rParts[i] : 0
            let cVal = i < cParts.count ? cParts[i] : 0
            if rVal > cVal { return true }
            if rVal < cVal { return false }
        }
        return false
    }
    
    // MARK: - Rate-Limit Immune Tag Resolution
    
    private func resolveLatestTagViaRedirect() async -> String? {
        guard let url = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest") else {
            return nil
        }
        
        final class RedirectCatcher: NSObject, @unchecked Sendable, URLSessionTaskDelegate {
            var destinationURL: URL?
            func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
                destinationURL = request.url
                completionHandler(request)
            }
        }
        
        let catcher = RedirectCatcher()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config, delegate: catcher, delegateQueue: nil)
        
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        
        do {
            let (_, response) = try await session.data(for: req)
            if let finalURL = catcher.destinationURL ?? response.url {
                let tag = finalURL.lastPathComponent
                if tag != "latest" && !tag.isEmpty {
                    return tag
                }
            }
        } catch {
            print("[UpdateChecker] Error fetching release redirect: \(error)")
        }
        
        return await resolveLatestTagViaAPI()
    }
    
    private func resolveLatestTagViaAPI() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                return tag
            }
        } catch {
            print("[UpdateChecker] Error querying API: \(error)")
        }
        return nil
    }
    
    // MARK: - Notifications
    
    private func postNotificationIfAvailable(version: String, url: URL?) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "macTilt 有可用更新"
            content.subtitle = "\(version) 可以安装"
            content.body = "点击从 GitHub 下载最新版本。"
            content.sound = .default
            if let url = url {
                content.userInfo = ["url": url.absoluteString]
            }
            
            let request = UNNotificationRequest(identifier: "com.lqsky7.mactilt.update", content: content, trigger: nil)
            center.add(request)
        }
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let urlStr = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        } else if let url = latestReleaseUrl {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
    
    // MARK: - Alerts
    
    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "已是最新版本"
        alert.informativeText = "macTilt v\(currentVersion)（构建 \(currentBuild)）已是最新版本。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
    
    private func showUpdateAvailableAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = "发现新版本：\(version)"
        alert.informativeText = "GitHub 上有新版 macTilt，是否现在下载？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "下载更新")
        alert.addButton(withTitle: "稍后")
        
        if alert.runModal() == .alertFirstButtonReturn {
            openLatestRelease()
        }
    }
    
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "检查更新"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
    
    public func openLatestRelease() {
        if let url = latestDmgUrl ?? latestReleaseUrl {
            NSWorkspace.shared.open(url)
        } else if let fallback = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
