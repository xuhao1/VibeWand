import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI
import SpeechInput
import WandAgent

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

// MARK: Welcome

struct WelcomeStep: View {
    @State private var shown = false
    private var points: [(symbol: String, tint: Color, title: String, detail: String)] { [
        ("dial.medium", .blue, tr("转一转，按一按", "Turn and press"),
         tr("滚动、挑会话、换模型、确认，手不用离开设备。", "Scroll, pick a chat, change the model, confirm: your hand stays on the device.")),
        ("waveform", .pink, tr("按住说话", "Hold to speak"),
         tr("话直接变成输入框里的字，看一眼再自己发送。", "Your words become text in whatever field you are in. You read it, then send it yourself.")),
        ("sparkles", .purple, tr("说一句，它去找", "Say it, and it is found"),
         tr("“切到 Codex 里讨论麦克风的那个会话。”命令模式替你找到应用、会话和控件。", "“Switch to the Codex chat about the microphone.” Command mode finds the app, the chat or the control for you."))
    ] }

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            BrandMark(size: 108)
                .shadow(color: Color.indigo.opacity(0.35), radius: 24, y: 10)
                .scaleEffect(shown ? 1 : 0.82).opacity(shown ? 1 : 0)
            VStack(spacing: 8) {
                Text(tr("欢迎使用 VibeWand", "Welcome to VibeWand")).font(.system(size: 34, weight: .bold, design: .rounded))
                Text(tr("一根魔杖，指挥所有应用", "One wand to command them all")).font(.system(size: 16)).foregroundStyle(.secondary)
            }.opacity(shown ? 1 : 0)
            VStack(spacing: 10) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    HStack(spacing: 14) {
                        Image(systemName: point.symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(point.tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.title).font(.system(size: 15, weight: .semibold))
                            Text(point.detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(13).settingsGlass(cornerRadius: 16, prominent: true)
                    .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
                    .animation(.spring(duration: 0.6, bounce: 0.25).delay(0.15 + Double(index) * 0.1), value: shown)
                }
            }.frame(maxWidth: 560)
            Text(tr("接下来几分钟把它调好：权限、设备、语音、按键和命令模式。每一步都可以先跳过，之后在设置里改。",
                    "The next few minutes set it up: permissions, your device, voice, the buttons and command mode. Any step can be skipped and changed later in Settings."))
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520).opacity(shown ? 1 : 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 40).padding(.top, 24)
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.3)) { shown = true } }
    }
}

// MARK: Permissions

struct AccessStep: View {
    @ObservedObject var model: SettingsModel
    @State private var trusted = AXIsProcessTrusted()
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        OnboardingPage(step: .access, title: tr("先给它两项权限", "Two permissions first"),
                       subtitle: tr("VibeWand 靠 macOS 的辅助功能认出前台应用，并把你在设备上的动作发给它。用内置语音输入时还要用麦克风。",
                                    "VibeWand uses macOS Accessibility to recognise the app in front and send it what you do on the device. Built-in voice input also uses the microphone.")) {
            permission("hand.point.up.left", tr("辅助功能", "Accessibility"), ready: trusted,
                       state: trusted ? tr("已授权", "Allowed") : tr("需要授权，没有它按键不起作用", "Needed: without it the buttons do nothing"),
                       note: tr("用来识别当前应用和输入框，并发送按键、滚动和文字。VibeWand 不读取对话和文档的内容。",
                                "Used to recognise the current app and field and to send keys, scrolling and text. VibeWand does not read what conversations and documents say.")) {
                if !trusted { Button(tr("打开系统设置…", "Open System Settings…"), action: askForAccessibility).buttonStyle(.borderedProminent) }
            }
            permission("mic", tr("麦克风", "Microphone"), ready: microphone == .authorized,
                       state: microphone == .authorized ? tr("已授权", "Allowed") : microphone == .notDetermined ? tr("尚未询问，可以现在允许", "Not asked yet; you can allow it now") : tr("已被拒绝，可在系统设置里打开", "Denied; it can be turned on in System Settings"),
                       note: tr("只有内置语音输入和命令模式用得到。继续用 Typeless、豆包这类外置输入法的话，可以不给。",
                                "Only built-in voice input and command mode use it. If you keep an external input method such as Typeless or Doubao, it is not needed.")) {
                if microphone == .notDetermined {
                    Button(tr("允许使用麦克风", "Allow the microphone")) { AVCaptureDevice.requestAccess(for: .audio) { _ in } }
                } else if microphone != .authorized {
                    Button(tr("打开系统设置…", "Open System Settings…")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                }
            }
            SettingsNote(text: tr("两项都只在这台 Mac 上生效，随时可以在“系统设置 → 隐私与安全性”里收回。没有辅助功能权限时 VibeWand 以演示模式运行：悬浮面板会动，但不操作任何应用。授权后如果按键仍然没有反应，重新打开一次 VibeWand。",
                                  "Both apply to this Mac only and can be taken back under System Settings → Privacy & Security. Without Accessibility VibeWand runs as a demo: the overlay moves and no app is operated. If the buttons still do nothing after you allow it, reopen VibeWand once."))
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = AXIsProcessTrusted(); microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    private func permission<Action: View>(_ symbol: String, _ title: String, ready: Bool, state: String, note: String, @ViewBuilder action: () -> Action) -> some View {
        let button = action()
        return OnboardingCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: ready ? "checkmark.shield.fill" : symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(ready ? Color.green : Color.orange)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44).background((ready ? Color.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    OnboardingStatus(ready: ready, text: state)
                    SettingsNote(text: note)
                }.frame(maxWidth: .infinity, alignment: .leading)
                button.fixedSize()
            }
        }
    }

    private func askForAccessibility() {
        // Puts VibeWand on the system's list, so that there is a switch to turn on, then shows the list.
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        model.accessibility()
    }
}

// MARK: The device

struct DeviceStep: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var guide: OnboardingModel
    private var keyboard: Bool { model.template.id == .keyboard }

    var body: some View {
        OnboardingPage(step: .device, title: tr("试一下你的设备", "Try your device"),
                       subtitle: tr("选中你手上的设备，随便按几个键、转一转。亮起来，就是 VibeWand 收到了。没有设备就选键盘。在这一步里，按键不会发给任何应用。",
                                    "Pick the device in your hand, press a few buttons, give it a turn. What lights up has reached VibeWand. With no device, pick the keyboard. During this step nothing you press is sent to any app.")) {
            HStack(spacing: 10) {
                ForEach(DeviceTemplateID.allCases, id: \.self) { id in
                    let selected = model.snapshot.deviceTemplate == id, connected = model.snapshot.connectedTemplates.contains(id)
                    Button { model.chooseTemplate(id); guide.tested = [] } label: {
                        HStack(spacing: 9) {
                            Image(systemName: Self.symbol(id)).font(.system(size: 16, weight: .medium)).foregroundStyle(selected ? Color.white : Color.blue)
                                .frame(width: 32, height: 32).background(selected ? AnyShapeStyle(Color.blue.gradient) : AnyShapeStyle(Color.blue.opacity(0.12)), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(id.template.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                                Label(connected ? tr("已连接", "Connected") : tr("未连接", "Not connected"), systemImage: "circle.fill")
                                    .labelStyle(.titleAndIcon).font(.system(size: 11)).imageScale(.small).foregroundStyle(connected ? Color.green : Color.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10).frame(maxWidth: .infinity)
                        .background(selected ? Color.blue.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .settingsGlass(cornerRadius: 14, prominent: true)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Color.blue.opacity(0.55) : .clear, lineWidth: 1.5))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain).accessibilityLabel(id.template.title).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack(alignment: .top, spacing: 14) {
                OnboardingDevice(template: model.template, pressed: model.snapshot.pressed, tested: guide.tested).frame(width: 330, height: 262)
                VStack(alignment: .leading, spacing: 12) {
                    progress
                    OnboardingCard {
                        SettingsNote(text: model.template.connectionNote)
                        if keyboard {
                            Button(tr("修改组合键…", "Change the combinations…")) { guide.openSettings?(.devices) }
                        } else {
                            Button(tr("重新连接", "Reconnect")) { model.runtime.reconnectDevice(); model.refresh() }
                            SettingsNote(text: tr("手边没有设备也能继续：选上面的“键盘”，用组合键当按键。", "No device at hand? Pick Keyboard above and key combinations become the buttons."))
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
        }
        .onChange(of: model.snapshot.pressed) { _, pressed in guide.tested.formUnion(pressed) }
    }

    @ViewBuilder private var progress: some View {
        let count = guide.tested.count
        HStack(spacing: 10) {
            Image(systemName: count == 0 ? "hand.tap" : "dot.radiowaves.left.and.right").font(.system(size: 20)).foregroundStyle(count == 0 ? Color.secondary : Color.green)
                .symbolEffect(.pulse, isActive: count == 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(count == 0 ? tr("还没有收到输入", "Nothing received yet")
                     : tr("已收到 \(count) 个按键或方向", count == 1 ? "1 button or direction received" : "\(count) buttons or directions received"))
                    .font(.system(size: 15, weight: .semibold)).contentTransition(.numericText())
                SettingsNote(text: count == 0 ? (keyboard ? tr("按一下左边任意一组组合键。", "Press any of the combinations on the left.") : tr("按一下设备上的任意键。没有反应时，看下面的连接说明。", "Press any button on the device. If nothing happens, see the connection note below."))
                             : count < 3 ? tr("再按几个，把常用的都试一遍。", "Try a few more, so the ones you will use most have all been pressed.")
                             : tr("工作正常。", "It is working."))
            }
            Spacer(minLength: 0)
            if count >= 3 { Image(systemName: "checkmark.seal.fill").font(.system(size: 24)).foregroundStyle(.green).transition(.scale.combined(with: .opacity)) }
        }
        .padding(14).settingsGlass(cornerRadius: 16, prominent: true)
        .animation(.spring(duration: 0.35), value: count)
    }

    static func symbol(_ id: DeviceTemplateID) -> String {
        switch id {
        case .vibeKey: return "dial.medium"
        case .dualSense: return "gamecontroller"
        case .xiaomiRemote: return "av.remote"
        case .keyboard: return "keyboard"
        }
    }
}

// MARK: Voice

struct VoiceStep: View {
    private enum Way { case external, system, local, service }
    @ObservedObject var model: SettingsModel
    @ObservedObject var voice: VoiceInputController
    @State private var draft: SpeechConfiguration
    @State private var keyDraft = ""
    @State private var keySaved = false
    @State private var holding = false

    init(model: SettingsModel, voice: VoiceInputController) {
        self.model = model; self.voice = voice
        _draft = State(initialValue: voice.configuration)
    }
    private var way: Way { draft.mode == .external ? .external : draft.provider == .system ? .system : draft.provider == .senseVoice ? .local : .service }

    var body: some View {
        OnboardingPage(step: .voice, title: tr("怎么把话变成字", "How speech becomes text"),
                       subtitle: tr("按住听写键说话，松开后文字留在输入框里，由你自己发送。选一种识别方式，随时可以在“语音输入”里换。",
                                    "Hold the dictation button and speak; on release the text stays in the field for you to send. Pick how it is recognised. It can be changed any time under Voice input.")) {
            OnboardingChoice(symbol: "character.cursor.ibeam", title: tr("继续用我的语音输入法", "Keep my voice input method"),
                             detail: tr("已经在用 Typeless、豆包这类输入法：不用配置。VibeWand 的听写键替你按住 Fn，其余交给它。",
                                        "Already using Typeless, Doubao or the like: nothing to set up. VibeWand's dictation button holds Fn for you and the input method does the rest."),
                             tint: .pink, selected: way == .external) { choose(.external) }
            OnboardingChoice(symbol: "apple.logo", title: tr("macOS 自带听写", "macOS dictation"),
                             detail: tr("不用密钥。支持的语言在本机识别，第一次使用时系统会询问麦克风和语音识别权限。",
                                        "No key needed. Supported languages are recognised on this Mac; the first use asks for the microphone and speech recognition."),
                             tint: .pink, selected: way == .system) { choose(.system) }
            OnboardingChoice(symbol: "memorychip", title: tr("本机 SenseVoice", "SenseVoice on this Mac"),
                             detail: tr("不用密钥，录音不出本机，中英混说也认得准。第一次要下载约 240 MB 的模型。",
                                        "No key, the recording never leaves this Mac, and mixed Chinese and English is recognised well. The first use downloads about 240 MB of models."),
                             tint: .pink, selected: way == .local) { choose(.local) }
            OnboardingChoice(symbol: "cloud", title: tr("语音服务 API", "A speech API"),
                             detail: tr("阿里 Qwen 实时语音，或任何兼容 /audio/transcriptions 的服务。边说边出字，还能自动去掉口头语。用你自己的密钥。",
                                        "Alibaba Qwen Realtime, or any service compatible with /audio/transcriptions. Text appears as you speak, and fillers can be tidied away. It uses your own key."),
                             tint: .pink, selected: way == .service) { choose(.service) }
            if way == .service { service }
            if way == .external {
                SettingsNote(text: tr("装好输入法后，在任意输入框里按住设备上的听写键试一下。输入法的触发键需要是 Fn。", "With the input method installed, hold the device's dictation button in any text field. The input method's own trigger needs to be Fn."))
            }
            // SenseVoice is tried once its models are here; until then the one thing to do is fetch them.
            else if way == .local, voice.senseVoice.state != .ready { OnboardingCard { SenseVoiceModels(voice: voice, compact: true) } }
            else { trial }
        }
        .onAppear { keySaved = voice.keySaved }
        .onReceive(voice.$configuration) { draft = $0; keySaved = voice.hasKey(for: $0) }
    }

    private var service: some View {
        OnboardingCard {
            Picker(tr("服务", "Service"), selection: Binding(get: { draft.provider }, set: { draft.selectProvider($0); commit() })) {
                Text(SpeechProvider.qwenRealtime.title).tag(SpeechProvider.qwenRealtime)
                Text(SpeechProvider.transcriptionAPI.title).tag(SpeechProvider.transcriptionAPI)
            }.pickerStyle(.segmented).labelsHidden()
            HStack(spacing: 10) {
                TextField(tr("服务地址", "Endpoint"), text: $draft.endpoint).textFieldStyle(.roundedBorder)
                TextField(tr("模型", "Model"), text: $draft.model).textFieldStyle(.roundedBorder).frame(width: 220)
            }
            HStack(spacing: 10) {
                SecureField(keySaved ? tr("密钥已保存，可输入新的替换", "A key is saved; type a new one to replace it") : tr("输入这个服务的 API Key", "Enter the API key for this service"), text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                Button(tr("保存", "Save")) {
                    model.perform {
                        try model.runtime.updateSpeechConfiguration(draft)
                        if !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try voice.saveKey(keyDraft); keyDraft = "" }
                        keySaved = voice.keySaved
                    }
                }.buttonStyle(.borderedProminent)
            }
            OnboardingStatus(ready: keySaved, text: keySaved ? tr("这个地址的密钥已保存在钥匙串里", "The key for this address is in the Keychain") : tr("还没有保存这个地址的密钥", "No key saved for this address yet"))
        }
    }

    private var trial: some View {
        OnboardingCard {
            HStack(spacing: 14) {
                Label(holding ? tr("松开结束", "Release to finish") : tr("按住这里说一句话", "Hold here and say something"), systemImage: "mic.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 20).frame(height: 44)
                    .background(holding ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Color.pink.gradient), in: Capsule())
                    .scaleEffect(holding ? 1.05 : 1).animation(.spring(duration: 0.25, bounce: 0.4), value: holding)
                    .contentShape(Capsule())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !holding { holding = true; begin() } }
                        .onEnded { _ in holding = false; voice.end() })
                    .accessibilityAddTraits(.isButton)
                Image(systemName: "waveform").font(.system(size: 22)).foregroundStyle(voice.state == .recording ? Color.pink : Color.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: voice.state == .recording)
                Text(voice.displayMessage).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            let heard = voice.liveTranscript.isEmpty ? voice.testTranscript : voice.liveTranscript
            if !heard.isEmpty {
                Text(heard).font(.system(size: 16)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.opacity)
            }
            SettingsNote(text: tr("试出来的字只显示在这里，不会写进任何应用。", "What you try shows here only and is written into no app."))
        }
    }

    private func choose(_ way: Way) {
        switch way {
        case .external: draft.mode = .external
        case .system: draft.mode = .builtIn; draft.selectProvider(.system)
        case .local: draft.mode = .builtIn; draft.selectProvider(.senseVoice)
        case .service:
            draft.mode = .builtIn
            if draft.provider.isLocal { draft.selectProvider(.qwenRealtime) }
        }
        commit()
    }
    private func commit() { model.perform { try model.runtime.updateSpeechConfiguration(draft); keySaved = voice.keySaved } }
    private func begin() {
        model.perform { try model.runtime.updateSpeechConfiguration(draft) }
        voice.beginTest()
    }
}

// MARK: The buttons

struct KeysStep: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var settings: CommandSettings
    @ObservedObject var guide: OnboardingModel
    /// The six inputs every layout has, in the order the hand meets them.
    private static let core: [DeviceControl] = [.voice, .dial, .left, .right, .ok, .escape]
    private var keys: [DeviceTemplateControl] { Self.core.compactMap { control in model.template.controls.first { $0.control == control } } }

    /// Where an action sits on this layout, with the command key as it will be once command mode is live.
    private func bound(_ action: GestureAction) -> String? {
        var layout = model.config
        layout.commandLayer = model.template.commandBindings
        for item in model.template.controls {
            for kind in item.gestures where layout.action(.global, item.control, kind) == action { return "\(kind.label) · \(item.title)" }
        }
        return nil
    }

    var body: some View {
        OnboardingPage(step: .keys, title: tr("认一认按键", "Meet the buttons"),
                       subtitle: tr("这是“\(model.template.title)”现在的布局。同一个键在阅读、编辑和挑选列表时做的事不同，悬浮面板会一直提示眼下每个键是干什么的。",
                                    "This is the “\(model.template.title)” layout as it stands. The same button does different things while reading, editing and picking from a list; the overlay always shows what each one does right now.")) {
            HStack(alignment: .top, spacing: 14) {
                OnboardingDevice(template: model.template, pressed: model.snapshot.pressed, numbered: keys.map(\.control)).frame(width: 250, height: 272)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(keys.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: 9) {
                            Text("\(index + 1)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                .frame(width: 20, height: 20).background(Color.teal.gradient, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.system(size: 13.5, weight: .semibold))
                                Text(item.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).settingsGlass(cornerRadius: 16, prominent: true)
            }
            HStack(alignment: .top, spacing: 18) {
                role(tr("听写", "Dictation"), "waveform", .pink, bound(.dictation) ?? tr("这个布局上没有分配", "Not assigned on this layout"))
                role(tr("命令", "Command"), "sparkles", .purple, bound(.command) ?? tr("用键盘上的命令键", "The keyboard's command key"))
                VStack(alignment: .leading, spacing: 4) {
                    Label(tr("键盘上的命令键", "Command key on the keyboard"), systemImage: "keyboard").font(.system(size: 13, weight: .semibold)).foregroundStyle(.teal)
                    Picker("", selection: Binding(get: { settings.hotkey }, set: { settings.setHotkey($0) })) {
                        ForEach(CommandHotkey.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                Spacer(minLength: 0)
                Button(tr("自定义按键…", "Customise…")) { guide.openSettings?(.devices) }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).settingsGlass(cornerRadius: 16, prominent: true)
            SettingsNote(text: tr("听写和命令都是按住说话、松开结束；命令键要等命令模式配好才生效。每个键的单击、双击、长按和按住都可以在“设备与按键”里改。",
                                  "Dictation and command are both hold to speak, release to finish; the command key is live once command mode is set up. Press, double press, long press and hold of every button can be changed under Devices & inputs."))
        }
    }

    private func role(_ title: String, _ symbol: String, _ tint: Color, _ binding: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            Text(binding).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Command mode

struct CommandStep: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var settings: CommandSettings
    @State private var draft = CommandModel(CommandEndpoint.all[0])
    @State private var busy = false
    @State private var checked: (ok: Bool, detail: String)?
    /// What the installed harness says its version is; nil while it is being asked or when there is none.
    @State private var version: String?
    private var command: CommandController { model.runtime.command }
    private var installed: Harness? { settings.harness(.harness) }
    private var verified: Bool { version.map(Harness.verified.contains) ?? false }

    var body: some View {
        OnboardingPage(step: .command, title: tr("要不要用命令模式", "Command mode, or not"),
                       subtitle: tr("按住命令键说一句话：“切到 Codex 里讨论麦克风的那个会话”“打开备忘录”。一个你选的模型替你找到应用、会话和控件，然后停下。",
                                    "Hold the command key and say it: “switch to the Codex chat about the microphone”, “open Notes”. A model you choose finds the app, the chat or the control, then stops.")) {
            OnboardingCard {
                SettingsToggleRow(title: tr("开启命令模式", "Turn on command mode"), isOn: Binding(get: { settings.enabled }, set: { settings.setEnabled($0) }))
                SettingsNote(text: tr("开启并配好模型后，这些内容会发给你选的模型服务：命令原话，应用、窗口和会话的标题，以及操作界面时控件上的文字。输入框和文档的内容、截图不会发。不配模型就什么都不发，命令键也不起作用。",
                                      "Once it is on and a model is set up, the model service you choose is sent: the words of your command, the titles of apps, windows and chats, and the labels of controls while a window is operated. The contents of fields and documents, and screenshots, are not sent. With no model set up nothing is sent and the command key does nothing."))
            }
            if settings.enabled {
                kernels
                if settings.kernelMode == .builtIn {
                    OnboardingCard { CommandModelBasics(model: model, settings: settings, draft: $draft) { checked = nil } }
                }
                OnboardingCard {
                    Picker(tr("动手之前问不问", "Asking before it acts"), selection: Binding(get: { settings.permission == .ask ? PermissionMode.ask : .risky }, set: { settings.setPermission($0) })) {
                        Text(PermissionMode.risky.title).tag(PermissionMode.risky)
                        Text(PermissionMode.ask.title).tag(PermissionMode.ask)
                    }.pickerStyle(.segmented)
                    SettingsNote(text: (settings.permission == .ask ? PermissionMode.ask : PermissionMode.risky).summary + tr("任何时候按返回键都能停下。", " The back button stops it at any moment."))
                }
                HStack(spacing: 12) {
                    Button(settings.kernelMode == .builtIn ? tr("保存并测试", "Save and test") : tr("测试", "Test"), action: test)
                        .buttonStyle(.borderedProminent).disabled(busy || (settings.kernelMode == .builtIn ? draft.model.isEmpty : installed == nil))
                    if busy { ProgressView().controlSize(.small) }
                    if let checked {
                        Label(checked.detail, systemImage: checked.ok ? "checkmark.circle.fill" : "xmark.octagon.fill").font(.system(size: 13))
                            .foregroundStyle(checked.ok ? Color.green : Color.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                SettingsNote(text: tr("更多选项在“设置 → 命令模式”：思考强度、对话保留多久、让模型看窗口截图、交出 Harness 的全部工具。", "More under Settings → Command mode: reasoning effort, how long a conversation is kept, letting the model see the window, handing over the harness's own tools."))
            }
        }
        .onAppear { draft = settings.model }
        .task { if let installed { version = await command.version(of: installed) } }
    }

    /// The same coordinator either way; what differs is whose DeepSeek Harness runs it.
    private var kernels: some View {
        HStack(alignment: .top, spacing: 12) {
            OnboardingChoice(symbol: "shippingbox", title: tr("用 VibeWand 自带的内核", "The kernel VibeWand ships"),
                             detail: tr("不用再装别的。选一个模型服务，填上你的密钥就能用。", "Nothing else to install. Pick a model service and enter your key."),
                             badge: installed == nil || !verified ? tr("推荐", "Recommended") : "",
                             tint: .purple, selected: settings.kernelMode == .builtIn) { settings.setKernelMode(.builtIn); checked = nil }
            OnboardingChoice(symbol: "puzzlepiece.extension", title: tr("用我装好的 DeepSeek Harness", "My own DeepSeek Harness"),
                             detail: installed == nil ? tr("这台 Mac 上没有找到 DeepSeek Harness。装好它之后可以在设置里改用。", "No DeepSeek Harness was found on this Mac. Once it is installed you can switch to it in Settings.")
                                : verified ? tr("找到了 DeepSeek Harness \(version ?? "")。直接用它里面配好的模型、密钥和登录，对话也能在它的界面里看到。", "Found DeepSeek Harness \(version ?? ""). Its models, keys and sign-ins are used as they are, and conversations show up in its own apps.")
                                : tr("找到了 DeepSeek Harness \(version ?? "…")，但这个版本还没有验证过，可能用不了。", "Found DeepSeek Harness \(version ?? "…"), but this version has not been verified and may not work."),
                             badge: installed != nil && verified ? tr("推荐", "Recommended") : "",
                             tint: .purple, selected: settings.kernelMode == .harness, enabled: installed != nil) { settings.setKernelMode(.harness); checked = nil }
        }
    }

    private func test() {
        if settings.kernelMode == .builtIn {
            model.perform { try settings.setModel(draft); draft = settings.model }
            guard draft == settings.model else { return }
        }
        busy = true; checked = nil
        Task { checked = await command.probe(); busy = false }
    }
}

// MARK: Done

struct DoneStep: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var settings: CommandSettings
    @ObservedObject var guide: OnboardingModel
    private var voice: VoiceInputController { model.runtime.voiceInput }

    var body: some View {
        OnboardingPage(step: .done, title: tr("可以开始用了", "Ready to use"),
                       subtitle: tr("下面是现在的状态。没配好的随时回来补，或者在设置里改。", "This is where things stand. Come back to whatever is not ready, or change it in Settings.")) {
            OnboardingCard {
                line(.access, ready: model.runtime.adapter.trusted,
                     text: model.runtime.adapter.trusted ? tr("辅助功能已授权", "Accessibility is allowed") : tr("还没有辅助功能权限，按键不会起作用", "Accessibility is not allowed yet; the buttons will do nothing"))
                Divider()
                line(.device, ready: model.snapshot.connected,
                     text: model.snapshot.connected ? tr("\(model.template.title) 已连接", "\(model.template.title) is connected") : tr("还没有连上设备，键盘上的命令键可以先用", "No device connected yet; the keyboard's command key works meanwhile"))
                Divider()
                line(.voice, ready: voiceReady, text: voiceLine)
                Divider()
                line(.command, ready: !settings.enabled || settings.active, text: commandLine)
            }
            OnboardingCard {
                Label(tr("试一试", "Try it"), systemImage: "hand.wave").font(.system(size: 15, weight: .semibold))
                SettingsNote(text: tr("在任意输入框里按住听写键说一句话，松开看字。", "In any text field, hold the dictation button, say something, release and read."))
                if settings.active {
                    SettingsNote(text: tr("按住命令键说“打开备忘录”，看悬浮面板上它在做什么。", "Hold the command key and say “open Notes”, and watch the overlay show what it is doing."))
                }
                SettingsNote(text: tr("悬浮面板一直显示每个键眼下的作用；菜单栏的旋钮图标可以打开设置。", "The overlay always shows what each button does right now; the dial icon in the menu bar opens Settings."))
            }
            HStack {
                Button(tr("打开完整设置", "Open full settings")) { guide.openSettings?(.general) }
                SettingsNote(text: tr("这份引导之后可以在“设置 → 通用”里重新打开。", "This guide can be opened again under Settings → General."))
            }
        }
    }

    private var voiceReady: Bool {
        let configuration = voice.configuration
        return configuration.mode == .external || configuration.provider == .system || voice.keySaved
    }
    private var voiceLine: String {
        let configuration = voice.configuration
        if configuration.mode == .external { return tr("听写交给你的语音输入法", "Dictation is left to your voice input method") }
        if configuration.provider == .system { return tr("听写用 macOS 自带听写", "Dictation uses macOS dictation") }
        return voice.keySaved ? tr("听写用 \(configuration.provider.title)", "Dictation uses \(configuration.provider.title)") : tr("语音服务还没有保存密钥", "The speech service has no key saved yet")
    }
    private var commandLine: String {
        if !settings.enabled { return tr("命令模式没有开启", "Command mode is off") }
        if settings.active { return tr("命令模式已就绪：", "Command mode is ready: ") + settings.modelName }
        return settings.kernelMode == .harness ? tr("命令模式找不到已安装的 DeepSeek Harness", "Command mode finds no installed DeepSeek Harness") : tr("命令模式还差模型或密钥", "Command mode still needs a model or its key")
    }

    private func line(_ step: OnboardingStep, ready: Bool, text: String) -> some View {
        HStack(spacing: 10) {
            OnboardingStatus(ready: ready, text: text)
            Spacer(minLength: 8)
            if !ready { Button(tr("去设置", "Set it up")) { withAnimation(.spring(duration: 0.5, bounce: 0.18)) { guide.go(to: step) } }.controlSize(.small) }
        }
    }
}
