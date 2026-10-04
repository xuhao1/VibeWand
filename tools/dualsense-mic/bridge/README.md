# DualSense 蓝牙麦克风实验版

本机程序：`output/dualsense-mic/VibeWand Mic.app`。

1. 拔掉手柄 USB 数据线，通过蓝牙连接 DualSense；休眠后按 PS 键重连。
2. 打开程序，等待“已发布麦克风”，点击“开始”。
3. 在语音应用里选择 **VibeWand DualSense Mic**。
4. 用完点击“停止”。关闭窗口或 ⌘Q 会停止并退出。

采集期间临时开启 Apple 游戏模式，并独占手柄，**原有手柄导航暂停**。停止后恢复游戏模式原策略；程序从不切换系统默认麦克风。首次被语音应用读取时可能需要系统音频录制授权：tap 只选择本程序的音频进程，不选择其他应用或系统混音。程序静音自己的输出，避免把手柄声音送回扬声器。

这仍是实验版：声学 A/B 中缺帧从约 58% 降至约 4.8%，残余缺口由 Opus PLC 补偿。100 ms 预缓冲会增加延迟；不保证无断续、音乐保真或所有手柄固件可用。仅测试普通 DualSense `054c:0ce6`。没有整合主项目的按钮触发/导航，也没有验证所有语音应用。

当前打包版本面向 Apple Silicon、macOS 26+，内置本机的 libopus 和版权说明。游戏模式控制仍依赖本机 Xcode/Command Line Tools 中的 `gamepolicyctl`。底层 Core Audio tap API 自 macOS 14.2 可用，但本包及依赖没有按旧系统编译或测试。程序为本地临时签名，未公证。

正常停止、窗口关闭、SIGTERM/SIGINT/SIGHUP 会执行关闭和恢复。强制 SIGKILL、系统崩溃或不可恢复的 OS 写入阻塞无法保证恢复；本次环境原策略是 `auto`，必要时用原来的策略恢复游戏模式。下一次启动只清理本程序 UID 的残留临时端点，单实例锁防止两个程序同时争用。退出会移除临时麦克风；部分语音应用可能需要重新打开输入菜单。

## 构建与测试

```sh
sh tools/dualsense-mic/bridge/build.sh
```

构建需要 Xcode 命令行工具及 `/opt/homebrew` 下的 opus。构建脚本不会安装依赖，不修改主项目的 Package.swift。

“验证系统输入”按钮会在程序内部生成低幅度正弦波，经静音 tap 再从 aggregate input 读取；不会播放到扬声器，不启用手柄麦克风。它验证发布的输入能交付样本，不能代替真实手柄/语音验收。

开发命令行参数（先退出已运行的实例）：

- `--test-seconds 32`：短时采集后自动停止，把解码/补帧后的音频写到工作目录的 `microphone-test.wav`。
- `--capture-system`：同时保存真正从 Core Audio 读出的 `system-microphone-test.wav`。
- `--no-game-mode`：仅用于默认策略对照，通常会出现大量缺帧。

这些录音文件名会被下次开发测试覆盖；要保留时先另存。日常点击“开始”不会保存录音文件。

`analyze-audio.py` 生成已知信号并做本地频谱/互相关分析，依赖 NumPy、SciPy 和 Matplotlib。`run-acoustic-ab.py` 在 `output/dualsense-mic` 内执行两轮已知信号播放及采集，**会发出声音并保存录音**；确认手柄靠近扬声器、场景允许播放后使用。它先等待有效音频报告，再播放刺激，避免休眠空测。`plot-comparison.py` 汇总两轮结果。

录音和原始中间文件保持在被 Git 忽略的 output 目录。没有网络音频上传或语音转写。

## 实现与验证

- 原生 IOHID 独占接入，独立串行写线程，正确区分麦克风和控制报告。
- 输入 CRC 校验，持续 Opus 解码，八位序号识别短缺口和重复包。
- 单生产者/单消费者 C 环形缓冲，渲染线程不阻塞、不分配内存；100 ms 预缓冲、过期数据裁剪和静音清空。
- AVAudioEngine → 仅本程序的静音 process tap → Core Audio 聚合输入。
- Game Mode 原策略记录/恢复；没有 SIP、驱动替换或管理员安装。
- 离线协议/缓冲测试、真实短时与一分钟接收、真人首版反馈、已知刺激 A/B、真正系统输入录制、正常停止和退出验证。

参考 [ControlDeck](https://github.com/ihansel/control-deck)、[DS5Dongle](https://github.com/awalol/DS5Dongle)、[DS4Windows](https://github.com/hbashton/DS4Windows) 的协议/架构资料，以及 Apple 的 Core Audio tap 示例；本目录为独立的本机原型。Opus 的版权说明随构建产物保存。
