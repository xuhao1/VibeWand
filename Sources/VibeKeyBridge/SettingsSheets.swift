import AppKit
import SwiftUI
import AU05Device

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

struct ActionLibrary: View {
    @ObservedObject var model: SettingsModel
    let request: GestureEditRequest
    @Environment(\.dismiss) private var dismiss
    @State private var category = ActionCategory.application
    @State private var search = ""
    private var current: GestureAction { model.config.action(model.scope, request.control, request.kind) }
    private var inherited: GestureAction { model.inherited(request.control, request.kind) }
    private var actions: [GestureAction] {
        GestureAction.allCases.filter {
            $0.category == category && (search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.label.localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: tr("选择动作", "Choose an action"),
                         subtitle: "\(model.selected.title) · \(model.gestureTitle(request.kind)) · \(model.scope.label)")
                .padding(20)
                .background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Color.accentColor).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(tr("当前动作", "Current action")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            SheetBadge(text: model.isInherited(request.control, request.kind) ? tr("沿用默认", "Default") : tr("自定义", "Custom"))
                        }
                        Text(current.label).font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    .settingsGlass(cornerRadius: 10)
                Picker(tr("功能分类", "Action category"), selection: $category) {
                    ForEach(ActionCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(tr("搜索此分类中的动作", "Search this category"), text: $search).textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).help(tr("清除搜索", "Clear search"))
                            .accessibilityLabel(tr("清除搜索", "Clear search"))
                    }
                }.font(.system(size: 15)).padding(.horizontal, 11).padding(.vertical, 9)
                    .settingsGlass(cornerRadius: 8, prominent: true)
                ScrollView {
                    if actions.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                            Text(tr("没有匹配的动作", "No matching actions")).font(.system(size: 15, weight: .semibold))
                            Text(tr("换一个关键词，或选择其他功能分类。", "Try another search or choose a different category."))
                                .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).frame(height: 236)
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(actions, id: \.self) { action in
                                Button {
                                    model.setAction(action, control: request.control, kind: request.kind); dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(action.label).font(.system(size: 15)).multilineTextAlignment(.leading)
                                        Spacer(minLength: 6)
                                        if action == inherited { SheetBadge(text: tr("默认", "Default")) }
                                        Image(systemName: current == action ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 16)).foregroundStyle(current == action ? Color.accentColor : Color.primary.opacity(0.15))
                                    }.padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity, minHeight: 42)
                                        .background(current == action ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                        .settingsGlass(cornerRadius: 8)
                                        .contentShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                                    .accessibilityAddTraits(current == action ? .isSelected : [])
                            }
                        }.padding(.trailing, 2)
                    }
                }.frame(height: 264)
            }.padding(20)
            Divider()
            HStack(alignment: .center, spacing: 16) {
                Button {
                    model.setAction(nil, control: request.control, kind: request.kind); dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 15))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("恢复默认动作", "Use default action")).font(.system(size: 14, weight: .medium))
                            Text(inherited.label).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }.buttonStyle(.plain)
                Spacer(minLength: 8)
                Button(tr("完成", "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 20).padding(.vertical, 16)
                .background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
        }.frame(width: 600)
            .background { SettingsBackdrop(material: .sheet, blendingMode: .withinWindow) }
            .onAppear { category = current.category }
            .onExitCommand { dismiss() }
    }
}

struct TimingSettings: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: tr("手势时序", "Gesture timing"),
                         subtitle: model.template.title + tr(" · 更改即时保存到此模板", " · Changes save to this layout"))
                .padding(20)
                .background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                TimingSlider(title: tr("双击间隔", "Double-press interval"),
                             detail: tr("两次按下在此时间内算作双击。", "Two presses within this window count as a double press."),
                             value: Binding(get: { model.config.doubleClickInterval }, set: { model.setTiming(double: $0) }), range: 0.15...0.6, step: 0.01)
                Divider()
                TimingSlider(title: tr("长按时间", "Long-press duration"),
                             detail: tr("持续按住多久后触发长按。", "How long to hold before triggering a long press."),
                             value: Binding(get: { model.config.longPressInterval }, set: { model.setTiming(long: $0) }), range: 0.35...2, step: 0.05)
            }.padding(16).settingsGlass(cornerRadius: 10).padding(20)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").padding(.top, 1)
                Text(tr("单击会等待双击判定结束。长按时间始终晚于双击间隔。", "A single press waits for the double-press window. The long-press duration always exceeds that window."))
                    .fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 14)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 20)
            Divider()
            HStack {
                Label(tr("自动保存", "Saved automatically"), systemImage: "checkmark.circle").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Button(tr("完成", "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 20).padding(.vertical, 16)
                .background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
        }.frame(width: 520)
            .background { SettingsBackdrop(material: .sheet, blendingMode: .withinWindow) }
            .onExitCommand { dismiss() }
    }
}

private struct TimingSlider: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(String(format: "%.2f s", value)).font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.accentColor).frame(width: 68).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.08), in: Capsule())
            }
            Text(detail).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 3) {
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                    .accessibilityLabel(title)
                HStack {
                    Text(String(format: "%.2f s", range.lowerBound))
                    Spacer()
                    Text(String(format: "%.2f s", range.upperBound))
                }.font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }
}

struct ConnectionSettings: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.dismiss) private var dismiss
    private var readiness: DeviceTemplateReadiness { model.runtime.templates.readiness() }
    private var isController: Bool { model.template.id == .dualSense }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: tr("设备连接", "Device connection"),
                         subtitle: tr("为当前模板绑定设备，并了解麦克风支持。", "Connect this layout to your device and check microphone support."))
                .padding(20)
                .background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ZStack {
                        if let image = DeviceArtwork.forTemplate(model.template.id).image {
                            Image(nsImage: image).resizable().scaledToFit().padding(6)
                        }
                    }.frame(width: 96, height: 80).settingsGlass(cornerRadius: 10).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.template.title).font(.system(size: 18, weight: .semibold))
                        Label(model.snapshot.connected ? tr("设备已连接", "Device connected") : model.runtime.connectionSummary,
                              systemImage: model.snapshot.connected ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(model.snapshot.connected ? Color.green : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(model.snapshot.connected ? model.runtime.deviceName : readiness.label)
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 16) {
                    ConnectionDetail(title: tr("按键与连接", "Buttons & connection"), symbol: "cable.connector", text: model.template.connectionNote)
                    Divider()
                    ConnectionDetail(title: tr("麦克风与听写", "Microphone & dictation"), symbol: "mic", text: model.template.audioNote)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .settingsGlass(cornerRadius: 10)
                if isController {
                    HStack(spacing: 10) {
                        Link(destination: URL(string: "x-apple.systempreferences:com.apple.Bluetooth")!) {
                            Label(tr("打开蓝牙设置", "Bluetooth settings"), systemImage: "gearshape")
                        }
                        Spacer(minLength: 0)
                        Button(tr("重新检测", "Detect again")) { model.perform { model.runtime.reconnectDevice() } }
                    }.font(.system(size: 14))
                    DisclosureGroup(tr("高级兼容设置", "Advanced compatibility")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tr("自动识别无需配置文件。仅在设备不受系统支持、且已有实测映射时，使用 HID 配置替代自动识别。", "Automatic detection needs no profile. Use an HID override only for an unsupported device with a measured mapping."))
                                .font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button(tr("导入 HID 配置…", "Import HID profile…"), action: model.importDevice)
                                if model.runtime.templates.profile() != nil {
                                    Button(tr("恢复自动识别", "Use automatic detection")) {
                                        model.perform { try model.runtime.configureDevice(profile: nil) }
                                    }
                                }
                            }
                        }.padding(.top, 10)
                    }.font(.system(size: 14, weight: .medium))
                }
            }.padding(20)
            Divider()
            HStack(spacing: 10) {
                if !isController && model.runtime.templates.profile() != nil {
                    Button(tr("解除绑定", "Unlink profile")) { model.perform { try model.runtime.configureDevice(profile: nil) } }
                        .buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !isController {
                    Button(tr("导入 HID 配置…", "Import HID profile…"), action: model.importDevice)
                }
                Button(tr("完成", "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }.padding(.horizontal, 20).padding(.vertical, 16)
                .background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
        }.frame(width: 600)
            .background { SettingsBackdrop(material: .sheet, blendingMode: .withinWindow) }
            .onExitCommand { dismiss() }
    }
}

private struct ConnectionDetail: View {
    let title: String
    let symbol: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 20).padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(text).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SheetHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SheetBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.primary.opacity(0.05), in: Capsule()).fixedSize()
    }
}
