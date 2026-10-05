import AppKit
import SwiftUI
import WandAgent

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

struct CommandSettingsPage: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var settings: CommandSettings
    @State private var draft = CommandModel(CommandEndpoint.all[0])
    @State private var keyDraft = ""
    @State private var listed: [ListedModel] = []
    @State private var listNote = ""
    @State private var busy = false
    @State private var checked: (ok: Bool, detail: String)?
    @State private var notes = ""
    @State private var askingBypass = false
    @State private var showingHistory = false
    @State private var conversation = ""

    private static let disclosure = (
        "配置好模型后，这些内容会离开这台 Mac，发给你在下面选的模型服务：你说出的命令原话；应用、窗口和会话的标题，项目文件夹名；操作界面时前台窗口里控件上的文字。输入框和文档的内容、选中的文字不会发给它。",
        "Once a model is set up, the following leaves this Mac for the model service you choose below: the words of your command; the titles of apps, windows and chats, and project folder names; the labels of controls in the front window when the interface is operated. The contents of fields and documents, and selected text, are not sent to it."
    )
    private var command: CommandController { model.runtime.command }

    var body: some View {
        StandardPage(title: tr("命令模式", "Command mode"),
                     subtitle: tr("按住命令键说一句话，VibeWand 替你找到应用、会话或控件。", "Hold the command key and say what you want. VibeWand finds the app, chat or control.")) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) { switchCard; modelCard; notesCard }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(spacing: 16) { permissionCard; conversationCard; recordsCard; keyCard }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { draft = settings.model; notes = settings.instructions; conversation = conversationLine }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in conversation = conversationLine }
        .sheet(isPresented: $showingHistory) { CommandHistorySheet(command: command) }
        .alert(tr("跳过全部确认？", "Bypass all confirmations?"), isPresented: $askingBypass) {
            Button(tr("跳过", "Bypass"), role: .destructive) { settings.setPermission(.bypass) }
            Button(tr("取消", "Cancel"), role: .cancel) {}
        } message: { Text(PermissionMode.bypass.summary) }
    }

    // MARK: Switch and model

    private var switchCard: some View {
        SettingsCard(title: tr("开关", "Switch")) {
            SettingsToggleRow(title: tr("开启命令模式", "Turn on command mode"), isOn: Binding(get: { settings.enabled }, set: { settings.setEnabled($0) }))
            Label(readiness.text, systemImage: readiness.ready ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(readiness.ready ? Color.primary : Color.orange)
            SettingsNote(text: tr("默认开启。模型没配好之前，命令键不起作用，设备上的按键也保持原样。", "On by default. Until a model is set up the command key does nothing, and the device's keys keep what they did."))
            SettingsNote(text: tr(Self.disclosure.0, Self.disclosure.1))
        }
    }
    private var readiness: (ready: Bool, text: String) {
        if !settings.enabled { return (false, tr("已关闭", "Turned off")) }
        if !Self.kernelReady { return (false, tr("此版本未包含命令内核", "This build does not include the command kernel")) }
        if settings.model.model.isEmpty { return (false, tr("还没有选模型", "No model chosen yet")) }
        if !settings.usable { return (false, tr("还没有保存这个地址的密钥", "No key saved for this address yet")) }
        return (true, tr("已就绪：", "Ready: ") + settings.model.model)
    }

    private var modelCard: some View {
        SettingsCard(title: tr("模型", "Model")) {
            Picker(tr("服务", "Service"), selection: Binding(get: { draft.endpoint }, set: { draft = settings.configuration(for: $0); listed = []; listNote = ""; checked = nil; keyDraft = "" })) {
                ForEach(CommandEndpoint.all) { Text($0.title).tag($0.id) }
            }
            if draft.endpoint == CommandEndpoint.custom {
                field(tr("地址", "Address"), text: $draft.baseURL, placeholder: "https://example.com/v1")
                Picker(tr("接口", "Protocol"), selection: $draft.wire) {
                    Text("OpenAI Chat Completions").tag(ModelRoute.Wire.openAIChat)
                    Text("OpenAI Responses").tag(ModelRoute.Wire.openAIResponses)
                    Text("Anthropic Messages").tag(ModelRoute.Wire.anthropic)
                }
            } else {
                Text(draft.baseURL).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Divider()
            Label(keyState, systemImage: settings.keySaved(for: draft) ? "checkmark.shield" : "key").font(.system(size: 14, weight: .medium))
            SecureField(tr("输入这个地址的 API Key", "Enter the API key for this address"), text: $keyDraft).textFieldStyle(.roundedBorder)
            HStack {
                Button(tr("保存密钥", "Save key")) { model.perform { try settings.setModel(draft); try settings.saveKey(keyDraft); keyDraft = "" } }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(tr("删除密钥", "Delete key")) { model.perform { try settings.setModel(draft); try settings.removeKey() } }.disabled(!settings.keySaved(for: draft))
            }
            SettingsNote(text: tr("密钥按地址保存在此 Mac 的钥匙串中，只在启动命令内核时交给它，换了地址不会带过去。费用由你在该服务的账户承担。",
                                  "Keys are kept per address in this Mac's Keychain, handed to the command kernel only when it starts, and never carried to another address. Usage is billed to your account with that service."))
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("模型", "Model")).font(.system(size: 13, weight: .medium))
                HStack {
                    TextField(tr("模型 ID", "Model ID"), text: $draft.model).textFieldStyle(.roundedBorder)
                    Menu(tr("选择", "Choose")) {
                        ForEach(listed) { entry in
                            Button(entry.name.map { "\($0)（\(entry.id)）" } ?? entry.id) {
                                draft.model = entry.id
                                if let window = entry.contextWindow { draft.contextWindow = window }
                            }
                        }
                    }.disabled(listed.isEmpty).fixedSize()
                    Button(tr("获取模型列表", "Fetch models"), action: fetchModels).disabled(busy || draft.origin == nil)
                }
                if !listNote.isEmpty { SettingsNote(text: listNote) }
            }
            HStack(spacing: 16) {
                Picker(tr("思考强度", "Reasoning"), selection: $draft.reasoning) {
                    Text(tr("模型默认", "Model default")).tag(ModelRoute.Reasoning.automatic)
                    Text(tr("关闭", "Off")).tag(ModelRoute.Reasoning.off)
                    Text(tr("低", "Low")).tag(ModelRoute.Reasoning.low)
                    Text(tr("中", "Medium")).tag(ModelRoute.Reasoning.medium)
                    Text(tr("高", "High")).tag(ModelRoute.Reasoning.high)
                }.fixedSize()
                Spacer(minLength: 0)
                Text(tr("上下文长度", "Context length")).font(.system(size: 13))
                TextField(tr("自动", "Automatic"), text: Binding(
                    get: { draft.contextWindow > 0 ? String(draft.contextWindow) : "" },
                    set: { draft.contextWindow = Int($0.filter(\.isNumber)) ?? 0 })).textFieldStyle(.roundedBorder).frame(width: 110)
            }
            SettingsNote(text: tr("思考强度选“模型默认”时不发送任何参数；选了档位而服务不认识时，测试会报错。上下文长度是模型能容纳的 token 数，从列表里选模型时会自动填上；留空由内核按 262144 计算。对话用到八成后，下一条命令自动开始新对话。",
                                  "“Model default” sends no reasoning parameter; a level the service does not know shows up as an error when you test. Context length is how many tokens the model holds, filled in when you pick a model from the list; left empty, the kernel assumes 262144. Once a conversation has used four fifths of it, the next command starts a new one."))
            DisclosureGroup(tr("附加参数（JSON）", "Extra settings (JSON)")) {
                TextEditor(text: $draft.extra).font(.system(size: 12, design: .monospaced)).frame(height: 64)
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)) }
                SettingsNote(text: tr("写进内核里这个服务的配置，覆盖上面生成的同名项。例如本机 Qwen 关闭思考：{\"compat\": {\"thinkingFormat\": \"qwen-chat-template\"}}；自定义请求头：{\"headers\": {\"X-Title\": \"VibeWand\"}}。",
                                      "Merged into the kernel's settings for this service, over the generated ones of the same name. For a local Qwen that should stop thinking: {\"compat\": {\"thinkingFormat\": \"qwen-chat-template\"}}; for extra request headers: {\"headers\": {\"X-Title\": \"VibeWand\"}}."))
            }.font(.system(size: 13))
            HStack {
                Button(tr("保存配置", "Save settings")) { model.perform { try settings.setModel(draft); draft = settings.model } }.disabled(draft == settings.model)
                Button(tr("保存并测试", "Save and test"), action: test).disabled(busy || draft.model.isEmpty || !Self.kernelReady)
                if busy { ProgressView().controlSize(.small) }
            }
            if let checked {
                Label(checked.detail, systemImage: checked.ok ? "checkmark.circle" : "xmark.octagon").font(.system(size: 13))
                    .foregroundStyle(checked.ok ? Color.green : Color.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var keyState: String {
        if settings.keySaved(for: draft) { return tr("这个地址的密钥已保存", "Key saved for this address") }
        return draft.keyOptional ? tr("尚未保存密钥（这个地址可以不需要）", "No key saved (this address may not need one)") : tr("尚未保存这个地址的密钥", "No key saved for this address")
    }
    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .medium))
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func fetchModels() {
        busy = true; listNote = ""
        let wanted = draft, typed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { busy = false }
            // A key typed but not yet saved is tried as it is; it goes nowhere but the address shown.
            let key = typed.isEmpty ? await settings.readKey(for: wanted) : typed
            do {
                listed = try await ModelListing.fetch(wire: wanted.wire, baseURL: wanted.baseURL, key: key)
                listNote = tr("服务列出了 \(listed.count) 个模型，从“选择”里挑一个。", "The service lists \(listed.count) models. Pick one under Choose.")
            } catch {
                listed = []
                switch error as? ModelListing.Failure {
                case .status(let code)?: listNote = code == 401 || code == 403 ? tr("服务拒绝了这个密钥（\(code)）。", "The service refused this key (\(code)).")
                    : tr("这个地址没有给出模型列表（\(code)），请直接填写模型 ID。", "This address gave no model list (\(code)). Type the model ID instead.")
                case .unreachable?: listNote = tr("连不上这个地址。", "This address could not be reached.")
                case .address?: listNote = CommandSettingsError.address.localizedDescription
                default: listNote = tr("这个地址的回答不是模型列表，请直接填写模型 ID。", "This address did not answer with a model list. Type the model ID instead.")
                }
            }
        }
    }
    private func test() {
        model.perform { try settings.setModel(draft); draft = settings.model }
        guard draft == settings.model else { return }
        busy = true; checked = nil
        Task { checked = await command.probe(); busy = false }
    }

    private var notesCard: some View {
        SettingsCard(title: tr("给模型的备注", "Notes for the model")) {
            TextEditor(text: $notes).font(.system(size: 13)).frame(height: 76)
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)) }
            HStack {
                Button(tr("保存备注", "Save notes")) { settings.setInstructions(notes); notes = settings.instructions }
                    .disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines) == settings.instructions)
            }
            SettingsNote(text: tr("每次对话开头都会告诉模型的话：常用的叫法、偏好的应用、项目的别名。它补充规则，不能改变规则；随命令一起发给模型服务。",
                                  "Told to the model at the start of every conversation: what you call things, the apps you prefer, nicknames of projects. It adds to the rules and cannot change them, and it is sent to the model service with your commands."))
        }
    }

    // MARK: Permission, conversation, records

    private var permissionCard: some View {
        SettingsCard(title: tr("权限", "Permission")) {
            Picker("", selection: Binding(get: { settings.permission }, set: { if $0 == .bypass { askingBypass = true } else { settings.setPermission($0) } })) {
                ForEach(PermissionMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            SettingsNote(text: settings.permission.summary)
            SettingsNote(text: tr("当前档位显示在悬浮窗的命令下方。无论哪一档，返回键都能随时停止，需要挑选时仍会让你选。",
                                  "The mode in force is shown under a command on the overlay. In every mode the back key stops at any moment, and a choice is still yours to make."))
        }
    }

    private var conversationCard: some View {
        SettingsCard(title: tr("对话与上下文", "Conversation and context")) {
            Label(conversation, systemImage: "text.bubble").font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Picker(tr("保留对话", "Keep a conversation"), selection: Binding(get: { settings.historyMinutes }, set: { settings.setHistoryMinutes($0) })) {
                Text(tr("每条命令重新开始", "Start afresh every command")).tag(0)
                Text(tr("5 分钟内接着说", "Carry on within 5 minutes")).tag(5)
                Text(tr("30 分钟内接着说", "Carry on within 30 minutes")).tag(30)
                Text(tr("2 小时内接着说", "Carry on within 2 hours")).tag(120)
            }
            Picker(tr("单条命令最长用时", "Longest one command may run"), selection: Binding(get: { settings.timeLimit }, set: { settings.setTimeLimit($0) })) {
                ForEach([60, 120, 300, 600], id: \.self) { Text(tr("\($0 / 60) 分钟", $0 == 60 ? "1 minute" : "\($0 / 60) minutes")).tag($0) }
            }
            Picker(tr("单条命令最多步数", "Most steps in one command"), selection: Binding(get: { settings.stepLimit }, set: { settings.setStepLimit($0) })) {
                ForEach([12, 24, 48], id: \.self) { Text("\($0)").tag($0) }
            }
            Button(tr("现在开始新对话", "Start a new conversation now")) { command.shutdownKernel(); conversation = conversationLine }.disabled(command.turns == 0)
            SettingsNote(text: tr("同一段对话里可以接着说“不是这个，换下一个”。保留得越久，上下文占得越多，回答越慢也越贵；本机模型建议用时放长。改动这里任何一项都会开始新对话。",
                                  "Within one conversation you can go on with “not that one, the next”. The longer it is kept, the more context it holds and the slower and costlier each answer; give a local model more time. Changing anything here starts a new conversation."))
        }
    }
    private var conversationLine: String {
        guard command.turns > 0 else { return tr("当前没有进行中的对话，下一条命令是新对话", "No conversation in progress. The next command starts one.") }
        let turns = tr("当前对话已有 \(command.turns) 条命令", command.turns == 1 ? "This conversation has 1 command" : "This conversation has \(command.turns) commands")
        guard let usage = command.usage else { return turns }
        return turns + tr("，上下文 ", ", context ") + "\(CommandController.tokens(usage.used)) / \(CommandController.tokens(usage.size))（\(usage.used * 100 / usage.size)%）"
    }

    private var recordsCard: some View {
        SettingsCard(title: tr("Agent 记录", "Agent records")) {
            HStack {
                Button(tr("查看记录…", "View records…")) { showingHistory = true }.buttonStyle(.borderedProminent)
                Button(tr("在访达中显示", "Show in Finder")) {
                    try? FileManager.default.createDirectory(at: command.support, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([command.support])
                }
                Button(tr("清除全部记录", "Clear all records")) { command.clearRecords(); conversation = conversationLine }
            }
            SettingsNote(text: tr("每条命令的原话、模型的思考和回答、每一步工具调用和它返回的内容（应用、窗口、会话的标题和控件上的文字，过长的截断）都保存在本机，14 天后自动删除。内核自己的对话日志只保留最近一次启动的。",
                                  "The words of each command, what the model thought and said, and every tool call with what it returned (titles of apps, windows and chats and the labels of controls, cut when long) are kept on this Mac and deleted after 14 days. The kernel's own conversation log is kept only for its latest start."))
        }
    }

    private var keyCard: some View {
        SettingsCard(title: tr("命令键", "Command key")) {
            SettingsNote(text: tr("按住说话，松开执行。VibeKey：长按旋钮并保持（命令模式可用时，模型入口改为长按 OK）。手柄：按住 L2。",
                                  "Hold to speak, release to run. VibeKey: long-press the dial and keep holding (the model entry moves to a long press of OK while command mode is usable). Controller: hold L2."))
            Picker(tr("键盘", "Keyboard"), selection: Binding(get: { settings.hotkey }, set: { settings.setHotkey($0) })) {
                ForEach(CommandHotkey.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            SettingsNote(text: tr("单独按住这个键约 0.2 秒开始听；和其他键一起按时照常是修饰键。需要选择或确认时，方向键、回车和 Esc 交给命令，其余时间不受影响。",
                                  "Hold this key on its own for about 0.2 s to start listening; with another key it is an ordinary modifier. When a choice or confirmation is waiting, the arrows, Return and Esc answer it; otherwise they are untouched."))
            SettingsNote(text: tr("已被输入法或其他软件占用的键到不了 VibeWand，例如豆包输入法用右 ⌥ 做语音键。按住没有反应时请换一个。",
                                  "A key that an input method or another app has taken never reaches VibeWand; the Doubao input method, for one, uses right ⌥ for voice. If holding the key does nothing, pick another."))
            Divider()
            SettingsNote(text: tr("也可以在“设备与按键”里把“命令（按住说话）”绑到任意按键。", "You can also bind “Command (hold to speak)” to any button under Devices & inputs."))
            Button(tr("设备与按键…", "Devices & inputs…")) { model.section = .devices }
        }
    }

    private static var kernelReady: Bool { CommandController.install() != nil }
}

/// What the coordinator did, instruction by instruction: its thinking, each tool call and what came back.
struct CommandHistorySheet: View {
    let command: CommandController
    @Environment(\.dismiss) private var dismiss
    @State private var records: [TaskRecord] = []
    @State private var selected: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: tr("Agent 记录", "Agent records"),
                         subtitle: tr("最近的命令在上。选一条，看模型想了什么、调用了哪些工具、各自返回了什么。", "Newest first. Pick one to see what the model thought, which tools it called and what each returned."))
                .padding(20).background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
            Divider()
            HStack(spacing: 0) {
                List(records, selection: $selected) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.instruction).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        Text(caption(record)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }.padding(.vertical, 3).tag(record.id)
                }.frame(width: 290)
                Divider()
                ScrollView {
                    if let record = records.first(where: { $0.id == selected }) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(record.lines.enumerated()), id: \.offset) { entry(record, $0.element) }
                        }.padding(18).frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        Text(records.isEmpty ? tr("还没有记录。说一条命令后再来看。", "Nothing recorded yet. Speak a command and look again.") : tr("选一条命令", "Pick a command"))
                            .foregroundStyle(.secondary).padding(40).frame(maxWidth: .infinity)
                    }
                }
            }
            Divider()
            HStack {
                Text(tr("\(records.count) 条", records.count == 1 ? "1 record" : "\(records.count) records")).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Button(tr("刷新", "Refresh"), action: load)
                Button(tr("完成", "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 20).padding(.vertical, 14).background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
        }
        .frame(width: 940, height: 620)
        .background { SettingsBackdrop(material: .sheet, blendingMode: .withinWindow) }
        .onAppear(perform: load).onExitCommand { dismiss() }
    }

    private func load() {
        records = command.history()
        if !records.contains(where: { $0.id == selected }) { selected = records.first?.id }
    }

    private func caption(_ record: TaskRecord) -> String {
        var parts: [String] = []
        if let started = record.started {
            let clock = DateFormatter(); clock.dateFormat = Calendar.current.isDateInToday(started) ? "HH:mm:ss" : "MM-dd HH:mm"
            parts.append(clock.string(from: started))
        }
        parts.append(record.outcome.map { $0.finished ? tr("完成", "done") : tr("未完成", "not done") } ?? tr("被打断", "interrupted"))
        parts.append(tr("\(record.steps) 步", record.steps == 1 ? "1 step" : "\(record.steps) steps"))
        if let usage = record.usage { parts.append("\(CommandController.tokens(usage.used))/\(CommandController.tokens(usage.size))") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func entry(_ record: TaskRecord, _ line: JSONValue) -> some View {
        let tool = line["tool"]?.string ?? ""
        switch line["kind"]?.string {
        case "instruction":
            row("mic", .accentColor, tr("命令", "Command"), record.instruction, note: [
                record.app.isEmpty ? "" : tr("当时在 ", "in ") + record.app, record.model,
                record.turn == 1 ? tr("新对话", "new conversation") : tr("对话的第 \(record.turn) 条", "command \(record.turn) of its conversation")
            ].filter { !$0.isEmpty }.joined(separator: " · "))
        case "thought": row("brain", .purple, tr("思考", "Thinking"), line["text"]?.string ?? "", dimmed: true)
        case "message": row("text.bubble", .primary, tr("模型说", "The model said"), line["text"]?.string ?? "")
        case "call": row("arrow.right.circle", .blue, tool, line["arguments"]?.text ?? "", mono: true)
        case "result":
            let failed = line["ok"]?.bool == false
            row(failed ? "xmark.circle" : "arrow.left.circle", failed ? .red : .green,
                tool + (failed ? tr(" 失败", " failed") : line["verified"]?.bool == false ? tr(" 已执行，结果未能核对", " ran, result not verified") : tr(" 返回", " returned")),
                line["text"]?.string ?? line["error"]?.string ?? "", mono: true, dimmed: true)
        case "confirmed": row("hand.thumbsup", .green, tr("你确认了 ", "You confirmed ") + tool, "")
        case "declined": row("hand.raised", .orange, tr("你没有确认 ", "You did not confirm ") + tool, "")
        case "usage":
            if let used = line["used"]?.int, let size = line["size"]?.int, size > 0 {
                row("gauge.with.dots.needle.33percent", .secondary,
                    tr("上下文 ", "Context ") + "\(CommandController.tokens(used)) / \(CommandController.tokens(size))（\(used * 100 / size)%）", "")
            }
        case "end":
            let finished = line["finished"]?.bool == true
            row(finished ? "checkmark.seal" : "exclamationmark.triangle", finished ? .green : .orange,
                finished ? tr("完成", "Done") : tr("结束，未完成", "Ended, not done"), line["said"]?.string ?? "", note: line["reason"]?.string ?? "")
        default: EmptyView()
        }
    }

    private func row(_ symbol: String, _ tint: Color, _ title: String, _ text: String, note: String = "", mono: Bool = false, dimmed: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                if !text.isEmpty {
                    Text(text).font(.system(size: mono ? 12 : 13, design: mono ? .monospaced : .default))
                        .foregroundStyle(dimmed ? Color.secondary : Color.primary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(.tertiary) }
            }
        }
    }
}
