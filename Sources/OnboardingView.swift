import SwiftUI
import AppKit

public struct OnboardingView: View {
    @ObservedObject var settings: AppSettings = AppSettings.shared
    public var onDismiss: (() -> Void)?
    
    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                appIconView
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                
                VStack(spacing: 4) {
                    Text("欢迎使用 macTilt")
                        .font(.system(size: 26, weight: .bold))
                    
                    Text("为 MacBook 带来随合盖角度变化的立体透视与虚化效果。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 32)
            .padding(.horizontal, 28)
            
            // Feature Highlights
            VStack(spacing: 16) {
                FeatureRow(
                    icon: "laptopcomputer",
                    iconColor: .blue,
                    title: "随合盖角度变化",
                    subtitle: "读取 MacBook 内置铰链传感器，合盖时画面随角度向底部转轴折叠。"
                )
                
                FeatureRow(
                    icon: "battery.100.bolt",
                    iconColor: .green,
                    title: "闲置时暂停渲染",
                    subtitle: "平时暂停画面渲染，检测到合盖动作后准备桌面捕获。铰链传感器仍以较低频率读取。"
                )
                
                FeatureRow(
                    icon: "record.circle.fill",
                    iconColor: .orange,
                    title: "屏幕录制权限",
                    subtitle: "合盖时捕获当前桌面并呈现立体效果。画面仅在本机处理。"
                )
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            
            // Permission Action Card
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(settings.hasScreenRecordingPermission ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)
                    
                    Text(settings.hasScreenRecordingPermission ? "屏幕录制权限已开启" : "需要屏幕录制权限")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    if !settings.hasScreenRecordingPermission {
                        Button(action: {
                            ScreenCapture.shared.requestPermission()
                            ScreenCapture.shared.openSettings()
                        }) {
                            Text("前往授权…")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                
                if !settings.hasScreenRecordingPermission {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("使用实时桌面捕获时，授权后才会显示合盖效果。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Text("在系统设置中开启权限后，点击“重新启动”使其生效。")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button(action: {
                                ScreenCapture.shared.relaunchApp()
                            }) {
                                Label("重新启动", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.horizontal, 28)
            
            Spacer()
            
            // Bottom Action
            HStack {
                Spacer()
                Button(action: {
                    settings.hasCompletedOnboarding = true
                    onDismiss?()
                }) {
                    Text("开始使用")
                        .font(.headline)
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                Spacer()
            }
            .padding(.bottom, 28)
            .padding(.top, 12)
        }
        .frame(width: 520, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    @ViewBuilder
    private var appIconView: some View {
        if let iconUrl = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: iconUrl) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
        } else if let appIcon = NSApplication.shared.applicationIconImage {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "laptopcomputer")
                .resizable()
                .scaledToFit()
                .foregroundColor(.accentColor)
                .padding(16)
                .background(Color.blue.opacity(0.1))
        }
    }
}

// MARK: - Apple HCI Feature Row
private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            
            Spacer(minLength: 0)
        }
    }
}
