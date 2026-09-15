import SwiftUI
import AppKit

// Adaptive systemGray6 matching Apple HCI for macOS dark/light mode
private let cardBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0) // macOS systemGray6 dark
        : NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0) // macOS systemGray6 light
}))

private let cardBorder = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(white: 1.0, alpha: 0.08)
        : NSColor(white: 0.0, alpha: 0.08)
}))

public struct LiquidGlassSettingsView: View {
    @ObservedObject var settings: AppSettings = AppSettings.shared
    @ObservedObject var updater: UpdateChecker = UpdateChecker.shared
    @State private var copiedResetCommand: Bool = false
    @State private var showingPermissionTroubleshooting: Bool = false
    @State private var demoToken: Int = 0
    private var resetCommand: String { "tccutil reset ScreenCapture \(Bundle.main.bundleIdentifier ?? "local.david.mactilt-duo")" }
    
    public init() {}
    
    public var body: some View {
        // Header and footer are safe-area insets rather than VStack rows, so the
        // card list scrolls BENEATH them and the translucent material has
        // something real to blur as it passes under the bar.
        ScrollView {
            VStack(spacing: 14) {
                // Screen Recording Permission Card
                permissionCard
                
                // Battery & Performance Card
                batteryCard
                
                // Tilt Trigger Angles Card (Hardware LAS) vs Clamshell Opening Card (No LAS)
                if settings.isHardwareSensor {
                    tiltCard
                } else {
                    clamshellOpeningCard
                }
                
                // Display Source & Menu Bar Card
                displaySourceCard
                
                // Animation Physics & Shaders Card
                animationPhysicsCard
                
                // Lock Screen & Sleep Wake Card (Optional)
                lockScreenCard
                
                // Interactive Test Slider Card
                testPreviewCard
                
                // Software Updates & Release Card
                softwareUpdateCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 14)
                
                Divider()
            }
            // Pin the bar (and therefore its material) to the full window width
            // instead of letting it hug the wordmark and the chip, and let the
            // material bleed up under the transparent titlebar.
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, ignoresSafeAreaEdges: .all)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                
                footerBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, ignoresSafeAreaEdges: .all)
        }
        // Fill whatever the window hands us rather than pinning a hard size, so
        // growing the window never leaves dead space around the panel.
        .frame(minWidth: 480, idealWidth: 500, maxWidth: .infinity,
               minHeight: 560, idealHeight: 650, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            settings.refreshPermissions()
        }
        .onDisappear {
            settings.isTestModeActive = false
            settings.testTurnValue = 0.0
            OverlayWindowController.shared.stopOverlay()
        }
    }
    
    // MARK: - Header Bar
    //
    // Deliberately unadorned: the wordmark alone on the left, and a single
    // measurement chip on the right. No icon tile, no tagline — the panel's
    // own sections carry the explanation.
    private var headerBar: some View {
        HStack(spacing: 12) {
            Text("macTilt")
                .font(.system(size: 26, weight: .thin))
                .foregroundStyle(.primary)
            
            Spacer(minLength: 0)
            
            // Live reading chip. The source of the number is named in small
            // translucent type underneath it, so the badge reads as a
            // measurement rather than a status label.
            VStack(alignment: .trailing, spacing: 0) {
                if settings.isHardwareSensor {
                    Text("\(Int(settings.currentLidAngle))°")
                        .font(.system(size: 21, weight: .light))
                        .monospacedDigit()
                    Text("铰链角度")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                        .opacity(0.6)
                } else {
                    Text("开盖模式")
                        .font(.system(size: 15, weight: .light))
                    Text("无角度传感器")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                        .opacity(0.6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(cardBorder, lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Screen Recording Permission Card
    private var permissionCard: some View {
        HCISectionCard(title: "屏幕录制权限", icon: "video.badge.checkmark") {
            HStack(spacing: 10) {
                Image(systemName: settings.hasScreenRecordingPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(settings.hasScreenRecordingPermission ? Color.green : Color.orange)
                    .font(.system(size: 15))
                
                Text(settings.hasScreenRecordingPermission ? "已授权" : "需要授权")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                InfoButton("屏幕录制", content: "实时桌面捕获需要屏幕录制权限，用于在合盖时获取桌面并生成立体效果。所有画面均在本机处理；此模式在授权前不会显示动画。")
                
                Spacer()
                
                Button {
                    settings.refreshPermissions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("重新检查权限")
                
                if !settings.hasScreenRecordingPermission {
                    Button("重新启动") {
                        ScreenCapture.shared.relaunchApp()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("前往授权") {
                        if !ScreenCapture.shared.requestPermission() {
                            ScreenCapture.shared.openSettings()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            settings.refreshPermissions()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button {
                        showingPermissionTroubleshooting.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("排查权限问题")
                    .popover(isPresented: $showingPermissionTroubleshooting, arrowEdge: .trailing) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("权限问题排查")
                                .font(.headline)
                            
                            Text("如果系统设置已开启权限但这里仍显示未授权，请先重新启动。若更新过应用且问题持续，请从系统设置移除旧的 macTilt Duo 条目，再添加当前应用。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Button("重新启动应用") {
                                    ScreenCapture.shared.relaunchApp()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                
                                Button(copiedResetCommand ? "已复制" : "复制重置命令") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(resetCommand, forType: .string)
                                    copiedResetCommand = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        copiedResetCommand = false
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Text(resetCommand)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(14)
                        .frame(width: 300)
                    }
                }
            }

            // Honest first-run state: with the grant missing the fold is
            // deliberately inert (see OverlayWindowController.effectPermitted),
            // so say so rather than letting the user read the silence as a bug.
            if !settings.hasScreenRecordingPermission {
                Text("使用实时桌面捕获时，授权后才会显示合盖效果。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - Battery & Power Optimization Card
    private var batteryCard: some View {
        HCISectionCard(title: "耗电与性能", icon: "battery.100.bolt") {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                
                Text("闲置时暂停渲染")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.green)
                
                InfoButton("节能说明", content: "没有合盖动画时，Metal 渲染暂停，铰链传感器以较低频率读取。检测到合盖动作后准备桌面捕获，并按需恢复渲染。")
                
                Spacer()
                
                Text(settings.isScreenCaptureDormant ? "已暂停" : "准备捕获")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
            }
        }
    }
    
    // MARK: - Tilt Triggers Card
    private var tiltCard: some View {
        HCISectionCard(title: "合盖触发角度", icon: "angle") {
            VStack(spacing: 12) {
                // Start Angle Slider Row
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("动画起始角度")
                            .font(.subheadline)
                        
                        InfoButton("起始角度", content: "屏幕角度高于此值时正常显示；合盖到低于此值时开始动画。")
                        
                        Spacer()
                        
                        Text("\(Int(settings.startTiltAngle))°")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.startTiltAngle, in: 40...120, step: 1)
                }
                
                Divider()
                
                // End Angle Slider Row
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("完全合拢角度")
                            .font(.subheadline)
                        
                        InfoButton("完全合拢角度", content: "动画随着合盖逐渐变化，到达此角度时画面完全变黑。")
                        
                        Spacer()
                        
                        Text("\(Int(settings.endTiltAngle))°")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.endTiltAngle, in: 0...20, step: 1)
                }

                Divider()

                // Auto-release Row (issue #9)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("停止移动后恢复桌面")
                            .font(.subheadline)

                        InfoButton("停止移动后恢复桌面", content: "屏幕停止移动一段时间后，自动结束效果并恢复正常桌面，方便在半开角度继续使用。再次移动屏幕时重新显示合盖效果。")

                        Spacer()

                        Toggle("", isOn: $settings.autoReleaseFold)
                            .labelsHidden()
                    }

                    if settings.autoReleaseFold {
                        HStack(spacing: 8) {
                            Text("等待")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Slider(value: $settings.autoReleaseDelay, in: 0.3...3.0, step: 0.1)

                            Text(String(format: "%.1f 秒", settings.autoReleaseDelay))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Clamshell Opening Animation Card (Macs without continuous LAS)
    private var clamshellOpeningCard: some View {
        HCISectionCard(title: "无角度传感器的开盖动画", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                Text("部分机型（如 13 英寸 M1 MacBook Pro）只能检测开盖或合盖状态，无法连续读取角度。应用会在开盖唤醒时播放预设时长的展开动画。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("开盖动画时长")
                            .font(.subheadline)
                        
                        InfoButton("开盖动画时长", content: "调整开盖动画的播放时长，选择轻快、自然或舒缓的节奏。")
                        
                        Spacer()
                        
                        Text(String(format: "%.2f 秒", settings.clamshellOpeningDuration))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    
                    Slider(value: $settings.clamshellOpeningDuration, in: 0.4...2.5, step: 0.05)
                        .tint(Color.accentColor)
                    
                    HStack {
                        Text("轻快（0.6 秒）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("自然（0.95 秒）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("舒缓（2.0 秒）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                HStack(spacing: 8) {
                    Button(action: {
                        settings.clamshellOpeningDuration = 0.60
                        LidSensor.shared.triggerOpeningPreview()
                    }) {
                        Text("轻快")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        settings.clamshellOpeningDuration = 0.95
                        LidSensor.shared.triggerOpeningPreview()
                    }) {
                        Text("自然")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        settings.clamshellOpeningDuration = 1.60
                        LidSensor.shared.triggerOpeningPreview()
                    }) {
                        Text("舒缓")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button(action: {
                        LidSensor.shared.triggerOpeningPreview()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("预览开盖动画")
                        }
                        .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    // MARK: - Display Source & Menu Bar Card
    private var displaySourceCard: some View {
        HCISectionCard(title: "显示与菜单栏", icon: "display") {
            VStack(spacing: 12) {
                // Display Source Picker Row
                HStack {
                    Text("画面来源")
                        .font(.subheadline)
                    
                    InfoButton("画面来源", content: "选择实时桌面捕获、当前桌面壁纸、内置图片或自选图片。")
                    
                    Spacer()
                    
                    Picker("", selection: $settings.imageSourceMode) {
                        ForEach(ImageSourceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }
                
                if settings.imageSourceMode == .customImage {
                    HStack {
                        Text(settings.customImagePath.isEmpty ? "尚未选择图片" : (settings.customImagePath as NSString).lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("选择图片…") {
                            selectCustomImage()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                if settings.isHardwareSensor {
                    Divider()
                    
                    // Menu Bar Toggle Row
                    HStack {
                        Text("菜单栏显示铰链角度")
                            .font(.subheadline)
                        
                        InfoButton("菜单栏角度", content: "在菜单栏图标旁显示实时铰链角度，例如 120°。")
                        
                        Spacer()
                        
                        Toggle("", isOn: $settings.showAngleInMenuBar)
                            .labelsHidden()
                            .disabled(settings.hideMenuBarIcon)
                    }
                }
                
                Divider()
                
                // Hide Status Icon Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("隐藏菜单栏图标")
                            .font(.subheadline)
                        Text("重新打开 macTilt 即可返回设置。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    InfoButton("隐藏菜单栏图标", content: "隐藏菜单栏图标后，应用与合盖动画仍会运行。重新打开 macTilt 即可进入设置。")
                    
                    Spacer()
                    
                    Toggle("", isOn: $settings.hideMenuBarIcon)
                        .labelsHidden()
                }
            }
        }
    }
    
    // MARK: - Animation Physics Card
    private var animationPhysicsCard: some View {
        HCISectionCard(title: "动画效果", icon: "slider.horizontal.3") {
            VStack(spacing: 12) {
                Picker("效果模式", selection: $settings.useDuoProjection) {
                    Text("DuoLikeAnimation · 磨砂玻璃").tag(true)
                    Text("macTilt · 原版").tag(false)
                }
                if settings.useDuoProjection {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "观看距离：屏幕高度的 %.1f 倍", settings.eyeDistance))
                            .font(.subheadline)
                        Slider(value: $settings.eyeDistance, in: 1.1...5.0, step: 0.1)
                        Text("以屏幕底边为转轴，按你的坐姿调整观看距离。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                // Follow Speed
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("角度跟随速度")
                            .font(.subheadline)
                        
                        InfoButton(
                            "角度跟随速度",
                            content: "控制动画跟随屏幕角度的速度。数值越低，过渡越柔和；越高，响应越及时。",
                            demoLabel: "预览跟随效果",
                            demo: { demoFold(0.7, animated: false) }
                        )
                        
                        Spacer()
                        
                        Text(String(format: "%.0f", settings.followSpeed))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.followSpeed, in: 6...30, step: 1)
                }
                
                Divider()
                
                // Blur and Specular Dual Sliders
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("虚化强度")
                                .font(.subheadline)
                            InfoButton(
                                "虚化强度",
                                content: "磨砂玻璃模式按屏幕与原画面的间距计算散射；macTilt 原版使用高斯虚化，并随运动速度增强。磨砂玻璃模式设为 0 时关闭虚化。",
                                demoLabel: "预览合盖 55%",
                                demo: { demoFold(0.55) }
                            )
                            Spacer()
                            Text(String(format: "%.1f 倍", settings.blurStrength))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.blurStrength, in: 0.0...2.0, step: 0.1)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("玻璃反光")
                                .font(.subheadline)
                            InfoButton(
                                "玻璃反光",
                                content: "屏幕倾斜时，加入一条柔和的冷白色高光，模拟光照在玻璃上的反射。默认值 0 表示关闭。",
                                demoLabel: "预览合盖 75%",
                                demo: { demoFold(0.75) }
                            )
                            Spacer()
                            Text(String(format: "%.1f 倍", settings.reflectionIntensity))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.reflectionIntensity, in: 0.0...2.5, step: 0.1)
                    }
                }
                
                Divider()
                
                // Side Blackout — horizontal parallax void
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("两侧暗边")
                            .font(.subheadline)
                        InfoButton(
                            "两侧暗边",
                            content: "控制合盖时画面两侧的黑色区域。0% 保持原画面宽度，100% 对应物理投影，数值越大，两侧暗边越明显。",
                            demoLabel: "预览合盖 75%",
                            demo: { demoFold(0.75) }
                        )
                        Spacer()
                        Text("\(Int(settings.sideVoidAmount * 100))%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.sideVoidAmount, in: 0.0...2.0, step: 0.05)
                }
            }
        }
    }
    
    // MARK: - Lock Screen & Sleep Wake Card (Optional)
    private var lockScreenCard: some View {
        HCISectionCard(title: "锁屏与唤醒", icon: "lock.shield") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("提高显示层级")
                            .font(.subheadline)
                        Text("尝试在唤醒过渡期间显示动画。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    InfoButton("锁屏唤醒效果", content: "此实验功能沿用上游的私有 SkyLight 接口，本地整合版默认关闭。正常桌面的合盖效果无需开启此项。")
                    
                    Spacer()
                    
                    Toggle("", isOn: $settings.enableLockScreenPriority)
                        .labelsHidden()
                }
            }
        }
    }
    
    // MARK: - Test Preview Card
    private var testPreviewCard: some View {
        HCISectionCard(title: "交互预览", icon: "play.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("预览动画")
                        .font(.subheadline)
                    
                    InfoButton("交互预览", content: "拖动滑块预览合盖效果，无需移动屏幕。松开滑块后自动恢复桌面。")
                    
                    Spacer()
                    
                    Toggle("", isOn: $settings.isTestModeActive)
                        .labelsHidden()
                        .onChange(of: settings.isTestModeActive) { _, newValue in
                            if !newValue {
                                // Immediately clear turn value so the overlay hides at once
                                settings.testTurnValue = 0.0
                            }
                        }
                }
                
                if settings.isTestModeActive {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("合盖进度")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(settings.testTurnValue * 100))%")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.testTurnValue, in: 0.0...1.0) { isEditing in
                            if isEditing {
                                settings.isTestModeActive = true
                                OverlayWindowController.shared.captureScreenAsync()
                            } else {
                                // Stop the overlay on screen as soon as the user leaves the slider
                                withAnimation(.easeOut(duration: 0.25)) {
                                    settings.testTurnValue = 0.0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    if settings.testTurnValue == 0.0 {
                                        settings.isTestModeActive = false
                                        OverlayWindowController.shared.stopOverlay()
                                    }
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }
    
    // MARK: - Software Updates Card
    private var softwareUpdateCard: some View {
        HCISectionCard(title: "软件更新", icon: "arrow.triangle.2.circlepath.circle") {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前版本：v\(updater.currentVersion)（构建 \(updater.currentBuild)）")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if updater.isChecking {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在检查 GitHub 更新…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if updater.updateAvailable {
                            Text("发现新版本：\(updater.latestVersion)")
                                .font(.caption)
                                .foregroundStyle(Color.green)
                                .fontWeight(.semibold)
                        } else if updater.hasChecked {
                            Text(updater.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("本地整合版不自动更新，上游发行版不包含整合修改。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        updater.checkForUpdates(userInitiated: true)
                    }) {
                        HStack(spacing: 4) {
                            if updater.isChecking {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("检查更新")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(updater.isChecking)
                }
                
                if updater.updateAvailable {
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(updater.latestVersion) 可以安装")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("从 GitHub Releases 下载最新的通用版 DMG 安装包。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("下载更新（.dmg）") {
                            updater.openLatestRelease()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                
                Divider()
                
                Toggle(isOn: $settings.automaticallyCheckForUpdates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动检查更新")
                            .font(.subheadline)
                        Text("启动时在后台检查 GitHub 发行版；本地整合版已停用此功能。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }
    
    // MARK: - Bottom Footer Bar
    private var footerBar: some View {
        HStack {
            Button("恢复默认设置") {
                settings.startTiltAngle = 115.0
                settings.endTiltAngle = 3.0
                settings.followSpeed = 16.0
                settings.imageSourceMode = .liveCapture
                settings.blurStrength = 0.5
                settings.reflectionIntensity = 0.0
                settings.useDuoProjection = true
                settings.eyeDistance = 2.5
                settings.sideVoidAmount = 1.0
                settings.showAngleInMenuBar = true
                settings.isTestModeActive = false
                settings.testTurnValue = 0.0
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            
            Button("使用引导") {
                MenuBarController.shared.openOnboardingWindow()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            
            Spacer()
            
            Button("完成") {
                settings.isTestModeActive = false
                settings.testTurnValue = 0.0
                OverlayWindowController.shared.stopOverlay()
                NSApp.keyWindow?.orderOut(nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
        }
    }
    
    /// Live demonstration: shows the fullscreen fold at a representative
    /// progress for a few seconds, then eases out. The popover closes first
    /// so the demo is visible (the overlay covers all windows).
    private func demoFold(_ turn: Double, animated: Bool = true) {
        demoToken += 1
        let token = demoToken
        settings.isTestModeActive = true
        OverlayWindowController.shared.captureScreenAsync()
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                settings.testTurnValue = turn
            }
        } else {
            settings.testTurnValue = turn
        }
        let capturedSettings = settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            guard token == self.demoToken else { return }
            withAnimation(.easeOut(duration: 0.5)) {
                capturedSettings.testTurnValue = 0.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard token == self.demoToken else { return }
                if capturedSettings.testTurnValue == 0.0 {
                    capturedSettings.isTestModeActive = false
                    OverlayWindowController.shared.stopOverlay()
                }
            }
        }
    }

    private func selectCustomImage() {
        let panel = NSOpenPanel()
        panel.title = "选择用于合盖动画的图片"
        panel.prompt = "选择图片"
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.customImagePath = url.path
        }
    }
}

// MARK: - Apple HCI Grouped Section Card Component
private struct HCISectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Card Title Label
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 2)
            
            // Card Content Container
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(cardBorder, lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Apple HCI Info Popover Button
private struct InfoButton: View {
    let title: String
    let content: String
    var demoLabel: String? = nil
    var demo: (() -> Void)? = nil
    @State private var isShowing: Bool = false

    init(_ title: String = "", content: String, demoLabel: String? = nil, demo: (() -> Void)? = nil) {
        self.title = title
        self.content = content
        self.demoLabel = demoLabel
        self.demo = demo
    }

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.isEmpty ? "说明" : "\(title)说明")
        .popover(isPresented: $isShowing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                if !title.isEmpty {
                    Text(title)
                        .font(.headline)
                }
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                if let demoLabel, let demo {
                    Button {
                        isShowing = false
                        demo()
                    } label: {
                        Label(demoLabel, systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .frame(width: 280)
        }
    }
}
