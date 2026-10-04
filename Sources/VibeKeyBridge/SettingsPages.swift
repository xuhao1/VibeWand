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
                        SettingsNote(text: tr("切换立即生效，保留你的设备与按键配置。", "Switch instantly. Your device and button settings stay in place."))
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
                                SettingsNote(text: tr("为按键设置“听写（按住 Fn）”动作。", "Assign the “Dictation (hold Fn)” action to a button."))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                        Text(model.template.audioNote).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                        SettingsNote(text: tr("使用系统或输入法所选音源。VibeWand 不录音，也不上传聊天内容。", "Uses the audio source selected by your system or input method. VibeWand does not record audio or upload conversations."))
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

struct OverlaySettings: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var preview: NSImage?
    @State private var previewTask: Task<Void, Never>?
    @AppStorage("hudScale") private var scale = 1.0
    @AppStorage("hudOpacity") private var opacity = 0.95
    @AppStorage("hudExpanded") private var expanded = false

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
                        SettingsToggleRow(title: tr("展开按键说明", "Show button guide"), isOn: Binding(get: { expanded }, set: {
                            expanded = $0; model.overlay.setExpanded($0); model.refresh(); refreshPreview()
                        }))
                        SettingsNote(text: tr("在面板旁显示当前按键功能。", "Show the current button actions beside the device."))
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
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor))
                            if let preview {
                                Image(nsImage: preview).resizable().scaledToFit()
                                    .frame(width: min(preview.size.width, geometry.size.width - 24), height: min(preview.size.height, geometry.size.height - 24))
                                    .opacity(opacity)
                                    .shadow(color: .black.opacity(0.13), radius: 12, y: 4)
                            } else {
                                Label(tr("预览加载中", "Loading preview"), systemImage: "macwindow").font(.callout).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.frame(height: 360)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(expanded ? tr("带按键说明", "With button guide") : tr("紧凑面板", "Compact overlay"))
                                .font(.system(size: 14, weight: .medium))
                            SettingsNote(text: tr("跟随外观设置更新；可刷新当前动作。", "Updates with appearance settings. Refresh to show the current action."))
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
            .onDisappear { previewTask?.cancel() }
    }

    private func rangeLabels(_ low: String, _ high: String) -> some View {
        HStack { Text(low); Spacer(); Text(high) }.font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, -6)
    }

    private func refreshPreview() {
        // Capture only on appearance edits or explicit refresh, never on the runtime's status polling.
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            // Coalesce slider updates and let AppKit finish resizing before drawing the preview.
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            preview = model.overlay.previewImage(appearance: NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua))
        }
    }
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
                        Divider()
                        Label(tr("不包含聊天正文、音频或凭证。", "Excludes conversation text, audio and credentials."), systemImage: "lock")
                            .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
        StandardPage(title: tr("关于 VibeWand", "About VibeWand"), subtitle: tr("用手中的实体控制器，连接你的日常工作。", "Connect the controls in your hand to your everyday workflow.")) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    SettingsCard(title: tr("把操作握在手中", "Your controls. Your flow.")) {
                        HStack(spacing: 14) {
                            BrandMark(size: 62)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("VibeWand").font(.system(size: 25, weight: .bold, design: .rounded))
                                Text(tr("版本 ", "Version ") + version).font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                        Text(tr("旋转浏览、按键切换、按住听写。为 AI、浏览器和日常沟通设计，也为你的操作习惯留出空间。", "Browse, switch and dictate with the controls in your hand. Built for AI, browsers and everyday conversations, with room to make it yours."))
                            .font(.system(size: 15)).lineSpacing(4).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Divider()
                        HStack(spacing: 7) {
                            aboutTag("macOS", symbol: "macwindow")
                            aboutTag(tr("源码公开", "Source available"), symbol: "curlybraces")
                            aboutTag(tr("非商用", "Noncommercial"), symbol: "doc.text")
                        }
                    }
                    SettingsCard(title: tr("在本机运行", "Runs on your Mac")) {
                        Label(tr("设备输入、手势和配置均在本机处理。", "Device input, gestures and settings are processed locally."), systemImage: "desktopcomputer")
                            .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                        SettingsNote(text: tr("VibeWand 不录音，也不上传聊天内容。听写使用系统或输入法提供的服务。", "VibeWand does not record audio or upload conversations. Dictation uses the service provided by your system or input method."))
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(spacing: 16) {
                    SettingsCard(title: tr("作者", "Created by")) {
                        HStack(alignment: .top, spacing: 12) {
                            SettingsIcon(symbol: "person.crop.circle", tint: .accentColor)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(tr("徐浩博士", "Dr. Hao Xu")).font(.system(size: 21, weight: .semibold))
                                Text(tr("南京大学", "Nanjing University")).font(.system(size: 15))
                                Text(tr("准聘（Tenure-track）副教授", "Tenure-track Associate Professor"))
                                    .font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.vertical, 4)
                    }
                    SettingsCard(title: tr("了解更多", "Find out more")) {
                        websiteRow(tr("个人主页", "Personal website"), host: "xuhao1.me", symbol: "person.crop.circle", url: "http://xuhao1.me")
                        Divider()
                        websiteRow(tr("项目主页", "Project website"), host: "vibewand.xuhao1.me", symbol: "globe", url: "https://vibewand.xuhao1.me")
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Text(tr("按键布局与动作编辑方式参考 Steam Input。VibeWand 源码公开，允许个人非商用使用；商用必须联系作者徐浩并取得授权。", "The layout and action editors are inspired by Steam Input. VibeWand is source-available for personal noncommercial use. Commercial use requires contacting Hao Xu for authorization."))
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func aboutTag(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
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

private struct SettingsNote: View {
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
