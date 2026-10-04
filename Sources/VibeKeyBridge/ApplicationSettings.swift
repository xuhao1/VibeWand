import AppKit
import SwiftUI
import UniformTypeIdentifiers

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

struct ApplicationSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var editing: CustomApplicationProfile?
    @State private var removing: CustomApplicationProfile?

    var body: some View {
        StandardPage(title: tr("应用适配", "Applications"), subtitle: tr("为前台应用选择合适的操作，或添加自己的快捷键。", "Choose controls for each app, or add your own shortcuts.")) {
            SettingsCard(title: tr("我的应用", "My apps")) {
                HStack(alignment: .center, spacing: 16) {
                    Text(tr("从一个模板开始，配置你常用的应用。", "Start with a template for an app you use."))
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button { newProfile(.custom) } label: {
                        Label(tr("添加应用", "Add app"), systemImage: "plus")
                    }.buttonStyle(.borderedProminent).controlSize(.regular)
                }
                if model.runtime.adapter.customProfiles.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(ApplicationTemplate.allCases) { template in templateButton(template) }
                    }
                } else {
                    ForEach(model.runtime.adapter.customProfiles) { profile in
                        Divider()
                        customProfileRow(profile)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(tr("内置适配", "Built-in integrations")).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(tr("自动匹配前台应用", "Match the foreground app automatically"))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach([ApplicationProfile.codex, .claude, .deepSeekHarness, .workBuddy, .browser, .weChat, .feishu], id: \.self) { profile in
                        builtInCard(profile)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label(tr("自定义适配", "Custom integrations"), systemImage: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                        Text(tr("自定义配置优先于内置适配。", "Custom profiles take priority over built-in rules."))
                            .font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading).padding(16)
                    .background(Color.accentColor.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .settingsGlass()
                }
            }
        }
        .sheet(item: $editing) { profile in ApplicationProfileEditor(model: model, profile: profile) }
        .alert(tr("移除此应用适配？", "Remove this app integration?"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(tr("取消", "Cancel"), role: .cancel) { removing = nil }
            Button(tr("移除", "Remove"), role: .destructive) {
                if let removing { model.runtime.adapter.removeCustomProfile(id: removing.id); model.refresh() }
                removing = nil
            }
        } message: {
            Text(tr("移除自定义配置后，如有内置适配，将恢复使用内置适配。", "Removing the custom profile restores the built-in integration, if one exists."))
        }
    }

    private func newProfile(_ template: ApplicationTemplate) {
        var profile = CustomApplicationProfile()
        profile.applyTemplate(template)
        editing = profile
    }

    private func templateButton(_ template: ApplicationTemplate) -> some View {
        Button { newProfile(template) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol(for: template)).font(.system(size: 18))
                    .foregroundStyle(Color.accentColor).frame(width: 24)
                Text(template.title).font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 13)
            .background(Color.accentColor.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .settingsGlass(cornerRadius: 8)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).help(tr("从此模板添加应用", "Add an app using this template"))
    }

    private func customProfileRow(_ profile: CustomApplicationProfile) -> some View {
        HStack(spacing: 12) {
            appIcon(symbol(for: profile.template), color: .accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(profile.template.title + " · " + (profile.shortcuts[.primary]?.label ?? ApplicationCommand.primary.emptyLabel))
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(tr("编辑", "Edit")) { editing = profile }.controlSize(.small)
            Toggle(profile.name, isOn: Binding(get: {
                model.runtime.adapter.customProfiles.first { $0.id == profile.id }?.enabled ?? false
            }, set: {
                model.runtime.adapter.setCustomProfileEnabled($0, id: profile.id); model.refresh()
            })).toggleStyle(.switch).controlSize(.small).labelsHidden()
                .accessibilityLabel(tr("启用 ", "Enable ") + profile.name)
            Button { removing = profile } label: { Image(systemName: "trash").frame(width: 24, height: 24) }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help(tr("移除适配", "Remove integration"))
                .accessibilityLabel(tr("移除 ", "Remove ") + profile.name)
        }.padding(.vertical, 2)
    }

    private func builtInCard(_ profile: ApplicationProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                appIcon(symbol(for: profile), color: tint(for: profile))
                Text(profile.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Toggle(profile.title, isOn: Binding(get: { model.runtime.adapter.isEnabled(profile) }, set: {
                    model.runtime.adapter.setEnabled($0, for: profile); model.refresh()
                })).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .accessibilityLabel(tr("启用 ", "Enable ") + profile.title)
            }
            Text(summary(for: profile)).font(.system(size: 14)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading).padding(16)
        .settingsGlass()
        .help(profile.verification)
    }

    private func appIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .medium))
            .foregroundStyle(color).frame(width: 32, height: 32)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }

    private func symbol(for template: ApplicationTemplate) -> String {
        switch template {
        case .chat: return "bubble.left.and.bubble.right"
        case .browser: return "globe"
        case .custom: return "slider.horizontal.3"
        }
    }

    private func symbol(for profile: ApplicationProfile) -> String {
        switch profile {
        case .codex: return "terminal"
        case .claude: return "asterisk"
        case .deepSeekHarness: return "sparkles"
        case .workBuddy: return "briefcase"
        case .browser: return "globe"
        case .weChat: return "bubble.left.and.bubble.right"
        case .feishu: return "paperplane"
        default: return "app"
        }
    }

    private func tint(for profile: ApplicationProfile) -> Color {
        switch profile {
        case .codex: return .primary
        case .claude: return .orange
        case .weChat: return .green
        case .deepSeekHarness: return .indigo
        case .workBuddy: return .teal
        default: return .blue
        }
    }

    private func summary(for profile: ApplicationProfile) -> String {
        switch profile {
        case .codex: return tr("会话、模型与推理强度；草稿编辑与滚动。", "Chats, models and reasoning; draft editing and scrolling.")
        case .claude: return tr("⌘K 会话搜索、模型菜单与强度滑块；听写直接写入输入框。", "⌘K chat search, the model menu and effort slider; dictation goes straight into the composer.")
        case .deepSeekHarness: return tr("侧边栏会话列表、模型与推理等级菜单。", "Sidebar chat list, model and reasoning menus.")
        case .workBuddy: return tr("搜索任务、模型菜单；松开后粘贴听写。", "Task search, the model menu and dictation pasted on release.")
        case .browser: return tr("滚动网页、切换标签页、定位地址栏。", "Page scrolling, tab switching and address bar focus.")
        case .weChat: return tr("⌘F 搜索聊天；浏览结果与编辑草稿。", "⌘F chat search, result navigation and draft editing.")
        case .feishu: return tr("⌘K 快速搜索；浏览结果与编辑草稿。", "⌘K quick search, result navigation and draft editing.")
        default: return profile.summary
        }
    }
}

private struct ApplicationProfileEditor: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomApplicationProfile
    @State private var error: String?
    @State private var showIdentifier = false
    private let isNew: Bool

    init(model: SettingsModel, profile: CustomApplicationProfile) {
        self.model = model
        _draft = State(initialValue: profile)
        isNew = !model.runtime.adapter.customProfiles.contains { $0.id == profile.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "app.badge").font(.system(size: 22)).foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isNew ? tr("添加应用", "Add app") : tr("编辑应用适配", "Edit app integration"))
                        .font(.system(size: 21, weight: .semibold))
                    Text(tr("选择应用，再设置操作与快捷键。", "Choose an app, then configure its shortcuts."))
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 20).padding(.vertical, 16)
                .background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("应用", "Application")).font(.system(size: 14, weight: .semibold))
                            TextField(tr("应用名称", "App name"), text: $draft.name).textFieldStyle(.roundedBorder)
                        }
                        Button(tr("选择应用…", "Choose app…"), action: chooseApplication)
                            .padding(.top, 21)
                    }
                    DisclosureGroup(isExpanded: $showIdentifier) {
                        TextField("com.example.app", text: $draft.bundleID).textFieldStyle(.roundedBorder).padding(.top, 6)
                    } label: {
                        Text(draft.bundleID.isEmpty ? tr("或手动填写应用标识", "Or enter an app identifier manually") : draft.bundleID)
                            .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }.font(.system(size: 13))
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tr("适配模板", "Integration template")).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button(tr("恢复模板默认", "Reset shortcuts")) { draft.applyTemplate(draft.template) }
                            .buttonStyle(.link).font(.system(size: 13))
                    }
                    Picker(tr("适配模板", "Integration template"), selection: Binding(get: { draft.template }, set: { draft.applyTemplate($0) })) {
                        ForEach(ApplicationTemplate.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Text(draft.template.summary).font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(tr("操作", "Action")).frame(maxWidth: .infinity, alignment: .leading)
                        Text(tr("修饰键", "Modifiers")).frame(width: 132)
                        Text(tr("按键", "Key")).frame(width: 134, alignment: .leading)
                    }.font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.primary.opacity(0.035))
                    Divider()
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(ApplicationCommand.allCases) { command in
                                shortcutRow(command)
                                if command != ApplicationCommand.allCases.last { Divider().opacity(0.5).padding(.leading, 12) }
                            }
                        }
                    }.frame(maxHeight: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .settingsGlass(cornerRadius: 10, prominent: true)
                if let error { Text(error).font(.system(size: 13)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            }.padding(20).frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 10) {
                Text(tr("切换模板会重置快捷键。", "Changing templates resets shortcuts."))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Button(tr("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("保存", "Save"), action: save).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.bundleID.isEmpty)
            }.padding(.horizontal, 20).padding(.vertical, 14)
                .background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
        }.frame(width: 760, height: 690)
            .background { SettingsBackdrop(material: .sheet, blendingMode: .withinWindow) }
    }

    private func shortcutRow(_ command: ApplicationCommand) -> some View {
        HStack(spacing: 8) {
            Text(command.title).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                modifier(command, "⌃", "Control", \.control)
                modifier(command, "⌥", "Option", \.option)
                modifier(command, "⇧", "Shift", \.shift)
                modifier(command, "⌘", "Command", \.command)
            }.frame(width: 132)
            Picker(command.title, selection: Binding<ApplicationKey?>(get: { draft.shortcuts[command]?.key }, set: { key in
                if let key {
                    var value = draft.shortcuts[command] ?? ApplicationShortcut(key: key)
                    value.key = key; draft.shortcuts[command] = value
                } else { draft.shortcuts.removeValue(forKey: command) }
            })) {
                Text(command.emptyLabel).tag(Optional<ApplicationKey>.none)
                Divider()
                ForEach(ApplicationKey.allCases) { Text($0.title).tag(Optional($0)) }
            }.labelsHidden().frame(width: 134)
        }.padding(.horizontal, 12).padding(.vertical, 7)
    }

    private func modifier(_ command: ApplicationCommand, _ symbol: String, _ name: String, _ keyPath: WritableKeyPath<ApplicationShortcut, Bool>) -> some View {
        let selected = draft.shortcuts[command]?[keyPath: keyPath] ?? false
        return Button {
            guard var value = draft.shortcuts[command] else { return }
            value[keyPath: keyPath].toggle(); draft.shortcuts[command] = value
        } label: {
            Text(symbol).font(.system(size: 16, weight: .medium)).frame(width: 29, height: 26)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background(selected ? Color.accentColor : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).disabled(draft.shortcuts[command] == nil)
            .help(name).accessibilityLabel(command.title + " · " + name)
            .accessibilityValue(selected ? tr("已选", "Selected") : tr("未选", "Not selected"))
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = tr("选择要适配的应用", "Choose an app to configure")
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
            error = tr("无法识别这个应用，请选择一个 Mac 应用。", "This application could not be identified. Choose a Mac application."); return
        }
        draft.bundleID = identifier
        draft.name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        error = nil
    }

    private func save() {
        do { try model.runtime.adapter.saveCustomProfile(draft); model.refresh(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
