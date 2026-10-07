import AppKit
import AVFAudio
import SwiftUI
import SpeechInput
import WandAgent

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

struct CommandSettingsPage: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var settings: CommandSettings
    @State private var draft = CommandModel(CommandEndpoint.all[0])
    @State private var busy = false
    @State private var checked: (ok: Bool, detail: String)?
    @State private var notes = ""
    @State private var askingBypass = false
    @State private var showingHistory = false
    @State private var conversation = ""
    /// What the installed harness says its version is; nil while it is being asked or when there is none.
    @State private var harnessVersion: String?
    /// Whether the harness's own apps have been given VibeWand's view, and what the harness said of the last change.
    @State private var viewShown = false
    @State private var viewBusy = false
    @State private var viewNote = ""
    @State private var mayRecord = CGPreflightScreenCaptureAccess()

    private var command: CommandController { model.runtime.command }
    /// What leaves this Mac, as the settings in force make it.
    private var disclosure: String {
        var text = tr("配置好模型后，这些内容会离开这台 Mac，发给你选的模型服务：你说出的命令原话；应用、窗口和会话的标题，项目文件夹名；操作界面时前台窗口里控件上的文字。",
                      "Once a model is set up, the following leaves this Mac for the model service you chose: the words of your command; the titles of apps, windows and chats, and project folder names; the labels of controls in the front window when the interface is operated.")
        if settings.sight {
            text += tr("你打开了“\(CommandSettings.sightTitle)”：模型要看时，被操作的那个窗口的截图和在本机从图里认出的文字也会发给它，窗口里显示的内容都在其中。",
                       " You turned on letting the model see: when it asks to look, a picture of the window being operated is sent too, with the text read in it on this Mac: everything that window shows.")
        } else {
            text += tr("输入框和文档的内容、选中的文字、截图不会发给它。", " The contents of fields and documents, selected text and screenshots are not sent to it.")
        }
        if settings.listening {
            text += tr("你让语音服务的模型直接听命令：这些内容连同命令的录音发给语音服务，而不是下面“模型”里的服务。",
                       " You let the voice service's model hear the command itself: all of this, and the recording of the command, goes to the voice service rather than the service under Model below.")
        }
        if !settings.listening, settings.speaks, !settings.voices.isEmpty, !settings.readerVoice.isEmpty {
            text += tr("结果和问题读出来时，要读的那一句会发给语音服务合成。", " When a result or a question is read out, that line goes to the voice service to be spoken.")
        }
        if settings.tools == .all {
            text += tr("你打开了 Harness 的全部工具：模型用它们读到的文件内容、命令输出和网页内容也会发给它。",
                       " You turned on the harness's own tools: what the model reads with them, file contents, command output and web pages, is sent to it as well.")
        }
        return text
    }

    var body: some View {
        StandardPage(title: tr("命令模式", "Command mode"),
                     subtitle: tr("按住命令键说一句话，VibeWand 替你找到应用、会话或控件。", "Hold the command key and say what you want. VibeWand finds the app, chat or control.")) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) { switchCard; modelCard; notesCard; keyCard }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(spacing: 16) { reachCard; voiceCard; permissionCard; conversationCard; recordsCard }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { draft = settings.model; notes = settings.instructions; conversation = conversationLine }
        .task(id: settings.kernelMode) {
            guard settings.kernelMode == .harness, let harness = settings.harness else { harnessVersion = nil; return }
            viewShown = Harness.apps.contains(where: harness.showsView)
            harnessVersion = await command.version(of: harness)
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            conversation = conversationLine; mayRecord = CGPreflightScreenCaptureAccess()
        }
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
            SettingsNote(text: tr("默认开启。模型没配好之前，命令键不起作用，设备上的按键也保持原样。“语音输入”用阿里 Qwen 实时语音时，它的模型就是命令的模型，不用另配。",
                                  "On by default. Until a model is set up the command key does nothing, and the device's keys keep what they did. When Voice input uses Alibaba Qwen Realtime, its model is the model for commands and nothing else needs setting up."))
            SettingsNote(text: disclosure)
        }
    }
    private var readiness: (ready: Bool, text: String) {
        if !settings.enabled { return (false, tr("已关闭", "Turned off")) }
        if settings.kernelMode == .builtIn, !kernelReady { return (false, tr("此版本未包含命令内核", "This build does not include the command kernel")) }
        if let heard = settings.listenModel, settings.usable { return (true, tr("已就绪：语音服务的模型直接听命令，", "Ready: the voice service's model hears the command itself, ") + heard) }
        if settings.kernelMode == .harness {
            return settings.usable ? (true, tr("已就绪：经 DeepSeek Harness 使用 ", "Ready: through DeepSeek Harness, on ") + settings.modelName)
                                   : (false, tr("没有找到已安装的 DeepSeek Harness", "No installed DeepSeek Harness found"))
        }
        if settings.model.model.isEmpty { return (false, tr("还没有选模型", "No model chosen yet")) }
        if !settings.usable { return (false, tr("还没有保存这个地址的密钥", "No key saved for this address yet")) }
        return (true, tr("已就绪：", "Ready: ") + settings.model.model)
    }

    private var modelCard: some View {
        SettingsCard(title: tr("模型", "Model")) {
            Picker(tr("内核", "Kernel"), selection: Binding(get: { settings.kernelMode }, set: { settings.setKernelMode($0); checked = nil })) {
                Text(tr("内置（VibeWand 自带的 DeepSeek Harness）", "Built in (the DeepSeek Harness VibeWand ships)")).tag(CommandKernelMode.builtIn)
                Text(tr("插件模式（你已安装的 DeepSeek Harness）", "Plugin mode (the DeepSeek Harness you installed)")).tag(CommandKernelMode.harness)
            }
            SettingsNote(text: tr("两种内核跑的是同一个协调器，用法相同。内置的那份只是替你装好了，模型在下面配置；插件模式用你自己那份里的模型、密钥和登录，对话也存在它那里。",
                                  "Both kernels run the same coordinator and are used the same way. The built-in one is simply installed for you, with its model set up below; plugin mode uses the models, keys and sign-ins of your own harness, which also keeps the conversations."))
            if let heard = settings.listenModel {
                Label(tr("命令现在交给语音服务的 \(heard)，下面配置的模型暂时不用", "Commands now go to the voice service's \(heard); the model set up below is not in use"),
                      systemImage: "waveform").font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            }
            if settings.kernelMode == .harness { harnessSettings } else { builtInSettings }
            if !settings.listening { testResult }
        }
    }
    /// How the last test went, shown on the card of the model it ran on.
    @ViewBuilder private var testResult: some View {
        if let checked {
            Label(checked.detail, systemImage: checked.ok ? "checkmark.circle" : "xmark.octagon").font(.system(size: 13))
                .foregroundStyle(checked.ok ? Color.green : Color.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Plugin mode: the user's own harness runs the coordinator. Its models and sign-ins are set up in its own apps.
    @ViewBuilder private var harnessSettings: some View {
        if let harness = settings.harness {
            let verified = harnessVersion.map(Harness.verified.contains) ?? true
            Label(harnessVersion.map { "DeepSeek Harness \($0) · " + (verified ? tr("已验证", "verified") : tr("未验证", "not verified")) } ?? tr("正在询问 DeepSeek Harness 的版本…", "Asking DeepSeek Harness for its version…"),
                  systemImage: verified ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(verified ? Color.primary : Color.orange)
            if !verified {
                SettingsToggleRow(title: tr("仍然在这个未验证的版本上尝试", "Try this unverified version anyway"),
                                  isOn: Binding(get: { settings.harnessUnverified }, set: { settings.setHarnessUnverified($0) }))
                SettingsNote(text: tr("插件声明兼容的 DeepSeek Harness 版本是 \(Harness.verified.joined(separator: "、"))，Harness 自己会拒绝在其他版本上加载它。打开这一项，VibeWand 会按 Harness 的规矩为“这个插件版本 + 这个 Harness 版本”登记一条例外；它可能出错，出错时改回内置内核。",
                                      "The plugin declares DeepSeek Harness \(Harness.verified.joined(separator: ", ")) as compatible, and the harness itself refuses to load it on any other. With this on, VibeWand records an exemption the way the harness does, for exactly this plugin version on this harness version. It may fail; switch back to the built-in kernel if it does."))
            }
            SettingsNote(text: tr("每段对话保存在你的 Harness 里，标题以“VibeWand ·”开头，不属于任何项目，列在它的“未分组”下，点开能看到完整上下文。VibeWand 只在 \(harness.home?.path ?? "")/profiles/vibewand 里写自己的配置，别的不动。",
                                  "Each conversation is kept in your harness under a title that starts with “VibeWand ·”. It belongs to no project, so the harness lists it under Ungrouped, where it opens with its whole context. VibeWand writes its own profile to \(harness.home?.path ?? "")/profiles/vibewand and touches nothing else."))
            HStack {
                Button(tr("在浏览器里查看对话", "View conversations in the browser"), action: command.openHarnessViewer).buttonStyle(.borderedProminent)
                Button(tr("打开 DeepSeek Harness", "Open DeepSeek Harness")) {
                    if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.deepseek.dsh") { NSWorkspace.shared.open(app) }
                }.disabled(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.deepseek.dsh") == nil)
            }
            SettingsNote(text: tr("“在浏览器里查看”会新启动一份 Harness 网页版，列表一定是最新的。已经开着的 Harness 桌面版或网页版不会发现别的程序写入的新对话：桌面版要重新打开，网页版要刷新页面，而且新对话在点开之前显示为“未命名”。",
                                  "“View in the browser” starts a fresh copy of the harness's web app, so its list is always current. A harness desktop or web app that is already open does not notice a conversation another program wrote: reopen the desktop app or reload the web page, and until it is opened a new conversation shows as Untitled."))
            if harness.view != nil {
                SettingsToggleRow(title: tr("在 Harness 里把命令显示成语音消息", "Show commands as voice messages in the harness"),
                                  isOn: Binding(get: { viewShown }, set: { showView($0, harness) })).disabled(viewBusy)
                if !viewNote.isEmpty { SettingsNote(text: viewNote) }
                SettingsNote(text: tr("打开后，VibeWand 用 Harness 自己的插件命令，把一个界面插件（vibewand-view）加进它的桌面版和网页版：命令模式开始的对话带一个标记，你说的每条命令是一条语音消息，能播放原声，旁边是识别出的文字和当时所在的应用。录音仍只在本机，由 Harness 从 VibeWand 的记录里读出来播放。桌面版要先完全退出再切换，切换后重新打开；它会出现在 Harness 的“插件”页里，在那里或在这里都能去掉。只声明兼容 DeepSeek Harness \(Harness.verified.joined(separator: "、"))。",
                                      "With this on, VibeWand uses the harness's own plugin command to add a view plugin (vibewand-view) to its desktop and web apps: a conversation command mode started carries a mark, and each command you spoke is a voice message that plays as you said it, beside the words recognised in it and the app you were in. The recording stays on this Mac; the harness reads it from VibeWand's records to play it. Quit the desktop app completely before switching and open it again afterwards. The plugin is listed on the harness's Plugins page, and can be removed there or here. It declares DeepSeek Harness \(Harness.verified.joined(separator: ", ")) only."))
            }
            Divider()
            Picker(tr("模型", "Model"), selection: Binding(get: { settings.harnessModel }, set: { settings.setHarnessModel($0) })) {
                Text(tr("跟随 Harness 的默认（\(harness.defaultModel.provider) / \(harness.defaultModel.model)）", "Follow the harness's default (\(harness.defaultModel.provider) / \(harness.defaultModel.model))")).tag(Harness.Model?.none)
                ForEach(harnessChoices, id: \.self) { Text("\($0.provider) / \($0.model)").tag(Harness.Model?.some($0)) }
            }
            Picker(tr("思考强度", "Reasoning"), selection: Binding(get: { settings.harnessReasoning }, set: { settings.setHarnessReasoning($0) })) {
                Text(tr("模型默认", "Model default")).tag(ModelRoute.Reasoning.automatic)
                Text(tr("关闭", "Off")).tag(ModelRoute.Reasoning.off)
                Text(tr("低", "Low")).tag(ModelRoute.Reasoning.low)
                Text(tr("中", "Medium")).tag(ModelRoute.Reasoning.medium)
                Text(tr("高", "High")).tag(ModelRoute.Reasoning.high)
            }.fixedSize()
            SettingsNote(text: tr("默认模型和可选的模型服务来自 Harness 的\(harness.source == "web" ? "网页版" : "桌面版")配置，每次开始对话时读取；在 Harness 里改了，下一段对话生效。“测试”之后这里会列出 Harness 里的全部模型。思考强度只在所选模型提供这一档时生效。",
                                  "The default model and the services on offer come from the settings of the harness's \(harness.source == "web" ? "web" : "desktop") app, read each time a conversation starts; a change made there applies to the next conversation. After a test, every model of your harness is listed here. A reasoning level applies only when the chosen model offers it."))
            HStack {
                Button(tr("测试并列出模型", "Test and list models"), action: testHarness).disabled(busy)
                if busy { ProgressView().controlSize(.small) }
            }
            SettingsNote(text: tr("每次测试会在 Harness 里留下一段很短的对话。", "Each test leaves one very short conversation in the harness."))
        } else {
            Label(tr("没有找到已安装的 DeepSeek Harness", "No installed DeepSeek Harness found"), systemImage: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(.orange)
            SettingsNote(text: tr("插件模式需要你自己安装的 DeepSeek Harness 桌面版，或终端里的 dsh 命令。装好后回到这里，或改用内置内核。",
                                  "Plugin mode needs a DeepSeek Harness you installed yourself: its desktop app, or the dsh command for the terminal. Come back here once it is installed, or use the built-in kernel."))
        }
    }
    /// The harness's models as its last conversation listed them, with the saved choice kept in the list.
    private var harnessChoices: [Harness.Model] {
        let listed = command.catalog.map { Harness.Model(provider: $0.provider, model: $0.model) }
        return (settings.harnessModel.map { [$0] } ?? []).filter { !listed.contains($0) } + listed
    }
    /// Adds VibeWand's view to the harness's apps, or takes it out. The desktop app's profile is only there once
    /// that app has been opened, and can only be changed while it is closed: the harness says so itself.
    private func showView(_ shown: Bool, _ harness: Harness) {
        viewBusy = true; viewNote = ""
        Task {
            var refused: [String] = []
            for app in Harness.apps where harness.showsView(in: app) != shown {
                if let said = await harness.setView(shown, in: app) { refused.append(said) }
            }
            viewShown = Harness.apps.contains(where: harness.showsView)
            viewNote = refused.first ?? (shown ? tr("已加入。重新打开 Harness 桌面版，或点“在浏览器里查看对话”就能看到。", "Added. Reopen the harness's desktop app, or use “View conversations in the browser”, to see it.")
                                               : tr("已去掉。", "Removed."))
            viewBusy = false
        }
    }

    private func testHarness() {
        busy = true; checked = nil
        Task { checked = await command.probe(); busy = false }
    }

    @ViewBuilder private var builtInSettings: some View {
        CommandModelBasics(model: model, settings: settings, draft: $draft) { checked = nil }
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
            Button(tr("保存并测试", "Save and test"), action: test).disabled(busy || draft.model.isEmpty || !kernelReady)
            if busy { ProgressView().controlSize(.small) }
        }
    }
    private func test() {
        model.perform { try settings.setModel(draft); draft = settings.model }
        guard draft == settings.model else { return }
        busy = true; checked = nil
        Task { checked = await command.probe(); busy = false }
    }

    /// Hearing and speaking: whether results are said aloud, which models hear, act and speak, and in which voice.
    private var voiceCard: some View {
        SettingsCard(title: tr("听与说", "Hearing and speaking")) {
            SettingsToggleRow(title: tr("把结果和问题说出来", "Say results and questions aloud"), isOn: Binding(get: { settings.speaks }, set: { settings.setSpeaks($0) }))
            SettingsNote(text: tr("命令做完后的那一句、缺什么、要你确认或挑选的问题，除了显示在悬浮窗上也说给你听。再按命令键或按停止，立刻安静。",
                                  "The line a command ends with, what is missing, and a question that waits for your confirmation or choice are said to you as well as shown on the overlay. Holding the command key again, or stop, silences it at once."))
            Divider()
            Picker("", selection: Binding(get: { settings.listens }, set: { settings.setListens($0); checked = nil })) {
                Text(tr("一个模型", "One model")).tag(true)
                Text(tr("多个模型组合", "Several models")).tag(false)
            }
            .pickerStyle(.segmented).labelsHidden()
            if settings.listens {
                let heard = settings.listenModel
                Label(heard.map { tr("正在使用 ", "In use: ") + $0 } ?? tr("需要“语音输入”里选用阿里 Qwen 实时语音并保存密钥；在那之前按“多个模型组合”运行", "Needs Alibaba Qwen Realtime chosen under Voice input, with its key saved; until then it runs as Several models"),
                      systemImage: heard != nil ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(heard != nil ? Color.primary : Color.orange).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(tr("测试", "Test"), action: testHarness).disabled(busy || heard == nil)
                    if heard == nil { Button(tr("语音输入…", "Voice input…")) { model.section = .speech } }
                    if busy, heard != nil { ProgressView().controlSize(.small) }
                }
                if heard != nil { testResult }
                SettingsNote(text: tr("语音服务的 Omni 模型（qwen3.8-omni-flash-realtime）一个包办：自己听你的录音，调用工具，再用它的声音回答；VibeWand 自己要说的确认和结果也由它来说，所以听到的始终是同一个声音。它同时拿到录音和识别出的那行字，识别认错了字也能照录音里说的做。它接在同一个内核上，内置和插件模式都能用，权限、对话保留和 Agent 记录照常；上面“模型”里配置的模型在这期间不用。",
                                      "The voice service's Omni model (qwen3.8-omni-flash-realtime) does it all: it listens to your recording itself, calls the tools and answers in its own voice, and what VibeWand itself has to say, a question or a result, is said by it too, so you hear one voice throughout. It gets the recording and the line the recogniser wrote, so a word the recogniser got wrong can still be acted on as it was spoken. It runs on the same kernel, built in or plugin mode, with permission, kept conversations and agent records as before; the model set up under Model above is not used meanwhile."))
            } else {
                SettingsNote(text: tr("上面“模型”里配置的模型（比如 DeepSeek V4.1 Flash）读识别出的文字去执行，它自己不出声；结果和问题由语音服务的合成模型（\(QwenSpeechSynthesis.model)）读出来，一句话大约一秒后出声。没有配阿里的语音服务，或者下面的声音选了 macOS 自带的语音时，由 macOS 朗读。",
                                      "The model set up under Model above (DeepSeek V4.1 Flash, say) reads the recognised words and acts; it has no voice of its own. Results and questions are read out by the voice service's synthesis model (\(QwenSpeechSynthesis.model)), about a second after a line is ready. Without Alibaba's voice service, or with the macOS voice chosen below, macOS reads them."))
            }
            voicePicker
            SettingsNote(text: tr("一个模型时，录音和上面列出的内容都发给语音服务，而不是“模型”里的那个服务，费用记在语音服务的密钥上；它不能看图：打开了看截图时，它靠在本机认出的文字来读窗口和点击；同一段对话里更早的命令，它看到的是当时识别出的文字。多个模型组合时，发给语音服务的只有要读出来的那一句。",
                                  "With one model, the recording and everything listed above go to the voice service instead of the service under Model, and are billed to the voice service's key; it takes no pictures, so with seeing turned on it reads a window and clicks by the text read on this Mac, and earlier commands of the same conversation reach it as the text recognised at the time. With several models, the voice service is sent only the line that is to be read out."))
        }
    }

    /// The voices of whichever model speaks, grouped by who they sound like.
    @ViewBuilder private var voicePicker: some View {
        let voices = settings.voices, current = settings.speakingVoice
        if voices.isEmpty {
            SettingsNote(text: tr("声音：macOS 自带的语音。“语音输入”选用阿里 Qwen 实时语音并保存密钥后，这里可以挑男声、女声和各种音色。",
                                  "Voice: the macOS voice. Once Voice input uses Alibaba Qwen Realtime with its key saved, a man's or a woman's voice, and many others, can be chosen here."))
        } else {
            HStack {
                Picker(tr("声音", "Voice"), selection: Binding(get: { current }, set: { settings.setSpeakingVoice($0) })) {
                    if !settings.listening { Text(tr("macOS 自带的语音", "The macOS voice")).tag("") }
                    // A name this list does not know, kept from an earlier setting.
                    if !current.isEmpty, SpeechVoice.named(current, in: voices) == nil { Text(current).tag(current) }
                    ForEach(voiceGroups, id: \.title) { group in
                        Section(group.title) { ForEach(voices.filter(group.holds)) { Text(label($0)).tag($0.id) } }
                    }
                }
                Button(tr("试听", "Listen")) { command.audition() }.disabled(!settings.speaks)
            }
            SettingsNote(text: tr("列表是语音服务给这个模型的官方音色，男声、女声、方言和外语口音都有，选了以后下一句话就换。也可以直接对它说“换成男声”“换个四川话的”，模型会从这张表里挑一个。两种组合各记各的声音。",
                                  "The list is the voice service's own for this model: men's and women's voices, dialects and accents. A choice is taken up by the next thing said. You can also just say “switch to a man's voice” or “speak Sichuanese”, and the model picks one from this list. Each of the two arrangements keeps its own voice."))
        }
    }
    private var voiceGroups: [(title: String, holds: (SpeechVoice) -> Bool)] {
        [(tr("女声", "Women"), { $0.kind == .plain && $0.female }), (tr("男声", "Men"), { $0.kind == .plain && !$0.female }),
         (tr("方言", "Dialects"), { $0.kind == .dialect }), (tr("外语口音与英语", "Accents and English"), { $0.kind == .foreign }),
         (tr("童声与角色", "Children and roles"), { $0.kind == .character })]
    }
    private func label(_ voice: SpeechVoice) -> String {
        // The listening model's voices go by a short name of their own; the synthesis model's only by their Chinese one.
        let short = voice.id.replacingOccurrences(of: "_v3.1", with: "")
        let who = settings.listening && voice.name != voice.id ? tr("\(voice.name) \(voice.id)", voice.id) : tr(voice.name, short)
        let speaker = voice.kind == .plain ? "" : " · " + (voice.female ? tr("女", "woman") : tr("男", "man"))
        return who + speaker + " · " + tr(voice.sound.zh, voice.sound.en)
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

    /// What the model can use: whose tools, and whether it may look at the window.
    private var reachCard: some View {
        SettingsCard(title: tr("模型能用什么", "What the model can use")) {
            let whole = settings.kernelMode == .harness && settings.harness?.overlay != nil
            Picker(tr("工具", "Tools"), selection: Binding(get: { settings.tools }, set: { settings.setHarnessTools($0) })) {
                Text(tr("仅 VibeWand 的工具", "VibeWand's tools only")).tag(Harness.Tools.own)
                Text(tr("加上 Harness 的全部工具", "The harness's own tools as well")).tag(Harness.Tools.all)
            }.pickerStyle(.segmented).disabled(!whole)
            SettingsNote(text: !whole ? tr("内置内核只带 VibeWand 的工具：找应用和会话、读取和操作前台窗口的控件。换成插件模式后，可以把你那份 Harness 自带的工具也交给模型。",
                                           "The built-in kernel carries VibeWand's tools only: finding apps and chats, reading and operating the controls of the front window. In plugin mode the tools of your own harness can be handed to the model as well.")
                : settings.tools == .own ? tr("模型只能找应用和会话、读取和操作前台窗口的控件。没有命令行，不读写文件，不上网。",
                                              "The model can find apps and chats, and read and operate the controls of the front window. No shell, no files, no web.")
                : tr("除了 VibeWand 的工具，模型还能用 Harness 自带的命令行、文件读写、网页搜索、技能和子任务，相当于对着你的 Harness 说话。它的工作目录是 VibeWand 的一个临时目录，回答较长时悬浮窗只显示一行，全文在 Harness 里看。",
                     "Beside VibeWand's tools the model has the harness's own shell, file tools, web search, skills and subagents: you are talking to your harness. Its working directory is a scratch folder of VibeWand's, and when an answer is long the overlay shows one line while the whole of it is in the harness."))
            Divider()
            SettingsToggleRow(title: CommandSettings.sightTitle, isOn: Binding(get: { settings.sight }, set: { on in
                settings.setSight(on)
                if on { InterfaceTools.warm() }
                if on, !CGPreflightScreenCaptureAccess() { mayRecord = CGRequestScreenCaptureAccess() }
            }))
            if settings.sight {
                HStack {
                    Label(mayRecord ? tr("屏幕录制权限已授权", "Screen recording is allowed") : tr("还没有屏幕录制权限", "Screen recording is not allowed yet"),
                          systemImage: mayRecord ? "checkmark.shield" : "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(mayRecord ? Color.primary : Color.orange)
                    Spacer(minLength: 8)
                    if !mayRecord {
                        Button(tr("打开系统设置…", "Open System Settings…")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }
                }
            }
            SettingsNote(text: tr("默认关闭。打开后模型多两个工具：看一眼被操作的那个窗口的截图，图上标着控件的编号，并附上在本机从图里认出的文字和它们的位置；用指针点击其中一行文字，或图上的一个位置。不向辅助功能提供控件的窗口（例如网易云音乐）靠它才能操作，它也用来读窗口里显示的内容、分清长得一样的控件、核对只有眼睛看得出的结果。只拍、只点被操作的那一个窗口。点击按下面的权限档位确认：那个位置上写着删除、发送这类字时，每次都先问你。需要 macOS 的“屏幕录制”权限，授权后要重新打开 VibeWand 才生效。不能看图的模型可以靠认出的文字操作，认图标和画面要能看图的模型。",
                                  "Off by default. When on, the model has two more tools: a picture of the window being operated, taken when it asks, with the controls' ids marked on it and the text read in it on this Mac listed with where each line is; and a pointer click on one of those lines or on a point of the picture. A window that gives accessibility no controls, NetEase Cloud Music for one, can be operated only this way, and it is also for reading what a window shows, telling look-alike controls apart and checking results only the eye can see. Only that one window is pictured and clicked. A click is confirmed as the permission mode below says: when the words at its place say delete, send or the like, you are asked every time. It needs the macOS Screen Recording permission, and VibeWand has to be reopened after that is given. A model that takes no pictures can work from the text read; icons and layout need one that does."))
        }
    }

    private var permissionCard: some View {
        SettingsCard(title: tr("权限", "Permission")) {
            Picker("", selection: Binding(get: { settings.permission }, set: { if $0 == .bypass { askingBypass = true } else { settings.setPermission($0) } })) {
                ForEach(PermissionMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            SettingsNote(text: settings.permission.summary)
            if settings.tools == .all { SettingsNote(text: settings.permission.harnessSummary) }
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
                Text(tr("一天内接着说", "Carry on within a day")).tag(1_440)
                Text(tr("一周内接着说", "Carry on within a week")).tag(10_080)
                Text(tr("一直保留，直到我开始新对话", "Keep it until I start a new one")).tag(-1)
            }
            Picker(tr("单条命令最长用时", "Longest one command may run"), selection: Binding(get: { settings.timeLimit }, set: { settings.setTimeLimit($0) })) {
                ForEach([60, 120, 300, 600], id: \.self) { Text(tr("\($0 / 60) 分钟", $0 == 60 ? "1 minute" : "\($0 / 60) minutes")).tag($0) }
            }
            Picker(tr("单条命令最多步数", "Most steps in one command"), selection: Binding(get: { settings.stepLimit }, set: { settings.setStepLimit($0) })) {
                ForEach([12, 24, 48], id: \.self) { Text("\($0)").tag($0) }
            }
            Button(tr("现在开始新对话", "Start a new conversation now")) { command.endConversation(); conversation = conversationLine }.disabled(command.turns == 0)
            SettingsNote(text: tr("同一段对话里可以接着说“不是这个，换下一个”。对话存在内核的会话库里：内核进程空闲 5 分钟后退出，下一条命令再把同一段对话接上，重新打开 VibeWand 之后也一样。保留得越久，上下文占得越多，回答越慢也越贵；用到八成时下一条命令自动开始新对话。本机模型建议用时放长。改动命令模式的任何设置都会开始新对话。",
                                  "Within one conversation you can go on with “not that one, the next”. The conversation lives in the kernel's session store: the kernel process exits after five idle minutes and the next command takes the same conversation up again, also after VibeWand is reopened. The longer it is kept, the more context it holds and the slower and costlier each answer; at four fifths full the next command starts a new one. Give a local model more time. Changing any command-mode setting starts a new conversation."))
            if settings.kernelMode == .harness {
                SettingsNote(text: tr("在 Harness 里点开过的对话会被它接手，VibeWand 这边接不上时自动开始新对话。", "A conversation you opened in the harness is taken over by it; when VibeWand cannot take it up again it starts a new one."))
            }
        }
    }
    private var conversationLine: String {
        guard command.turns > 0, settings.conversation != nil else { return tr("当前没有进行中的对话，下一条命令是新对话", "No conversation in progress. The next command starts one.") }
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
            SettingsNote(text: tr("每条命令的原话、模型的思考和回答、每一步工具调用和它返回的内容（应用、窗口、会话的标题和控件上的文字，过长的截断；打开看截图后还有模型看过的图）都保存在本机，14 天后自动删除。内置内核自己的会话库只留还能接着说的那一段。",
                                  "The words of each command, what the model thought and said, and every tool call with what it returned (titles of apps, windows and chats and the labels of controls, cut when long; with seeing turned on, the pictures the model looked at as well) are kept on this Mac and deleted after 14 days. The built-in kernel's own session store keeps only the conversation that can still be carried on."))
            Divider()
            SettingsToggleRow(title: tr("保留语音命令的录音", "Keep the recording of a spoken command"),
                              isOn: Binding(get: { settings.recordings }, set: { settings.setRecordings($0) }))
            SettingsNote(text: tr("默认开启。说出来的命令在记录里是一条语音消息：能重新播放原声，旁边是识别出的文字。录音和记录放在一起，只在本机，同样 14 天后删除；它不会因此多发给任何服务。系统听写不留录音。",
                                  "On by default. A command you spoke is a voice message in its record: it plays again as you said it, beside the words recognised in it. The recording sits with the record, on this Mac only, and is deleted after the same 14 days; keeping it sends nothing more to any service. macOS dictation leaves no recording."))
        }
    }

    private var keyCard: some View {
        SettingsCard(title: tr("命令键", "Command key")) {
            SettingsNote(text: tr("按住说话，松开执行。VibeKey：长按旋钮并保持（命令模式可用时，模型入口改为长按 OK）。手柄：按住 R1。",
                                  "Hold to speak, release to run. VibeKey: long-press the dial and keep holding (the model entry moves to a long press of OK while command mode is usable). Controller: hold R1."))
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

    private var kernelReady: Bool { settings.harness(.builtIn) != nil }
}

/// The least a model needs to be usable: where it is served, the key for that address, and which model. Settings
/// goes on to the finer points below it; the first-run guide stops here.
struct CommandModelBasics: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var settings: CommandSettings
    @Binding var draft: CommandModel
    /// Called when another service is picked: what was known about the old one no longer holds.
    var changed: () -> Void = {}
    @State private var keyDraft = ""
    @State private var listed: [ListedModel] = []
    @State private var listNote = ""
    @State private var fetching = false

    var body: some View {
        Picker(tr("服务", "Service"), selection: Binding(get: { draft.endpoint }, set: { draft = settings.configuration(for: $0); listed = []; listNote = ""; keyDraft = ""; changed() })) {
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
                Button(tr("获取模型列表", "Fetch models"), action: fetchModels).disabled(fetching || draft.origin == nil)
            }
            if !listNote.isEmpty { SettingsNote(text: listNote) }
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
        fetching = true; listNote = ""
        let wanted = draft, typed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { fetching = false }
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
}

/// What the coordinator did, instruction by instruction: its thinking, each tool call and what came back.
struct CommandHistorySheet: View {
    let command: CommandController
    @Environment(\.dismiss) private var dismiss
    @State private var records: [TaskRecord] = []
    @State private var selected: String?
    @State private var player: AVAudioPlayer?
    @State private var playing: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: tr("Agent 记录", "Agent records"),
                         subtitle: tr("最近的命令在上。选一条，看模型想了什么、调用了哪些工具、各自返回了什么。", "Newest first. Pick one to see what the model thought, which tools it called and what each returned."))
                .padding(20).background { SettingsBackdrop(material: .headerView, blendingMode: .withinWindow) }
            Divider()
            HStack(spacing: 0) {
                List(records, selection: $selected) { record in
                    VStack(alignment: .leading, spacing: 3) {
                        // A command that can be heard again is listed as a voice message.
                        ((record.recording == nil ? Text("") : Text(Image(systemName: "waveform")).foregroundColor(.accentColor) + Text(" "))
                            .font(.system(size: 12)) + Text(record.instruction).font(.system(size: 13, weight: .medium))).lineLimit(2)
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
            if let recording = record.recording {
                Button { play(record.id, recording.file) } label: {
                    Label(playing == record.id ? tr("停止", "Stop") : tr("播放原声 · \(Self.clock(recording.seconds))", "Play the recording · \(Self.clock(recording.seconds))"),
                          systemImage: playing == record.id ? "stop.circle.fill" : "play.circle.fill")
                }.buttonStyle(.bordered).controlSize(.small).padding(.leading, 27)
            }
            row(record.recording == nil ? "mic" : "waveform", .accentColor, tr("命令", "Command"), record.instruction, note: [
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
            // What the model was shown, as it was sent.
            if let name = line["image"]?.string, let picture = NSImage(contentsOf: record.directory.appendingPathComponent(name)) {
                Image(nsImage: picture).resizable().scaledToFit().frame(maxWidth: 520, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)) }
                    .padding(.leading, 27)
            }
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

    /// Plays a command as it was spoken, or stops the one that is playing.
    private func play(_ id: String, _ file: URL) {
        let stopping = playing == id
        player?.stop(); player = nil; playing = nil
        guard !stopping, let sound = try? AVAudioPlayer(contentsOf: file) else { return }
        player = sound; playing = id
        sound.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + sound.duration + 0.1) { if player === sound { player = nil; playing = nil } }
    }
    static func clock(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds.rounded(.up)) / 60, Int(seconds.rounded(.up)) % 60) }

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
