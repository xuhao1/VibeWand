import AppKit
import SwiftUI
import AU05Device

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

struct GeneralSettings: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var localization = L10n.shared

    var body: some View {
        StandardPage(title: tr("通用", "General"), subtitle: tr("语言、权限与当前工作状态。", "Language, permissions and your current setup.")) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    SettingsCard(title: tr("界面语言", "Interface language")) {
                        Picker("Language / 语言", selection: $localization.language) {
                            ForEach(AppLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                        SettingsNote(text: tr("切换语言后立即生效。", "Language changes take effect immediately."))
                    }
                    SettingsCard(title: tr("辅助功能权限", "Accessibility access")) {
                        HStack(alignment: .top, spacing: 12) {
                            SettingsIcon(symbol: model.runtime.adapter.trusted ? "checkmark.shield" : "lock.shield", tint: model.runtime.adapter.trusted ? .green : .orange)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.runtime.adapter.trusted ? tr("已授权", "Access enabled") : tr("需要授权", "Access required"))
                                    .font(.system(size: 16, weight: .semibold))
                                SettingsNote(text: tr("用于识别当前应用，并将设备动作发送给它。", "Allows VibeWand to recognize the active app and send your controls to it."))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                        HStack {
                            Text(tr("在 macOS 系统设置中管理", "Manage in macOS System Settings"))
                                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button(tr("打开设置…", "Open settings…"), action: model.accessibility).fixedSize()
                        }
                    }
                    SettingsCard(title: tr("配置你的工作流", "Set up your workflow")) {
                        SettingsNavigationRow(symbol: "gamecontroller", title: tr("设备与按键", "Devices & inputs"), detail: tr("选择布局，配置按键与摇杆。", "Choose a layout and map buttons and sticks.")) { model.section = .devices }
                        Divider()
                        SettingsNavigationRow(symbol: "square.grid.2x2", title: tr("应用适配", "Applications"), detail: tr("管理浏览器、聊天工具与自定义应用。", "Configure browsers, chat tools and custom apps.")) { model.section = .applications }
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(spacing: 16) {
                    SettingsCard(title: tr("当前状态", "Current status")) {
                        HStack(spacing: 10) {
                            Circle().fill(model.snapshot.connected ? Color.green : Color.orange).frame(width: 8, height: 8)
                            Text(model.snapshot.connected ? tr("设备已连接", "Device connected") : tr("等待设备连接", "Waiting for a device"))
                                .font(.system(size: 16, weight: .semibold))
                            Spacer(minLength: 0)
                        }
                        Divider()
                        SettingsValueRow(label: tr("当前布局", "Layout"), value: model.template.title)
                        SettingsValueRow(label: tr("设备", "Device"), value: model.runtime.deviceName)
                        SettingsValueRow(label: tr("前台应用", "Active app"), value: model.snapshot.target)
                        SettingsValueRow(label: tr("运行模式", "Run mode"), value: model.snapshot.captureOnly ? tr("只采集物理事件", "Capture only") : model.snapshot.demo ? tr("演示模式", "Demo") : tr("实时控制", "Live control"))
                    }
                    SettingsCard(title: tr("语音听写", "Dictation")) {
                        HStack(alignment: .top, spacing: 12) {
                            SettingsIcon(symbol: "waveform", tint: .accentColor)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(tr("按住说话，松开结束", "Hold to speak. Release to finish."))
                                    .font(.system(size: 16, weight: .semibold))
                                SettingsNote(text: tr("为按键设置“听写（按住说话）”动作。", "Assign the “Dictation (hold to speak)” action to a button."))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                        SettingsNavigationRow(symbol: "waveform", title: tr("语音输入", "Voice input"), detail: tr("选择外置输入法、系统听写或语音 API。", "Choose an external input method, macOS dictation or a speech API.")) { model.section = .speech }
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

struct OverlaySettings: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hudScale") private var scale = 1.0
    @AppStorage("hudOpacity") private var opacity = 0.95
    @AppStorage("hudExpanded") private var expanded = false
    @AppStorage("hudDisplayMode") private var displayMode = "full"

    var body: some View {
        StandardPage(title: tr("悬浮面板", "Overlay"), subtitle: tr("调整显示、大小和透明度，预览实际面板。", "Adjust visibility, size and opacity with a preview of your overlay.")) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    SettingsCard(title: tr("显示", "Visibility")) {
                        SettingsToggleRow(title: tr("显示悬浮面板", "Show overlay"), isOn: Binding(get: { model.overlay.isVisible }, set: {
                            model.overlay.setVisible($0); UserDefaults.standard.set($0, forKey: "hudVisible"); model.refresh(); refreshPreview()
                        }))
                        SettingsNote(text: tr("保持在应用上方，不占用输入焦点。", "Stays above your apps without taking keyboard focus."))
                        Divider()
                        Picker(tr("悬浮窗模式", "Overlay mode"), selection: Binding(get: { displayMode }, set: {
                            displayMode = $0; model.overlay.setDisplayMode(OverlayDisplayMode(rawValue: $0) ?? .full); model.refresh()
                        })) {
                            ForEach(OverlayDisplayMode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }.pickerStyle(.segmented).labelsHidden()
                        SettingsNote(text: tr("小条保留语音状态、实时文字和原词／自动整理开关。隐藏由上方开关独立控制。", "The compact bar keeps voice status, live text and verbatim / polish controls. Visibility is a separate switch."))
                        Divider()
                        SettingsToggleRow(title: tr("显示更多手势", "Show additional gestures"), isOn: Binding(get: { expanded }, set: {
                            expanded = $0; model.overlay.setExpanded($0); model.refresh(); refreshPreview()
                        }))
                        SettingsNote(text: tr("补充双击和长按提示。", "Include double-press and long-press hints."))
                    }
                    SettingsCard(title: tr("外观", "Appearance")) {
                        HStack {
                            Text(tr("大小", "Size")); Spacer()
                            Text(scale, format: .percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(.secondary)
                        }.font(.system(size: 14))
                        Slider(value: Binding(get: { scale }, set: { scale = $0; model.overlay.setScale($0); model.refresh(); refreshPreview() }), in: 0.65...1.8)
                            .accessibilityLabel(tr("面板大小", "Overlay size"))
                        rangeLabels("65%", "180%")
                        Divider()
                        HStack {
                            Text(tr("透明度", "Opacity")); Spacer()
                            Text(opacity, format: .percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(.secondary)
                        }.font(.system(size: 14))
                        Slider(value: Binding(get: { opacity }, set: { opacity = $0; model.overlay.setOpacity($0); model.refresh() }), in: 0.35...1)
                            .accessibilityLabel(tr("面板透明度", "Overlay opacity"))
                        rangeLabels("35%", "100%")
                    }
                    SettingsCard(title: tr("位置与导出", "Position & export")) {
                        SettingsNote(text: tr("拖动面板即可移动。齿轮打开设置，× 隐藏面板；可从菜单栏重新显示。", "Drag to move. The gear opens settings; × hides the overlay. Show it again from the menu bar."))
                        HStack(spacing: 10) {
                            Button(tr("重置位置", "Reset position")) { model.overlay.resetPosition() }
                            Button(tr("导出图片…", "Export image…"), action: model.exportImage)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                SettingsCard(title: tr("面板预览", "Overlay preview")) {
                    GeometryReader { geometry in
                        let size = SpeechOverlayLayout.size(template: model.snapshot.deviceTemplate, expanded: expanded,
                            mode: OverlayDisplayMode(rawValue: displayMode) ?? .full, voice: model.snapshot.voice)
                        let fit = min((geometry.size.width - 28) / size.width, (geometry.size.height - 28) / size.height)
                        ZStack {
                            OverlayPreviewBackdrop()
                            OverlayLivePreview(snapshot: model.snapshot, expanded: expanded, opacity: opacity, mode: OverlayDisplayMode(rawValue: displayMode) ?? .full)
                                .frame(width: size.width * fit, height: size.height * fit)
                                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.frame(height: expanded ? 510 : 475)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(expanded ? tr("完整手势提示", "Full gesture guide") : tr("核心按键提示", "Core button guide"))
                                .font(.system(size: 14, weight: .medium))
                            SettingsNote(text: tr("与悬浮窗共用真实组件，实时显示按键与玻璃效果。", "The actual overlay component, with live button feedback and glass."))
                        }
                        Spacer(minLength: 8)
                        Button(action: refreshPreview) { Image(systemName: "arrow.clockwise") }
                            .help(tr("刷新预览", "Refresh preview")).accessibilityLabel(tr("刷新预览", "Refresh preview"))
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }.task { refreshPreview() }
            .onChange(of: colorScheme) { _ in refreshPreview() }
            .onChange(of: model.snapshot.deviceTemplate) { _ in refreshPreview() }
    }

    private func rangeLabels(_ low: String, _ high: String) -> some View {
        HStack { Text(low); Spacer(); Text(high) }.font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, -6)
    }

    private func refreshPreview() { model.refresh() }
}

struct DeveloperSettings: View {
    @ObservedObject var model: SettingsModel
    private var mode: String { model.runtime.captureOnly ? "capture" : model.runtime.demo ? "demo" : "live" }

    var body: some View {
        StandardPage(title: tr("开发者工具", "Developer tools"), subtitle: tr("检查输入、预览交互与诊断应用兼容性。", "Inspect input, preview interactions and diagnose app compatibility.")) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    SettingsCard(title: tr("运行模式", "Run mode")) {
                        VStack(spacing: 8) {
                            modeOption("live", title: tr("实时控制", "Live control"), detail: tr("按前台应用和当前场景执行设备动作。", "Send device actions to the active app and context."), symbol: "cursorarrow.click")
                            modeOption("demo", title: tr("演示模式", "Demo"), detail: tr("使用模拟会话，可点击浮窗体验交互。", "Explore simulated conversations using the overlay."), symbol: "play.rectangle")
                            modeOption("capture", title: tr("只采集物理事件", "Capture only"), detail: tr("只显示设备输入，不读取应用或发送操作。", "Inspect device input without reading apps or sending actions."), symbol: "waveform.path")
                        }
                        Divider()
                        Button { model.runtime.captureOnly = false; model.runtime.playDemo(); model.refresh() } label: {
                            Label(tr("播放自动演示", "Play automatic demo"), systemImage: "play.fill")
                        }
                    }
                    SettingsCard(title: tr("兼容性", "Compatibility")) {
                        SettingsToggleRow(title: tr("选择器快捷键兼容模式", "Picker compatibility mode"), isOn: Binding(get: { model.runtime.adapter.compatibilityPicker }, set: { model.runtime.adapter.compatibilityPicker = $0; UserDefaults.standard.set($0, forKey: "compatibilityPicker"); model.refresh() }))
                        Divider()
                        SettingsToggleRow(title: tr("输入框识别兼容模式", "Editor detection compatibility"), isOn: Binding(get: { model.runtime.adapter.forceEditing }, set: { model.runtime.adapter.forceEditing = $0; UserDefaults.standard.set($0, forKey: "forceEditing"); model.refresh() }))
                        SettingsNote(text: tr("适用于未完整提供辅助功能信息的应用。", "For apps that expose incomplete Accessibility information."))
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(spacing: 16) {
                    SettingsCard(title: tr("输入与执行状态", "Input & execution")) {
                        HStack {
                            Label(tr("当前状态", "Current state"), systemImage: "waveform.path.ecg")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(tr("持续更新", "Updating")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        }
                        Text(model.snapshot.status).font(.system(size: 14)).lineSpacing(3).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12).frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        SettingsValueRow(label: tr("设备", "Device"), value: model.runtime.deviceName)
                        SettingsValueRow(label: tr("连接", "Connection"), value: model.snapshot.connected ? tr("已连接", "Connected") : tr("未连接", "Disconnected"))
                        SettingsValueRow(label: tr("当前场景", "Context"), value: model.snapshot.mode)
                        Divider()
                        Text(tr("最近动作", "Latest action")).font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(model.snapshot.action).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    SettingsCard(title: tr("诊断工具", "Diagnostics")) {
                        SettingsNote(text: tr("导出当前状态以排查问题，或重新建立设备连接。", "Export the current state for troubleshooting, or reconnect the device."))
                        HStack(spacing: 10) {
                            Button(tr("导出诊断…", "Export diagnostics…"), action: model.exportDiagnostics)
                            Button(tr("重新连接", "Reconnect")) { model.runtime.reconnectDevice(); model.refresh() }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func modeOption(_ value: String, title: String, detail: String, symbol: String) -> some View {
        Button {
            model.runtime.captureOnly = value == "capture"
            model.runtime.demo = value == "demo"
            model.refresh()
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(mode == value ? Color.accentColor : .secondary).frame(width: 20).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: mode == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(mode == value ? Color.accentColor : Color.primary.opacity(0.2))
                    .font(.system(size: 16)).padding(.top, 1)
            }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                .background(mode == value ? Color.accentColor.opacity(0.07) : Color(nsColor: .windowBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(mode == value ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.04)))
        }.buttonStyle(.plain).accessibilityAddTraits(mode == value ? .isSelected : [])
    }
}

struct AboutSettings: View {
    private var version: String { SettingsStyle.version }

    var body: some View {
        StandardPage(title: tr("关于 VibeWand", "About VibeWand"), subtitle: tr("版本、作者与项目链接。", "Version, author and project links.")) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    SettingsCard(title: tr("应用信息", "App information")) {
                        HStack(spacing: 14) {
                            BrandMark(size: 62)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("VibeWand").font(.system(size: 25, weight: .bold, design: .rounded))
                                Text(tr("版本 ", "Version ") + version).font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                        Text(tr("旋转浏览、按键切换、按住听写。", "Turn to browse, press to switch, hold to dictate."))
                            .font(.system(size: 15)).lineSpacing(4).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Divider()
                        SettingsValueRow(label: tr("使用许可", "Usage license"), value: tr("个人非商用", "Personal noncommercial use"))
                        SettingsNote(text: tr("商用请联系作者取得授权。", "Contact the author for commercial authorization."))
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(spacing: 16) {
                    SettingsCard(title: tr("作者", "Created by")) {
                        HStack(alignment: .top, spacing: 12) {
                            SettingsIcon(symbol: "person.crop.circle", tint: .accentColor)
                            Text("Dr. Xu").font(.system(size: 21, weight: .semibold))
                        }.padding(.vertical, 4)
                    }
                    SettingsCard(title: tr("了解更多", "Find out more")) {
                        websiteRow(tr("个人主页", "Personal website"), host: "xuhao1.me", symbol: "person.crop.circle", url: "http://xuhao1.me")
                        Divider()
                        websiteRow(tr("项目主页", "Project website"), host: "vibewand.xuhao1.me", symbol: "globe", url: "https://vibewand.xuhao1.me")
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }

        }
    }

    private func websiteRow(_ title: String, host: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18)).frame(width: 23)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                    Text(host).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 13)).foregroundStyle(.secondary)
            }.padding(.vertical, 3).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct SettingsIcon: View {
    let symbol: String
    var tint: Color = .accentColor
    var body: some View {
        Image(systemName: symbol).font(.system(size: 22, weight: .regular)).foregroundStyle(tint)
            .frame(width: 42, height: 42).background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 14) {
            Text(title).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).accessibilityLabel(title)
        }
    }
}

struct SettingsNote: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsValueRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label).foregroundStyle(.secondary).fixedSize()
            Spacer(minLength: 0)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 14))
    }
}

private struct SettingsNavigationRow: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Color.accentColor).frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                    SettingsNote(text: detail)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
