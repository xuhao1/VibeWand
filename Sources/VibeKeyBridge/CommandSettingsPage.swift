import AppKit
import SwiftUI
import WandAgent

private func tr(_ zh: String, _ en: String) -> String { L10n.tr(zh, en) }

struct CommandSettingsPage: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var settings: CommandSettings
    @State private var keyDraft = ""
    @State private var modelDraft = ""
    @State private var askingToEnable = false

    private static let disclosure = (
        "开启后，这些内容会离开这台 Mac，发给你在下面配置的模型服务：你说出的命令原话；应用、窗口和会话的标题，项目文件夹名；操作界面时前台窗口里控件上的文字。输入框和文档的内容、选中的文字不会发给它。",
        "When this is on, the following leaves this Mac for the model service you configure below: the words of your command; the titles of apps, windows and chats, and project folder names; the labels of controls in the front window when the interface is operated. The contents of fields and documents, and selected text, are not sent to it."
    )

    var body: some View {
        StandardPage(title: tr("命令模式", "Command mode"),
                     subtitle: tr("按住命令键说一句话，VibeWand 替你找到应用、会话或控件。", "Hold the command key and say what you want. VibeWand finds the app, chat or control.")) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    SettingsCard(title: tr("开关", "Switch")) {
                        SettingsToggleRow(title: tr("开启命令模式", "Turn on command mode"), isOn: Binding(
                            get: { settings.enabled },
                            set: { if $0 { askingToEnable = true } else { settings.setEnabled(false) } }))
                        SettingsNote(text: tr(Self.disclosure.0, Self.disclosure.1))
                        SettingsNote(text: tr("它只做导航和界面操作：打开、切换、按下控件、把文字放进输入框。它不会替你发送或提交；删除、发送这类控件每次都等你按确认键。",
                                              "It only navigates and operates the interface: opening, switching, pressing controls, putting text in a field. It never sends or submits for you, and controls that delete or send wait for your confirm key every time."))
                    }
                    SettingsCard(title: tr("模型", "Model")) {
                        Label(Self.kernelReady ? tr("命令内核已就绪（DeepSeek Harness）", "Command kernel ready (DeepSeek Harness)")
                                               : tr("此版本未包含命令内核", "This build does not include the command kernel"),
                              systemImage: Self.kernelReady ? "checkmark.circle" : "exclamationmark.triangle").font(.system(size: 14, weight: .medium))
                        Divider()
                        Label(settings.keySaved ? tr("DeepSeek 密钥已保存", "DeepSeek key saved") : tr("尚未保存 DeepSeek 密钥", "No DeepSeek key saved"),
                              systemImage: settings.keySaved ? "checkmark.seal" : "key").font(.system(size: 14, weight: .medium))
                        SecureField(tr("输入 DeepSeek API Key", "Enter a DeepSeek API key"), text: $keyDraft).textFieldStyle(.roundedBorder)
                        HStack {
                            Button(tr("保存密钥", "Save key")) { model.perform { try settings.saveKey(keyDraft); keyDraft = "" } }
                                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button(tr("删除密钥", "Delete key")) { model.perform { try settings.removeKey() } }.disabled(!settings.keySaved)
                        }
                        SettingsNote(text: tr("密钥保存在此 Mac 的钥匙串中，只在启动命令内核时交给它。费用由你的 DeepSeek 账户承担。",
                                              "The key is kept in this Mac's Keychain and handed to the command kernel only when it starts. Usage is billed to your DeepSeek account."))
                        Divider()
                        HStack {
                            TextField("deepseek-v4-flash", text: $modelDraft).textFieldStyle(.roundedBorder)
                            Button(tr("使用此模型", "Use this model")) { settings.setModel(modelDraft) }.disabled(modelDraft == settings.model)
                        }
                        SettingsNote(text: tr("留空使用默认模型。", "Leave empty for the default model."))
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(spacing: 16) {
                    SettingsCard(title: tr("命令键", "Command key")) {
                        SettingsNote(text: tr("按住说话，松开执行。VibeKey：长按旋钮并保持（开启后，模型入口改为长按 OK）。手柄：按住 L2。",
                                              "Hold to speak, release to run. VibeKey: long-press the dial and keep holding (the model entry moves to a long press of OK while this is on). Controller: hold L2."))
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
                    SettingsCard(title: tr("本机记录", "Records on this Mac")) {
                        SettingsNote(text: tr("每条命令的原话和执行步骤保存在本机，14 天后自动删除，不含界面读取结果。内核的对话日志只保留最近一次启动的。",
                                              "The words of each command and the steps taken are kept on this Mac and deleted after 14 days. They do not include what was read from windows. The kernel's conversation log is kept only for its latest start."))
                        HStack {
                            Button(tr("在访达中显示", "Show in Finder")) {
                                let folder = model.runtime.command.support
                                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                                NSWorkspace.shared.activateFileViewerSelecting([folder])
                            }
                            Button(tr("清除全部记录", "Clear all records")) { model.runtime.command.clearRecords() }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { modelDraft = settings.model }
        .alert(tr("开启命令模式？", "Turn on command mode?"), isPresented: $askingToEnable) {
            Button(tr("开启", "Turn on")) { settings.setEnabled(true) }
            Button(tr("取消", "Cancel"), role: .cancel) {}
        } message: { Text(tr(Self.disclosure.0, Self.disclosure.1)) }
    }

    private static var kernelReady: Bool { CommandController.install() != nil }
}
