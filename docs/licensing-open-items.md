# 许可与版权遗留项 / Licensing and copyright: open items

[文档目录 / Documentation](README.md) · [第三方记录 / Third-party notices](../third-party/README.md) · [许可证 / License](../LICENSE)

截至 2026-10-06，VibeWand 0.10.0。仓库目前是私有的，0.10.0 带着下面这些没有处理的项发布在这个私有仓库里；0.10.1 和 0.10.2 的内核包没有变，带着同样的这些项。作者当天的决定：这些问题留到正式开源之前处理。处理完一项，就在这里改掉它的状态，并同步修改[第三方记录](../third-party/README.md)。本文是工程上的盘点，不是法律意见。

As of 2026-10-06, VibeWand 0.10.0. The repository is private, and 0.10.0 is published there with the items below still open; 0.10.1 and 0.10.2 have the same kernel packages and carry the same items. The owner decided that day to settle them before the project is opened. When an item is settled, change its status here and bring the [third-party notice](../third-party/README.md) in line. This is an engineering inventory, not legal advice.

| # | 遗留项 / Item | 要定的事 / What has to be decided | 状态 / Status |
| --- | --- | --- | --- |
| 1 | sherpa-onnx 的预编译库里有 GPL 的 eSpeak NG / eSpeak NG (GPL) inside sherpa-onnx's prebuilt library | 换成不含语音合成的构建，还是照原样分发并补齐 GPL 的要求 / swap in the build without speech synthesis, or ship as it is and meet the GPL | 未处理 / open |
| 2 | libvips 及其内置库是 LGPL / libvips and the libraries built into it (LGPL) | 保留并补齐 LGPL 的要求，还是自带内核不带图片存储 / keep it and meet the LGPL, or leave the picture store out of the shipped kernel | 未处理 / open |
| 3 | 一批许可文本和声明还没有随包附上 / License texts and notices not yet in the bundle | 取齐文本 / collect the texts | 未处理 / open |
| 4 | SenseVoice 模型的协议要求署名 / The SenseVoice models' terms ask for attribution | 在下载处和文档里写明作者与协议 / state author and terms where the download is offered | 未处理 / open |
| 5 | VibeWand 自己的许可 / VibeWand's own license | “开源”用哪个许可；与 GPL 组件的关系；外部贡献的授权 / which license “open” means, how it sits with GPL components, how contributions are licensed | 未处理 / open |
| 6 | 设备插画、图标和文档图片 / Device artwork, icon and documentation images | 是否需要进一步核对或替换 / whether any needs clearing or replacing | 未核对 / not checked |
| 7 | 名称与商标 / Names and trademarks | 免责声明是否扩展到被操作的应用；“VibeKey”的用法 / extend the disclaimer to the apps operated; the use of “VibeKey” | 未处理 / open |
| 8 | AU05 协议里的密钥常量 / The key constants of the AU05 protocol | 公开是否合适 / whether publishing them is appropriate | 未处理 / open |

## 1. sherpa-onnx 预编译库里的 eSpeak NG（GPL-3.0-or-later）

**在哪。**`Contents/Resources/kernel/node_modules/sherpa-onnx-darwin-arm64/libsherpa-onnx-c-api.dylib`，sherpa-onnx 1.13.8，0.10.0 起随本机 SenseVoice 听写引入。

**情况。**两个 sherpa-onnx 包标的是 Apache-2.0，但这个库里还静态编入了十个别的库，其中语音合成用的 eSpeak NG 是 GPL-3.0-or-later（`csukuangfj/espeak-ng`，提交 `ed530aa1`）。VibeWand 只做识别，从不调用合成的代码，但代码在随包分发的库里。核对的依据：库里有 eSpeak NG 自己的函数（`espeak_ng_Initialize`、`TranslateRules`、`LoadPhData` 等）；sherpa-onnx 1.13.8 的 `CMakeLists.txt` 在 `SHERPA_ONNX_ENABLE_TTS` 打开（默认）时引入 `espeak-ng-for-piper`；eSpeak NG 在那次提交上的 README 写的是 GPL 3 或更高。

**0.10.0 的现状。**照原样带着这个库，没有附 GPL 3.0 的文本，也没有写 eSpeak NG 的源码出处。

**出路。**

- (a) 组装内核时只把这一个库换成 sherpa-onnx 随同一版本发布的不含语音合成的构建：`sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib.tar.bz2`，8.3 MB，在它的 v1.13.8 发布页上。按它的构建文件，关掉合成后不会编入 eSpeak NG 和 piper-phonemize；它的 C 接口对合成函数保留空实现，Node 插件应当仍能加载。**还没有试过**，换完要重新实测 SenseVoice。
- (b) 照原样分发：附上 GPL 3.0 的文本、eSpeak NG 的源码出处，以及它自带的 `COPYING.APACHE`、`COPYING.BSD2`、`COPYING.UCD`。
- (c) 自带内核不带识别程序：SenseVoice 只在用户装了 DeepSeek Harness 时可用，要另写一条经 Harness 自己的运行时启动识别程序的路径。

实现者的建议是 (a)：去掉一段用不到的 GPL 代码，比为它承担分发义务简单。

**The library.** `Contents/Resources/kernel/node_modules/sherpa-onnx-darwin-arm64/libsherpa-onnx-c-api.dylib`, sherpa-onnx 1.13.8, shipped since 0.10.0 for SenseVoice dictation on this Mac. The two sherpa-onnx packages state Apache-2.0, but ten other libraries are built into this file, and one of them, eSpeak NG for speech synthesis, is under GPL-3.0-or-later (`csukuangfj/espeak-ng` at `ed530aa1`). VibeWand only recognises speech and never calls the synthesis code, but that code is in the library that ships. Evidence: the file holds eSpeak NG's own functions (`espeak_ng_Initialize`, `TranslateRules`, `LoadPhData` and more); sherpa-onnx 1.13.8's `CMakeLists.txt` includes `espeak-ng-for-piper` when `SHERPA_ONNX_ENABLE_TTS` is on, the default; eSpeak NG's README at that commit says GPL version 3 or later.

**In 0.10.0** the library ships as published, without the GPL 3.0 text and without a pointer to eSpeak NG's source.

**Ways out.** (a) At kernel assembly, replace this one library with the build sherpa-onnx publishes without speech synthesis, `sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib.tar.bz2` (8.3 MB, on its v1.13.8 release page). By its build files that build leaves eSpeak NG and piper-phonemize out, and its C API keeps empty implementations of the synthesis functions, so the Node add-on should still load. **Not tried yet**; SenseVoice has to be tested again after the swap. (b) Ship as it is, with the GPL 3.0 text, a pointer to eSpeak NG's source and its own `COPYING.APACHE`, `COPYING.BSD2` and `COPYING.UCD`. (c) Leave the recogniser out of the shipped kernel: SenseVoice then works only with a DeepSeek Harness the user installed, through a path that starts the recogniser on the harness's own runtime and has yet to be written. The implementer recommends (a): removing GPL code that is never used is simpler than taking on its terms.

## 2. libvips 及其内置库（LGPL-3.0-or-later）

**在哪。**`Contents/Resources/kernel/node_modules/@img/sharp-libvips-darwin-arm64/lib/libvips-cpp.8.18.7.dylib`（包版本 1.3.4，18 MB）。0.10.0 起，由 DeepSeek Harness 的图片存储组件 `@deepseek-ai/dsh-attachment-local` 经 sharp 0.35.5 引入；命令模式的窗口截图靠它把图存进对话。

**情况。**包标的是 LGPL-3.0-or-later。它旁边的 `README.md` 列出了编进去的每个库：libvips、glib、pango、librsvg、libheif、libexif、fribidi、proxy-libintl 按 LGPLv3 使用，cairo 是 MPL 1.1，其余是 BSD、MIT、zlib 一类；`versions.json` 给出版本。包里没有 LGPL 和 GPL 的文本。这份清单取自包自己的说明，没有另外对二进制做核对。

**0.10.0 的现状。**未修改、作为单独的动态库随包分发，只在给模型看图时加载；没有附 LGPL 3.0 和 GPL 3.0 的文本。

**出路。**

- (a) 保留：附上 LGPL 3.0 和 GPL 3.0 的文本，写明源码出处（构建配方在 [lovell/sharp-libvips](https://github.com/lovell/sharp-libvips)），并说明用户怎样换上自己构建的库。它是独立的动态库，可以替换；替换后应用的签名会失效，要写明怎样重新签名。
- (b) 自带内核去掉图片存储组件：窗口截图只在插件模式下可用。

**The library.** `Contents/Resources/kernel/node_modules/@img/sharp-libvips-darwin-arm64/lib/libvips-cpp.8.18.7.dylib` (package 1.3.4, 18 MB), shipped since 0.10.0. It comes with sharp 0.35.5, which DeepSeek Harness's picture store `@deepseek-ai/dsh-attachment-local` uses; command mode's window picture is kept with the conversation through it. The package states LGPL-3.0-or-later. The `README.md` beside the library lists everything built into it: libvips, glib, pango, librsvg, libheif, libexif, fribidi and proxy-libintl used under LGPLv3, cairo under MPL 1.1, the rest under BSD, MIT and zlib style licenses; `versions.json` gives the versions. Neither the LGPL nor the GPL text is in the package. This list is the package's own; the binary was not inspected separately.

**In 0.10.0** it ships unmodified as a separate dynamic library, loaded only when the model is shown a picture, without the LGPL 3.0 and GPL 3.0 texts.

**Ways out.** (a) Keep it: add the LGPL 3.0 and GPL 3.0 texts, name the source (the build recipes are at [lovell/sharp-libvips](https://github.com/lovell/sharp-libvips)) and say how a user puts in a build of their own. The library is separate and replaceable; replacing it breaks the app's signature, so the note has to say how to sign again. (b) Leave the picture store out of the shipped kernel: window pictures then work in plugin mode only.

## 3. 还没有随包附上的许可文本和声明 / Texts and notices not yet in the bundle

**编进 `libsherpa-onnx-c-api.dylib` 的库**（清单取自 sherpa-onnx 1.13.8 的 `cmake` 目录，并核对过库里确有各自的代码）：

| 库 / Library | 许可 / License | 状态 / Status |
| --- | --- | --- |
| kaldi-native-fbank 1.22.3、kaldi-decoder 0.3.0、kaldifst 1.8.0、OpenFst、simple-sentencepiece 0.7 | Apache-2.0 | 许可文本与 `third-party/sherpa-onnx-LICENSE` 相同；各自的版权声明没有单列 / same license text as `third-party/sherpa-onnx-LICENSE`; their own copyright lines are not listed |
| JSON for Modern C++ 3.12.0 | MIT | 文本未附 / text missing |
| hclust-cpp（2026-02-25） | BSD-2-Clause | 文本未附 / text missing |
| Eigen 5.0.1 | MPL-2.0 | 第三方记录里写了源码出处 / the notice names the source |
| piper-phonemize（`f3ff95af`） | MIT | 文本未附；选 1(a) 后不再包含 / text missing; gone with 1(a) |
| eSpeak NG | GPL-3.0-or-later | 见第 1 项 / see item 1 |

**九个发布时没有带许可文件的 npm 包**，许可只写在各自的 `package.json` 里，文本要从它们的仓库取 / **nine npm packages published without a license file**, whose license is named only in their `package.json`; the texts have to come from their repositories:

| 包 / Package | 许可 / License |
| --- | --- |
| `@aws-sdk/credential-provider-http` 3.972.74、`@aws-sdk/credential-provider-login` 3.972.79、`@aws-sdk/nested-clients` 3.997.46 | Apache-2.0 |
| `@earendil-works/pi-ai` 0.87.1、`@earendil-works/pi-telemetry` 0.87.1 | MIT |
| `@koromix/koffi-darwin-arm64` 3.1.1 | MIT（同版本的 `koffi` 包带着 `LICENSE.txt` / the `koffi` package of the same version carries `LICENSE.txt`） |
| `data-uri-to-buffer` 4.0.1、`proxy-agent-negotiate` 1.1.0、`standardwebhooks` 1.1.1 | MIT |

第 1、2 项如果选择保留，GPL 3.0 和 LGPL 3.0 的文本也在这一项里。内核的包升级后，这两张表要重新核对。

If items 1 and 2 are settled by keeping the libraries, the GPL 3.0 and LGPL 3.0 texts belong here too. Both tables have to be checked again whenever the kernel's packages change.

## 4. SenseVoice 的模型 / The SenseVoice models

模型不随应用分发，也不在仓库里。用户点“下载并准备”时，VibeWand 从 Hugging Face 或其镜像下载 DeepSeek Harness 的 SenseVoice 插件指定的文件：`csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`（SenseVoiceSmall 的转换版）和 `csukuangfj/vad`（Silero VAD）。

- 转换版仓库的 `LICENSE` 只有一行，指向 FunASR 的许可说明。原模型 `FunAudioLLM/SenseVoiceSmall` 标的是 [FunASR Model Open Source License Agreement 1.1](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE)（阿里巴巴）：使用、复制、修改和分享时必须注明出处和作者，并保留模型名称；它不是 OSI 许可，另有“不得无端诋毁”的条款，违反即终止。
- Silero VAD 的上游 `snakers4/silero-vad` 是 MIT；`csukuangfj/vad` 这个仓库本身没有任何许可说明。
- 现状：第三方记录写了两个模型的出处；设置页的下载处和首次引导里没有显示作者和协议。
- 要做：在下载处和语音输入文档里写明模型的名称、作者和协议链接；确认 VAD 文件的出处与许可。

The models are neither shipped nor stored in the repository. When the user asks, VibeWand downloads the files that DeepSeek Harness's SenseVoice plug-in pins, from Hugging Face or its mirror: `csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` (a conversion of SenseVoiceSmall) and `csukuangfj/vad` (Silero VAD). The conversion's `LICENSE` is one line pointing at FunASR's license section. The original model, `FunAudioLLM/SenseVoiceSmall`, is under the [FunASR Model Open Source License Agreement 1.1](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE) (Alibaba): whoever uses, copies, modifies or shares it must attribute the source and author and keep the model names; it is not an OSI license, and it ends for anyone who “unjustifiably denigrates” the model. Silero VAD's upstream, `snakers4/silero-vad`, is MIT; the repository `csukuangfj/vad` states no license at all. Today the third-party notice names both sources, while the download in Settings and in the first-run guide shows neither author nor terms. To do: name the model, its author and its terms where the download is offered and in the voice input guide, and confirm where the VAD file comes from and under what terms.

## 5. VibeWand 自己的许可 / VibeWand's own license

- **“开源”用哪个许可。**源码现在采用 [PolyForm Noncommercial 1.0.0](../LICENSE)，文件末尾有作者的 `Required Notice`。两份 README 已经写明这是源码公开，不是 OSI 定义的开源。正式公开前要定：沿用它，还是换成一个 OSI 许可。
- **与 GPL、LGPL 组件的关系。**第 1、2 项如果保留，一个非商用许可的应用就和 GPL、LGPL 的库装在同一个包里。识别程序在自己的进程里运行，经本机回环地址与 VibeWand 通信，VibeWand 自己的代码不链接它；加载那个库的是 Harness 的插件（MIT）和 sherpa-onnx 的 Node 插件（Apache-2.0）。这样分发是否满足 GPL，需要有资格的人看过。选 1(a) 就没有这个问题；libvips 的 LGPL 只要求第 2 项里的那几件事。
- **外部贡献。**[贡献说明](../CONTRIBUTING.md)只要求贡献者先读许可证，没有约定贡献内容怎样授权。README 说商用授权由作者单独给出；要对含有他人贡献的代码这样做，需要贡献者协议或等效的条款。

**Which license “open” means.** The source is under [PolyForm Noncommercial 1.0.0](../LICENSE), with the author's `Required Notice` at the end of the file, and both READMEs already say this is source-available rather than open source as the OSI defines it. Before the project is opened: keep it, or move to an OSI license. **How it sits with GPL and LGPL components.** If items 1 and 2 are settled by keeping the libraries, an app under a noncommercial license travels in one bundle with GPL and LGPL libraries. The recogniser runs in a process of its own and talks to VibeWand over the loopback address; VibeWand's own code does not link it, and what loads the library is the harness's plug-in (MIT) and sherpa-onnx's Node add-on (Apache-2.0). Whether that way of distributing meets the GPL needs someone qualified to look at it. With 1(a) the question goes away; libvips's LGPL asks only for what item 2 lists. **Contributions.** [CONTRIBUTING.md](../CONTRIBUTING.md) asks contributors to read the license and takes no license from them. The README says commercial licenses come from the author; granting one over code that holds other people's contributions needs a contributor agreement or equivalent terms.

## 6. 设备插画、图标和文档图片 / Device artwork, icon and documentation images

- **设备插画**（`assets/device/`，随包分发）。三张图都由图像生成工具生成，不带厂商标志。`controller.png` 生成时参考过厂商的 AU05 产品页，手柄那张的提示词要的是“可辨认的 PS5 风格轮廓”。[`assets/device/README.md`](../assets/device/README.md) 自己写着：反复修改不等于版权清理。外观设计方面没有做过核对。
- **应用图标和首页场景图。**AI 生成，来源和提示词记录在 [`assets/app-icon/README.md`](../assets/app-icon/README.md) 和 [`docs/images/README.md`](images/README.md)。没有核对所用工具对生成图像的条款，AI 生成图像的权利在各地规定不同。
- **文档里第三方应用的截图**，例如 `docs/images/terminal-v084-codex.jpg`（iTerm2 里的 Codex CLI）。

**Device artwork** (`assets/device/`, shipped in the app): the three pictures were made with an image generation tool and carry no maker's mark. `controller.png` was generated with the maker's AU05 product sheet viewed as a reference, and the prompt for the gamepad asks for “a recognizable PS5-style silhouette”. [`assets/device/README.md`](../assets/device/README.md) itself says that repeated editing is not proof of clearance. Nothing has been checked on the side of design rights. **App icon and hero images**: generated, with sources and prompts recorded in [`assets/app-icon/README.md`](../assets/app-icon/README.md) and [`docs/images/README.md`](images/README.md); the terms of the tool for generated images were not checked, and rights in generated images differ by country. **Screenshots of other apps in the documentation**, such as `docs/images/terminal-v084-codex.jpg` (Codex CLI in iTerm2).

## 7. 名称与商标 / Names and trademarks

- README 和设备文档里的免责声明只提到设备厂商（Ulanzi、Sony、小米）。被操作的应用的厂商（OpenAI、Anthropic、DeepSeek、腾讯、字节跳动等）没有提到。
- “VibeKey”是 Ulanzi 那款产品的名称，这里用作一套模板的名字；内部 target 叫 `VibeKeyBridge`，bundle ID 是 `org.vibekey.bridge`。

The disclaimers in the READMEs and the device guide name device makers only (Ulanzi, Sony, Xiaomi). The makers of the apps VibeWand operates (OpenAI, Anthropic, DeepSeek, Tencent, ByteDance and others) are not mentioned. “VibeKey” is the name of Ulanzi's product and is used here as the name of a template; the internal target is `VibeKeyBridge` and the bundle identifier `org.vibekey.bridge`.

## 8. AU05 协议里的密钥常量 / The key constants of the AU05 protocol

`Sources/AU05Device/Protocol.swift` 里报文的加解密、命令格式和按键标识改编自 [AU05 Keys](https://github.com/elliclee/ulanzi-au05-keys)（MIT，许可文本已保留在 `third-party/AU05-Keys-LICENSE`）。其中有设备报文加密用的四个密钥常量。仓库和安装包里没有 Ulanzi 的任何二进制或固件。公开这些常量是否合适，由作者判断。

The report cipher, command formats and button identifiers in `Sources/AU05Device/Protocol.swift` are adapted from [AU05 Keys](https://github.com/elliclee/ulanzi-au05-keys) (MIT, text kept as `third-party/AU05-Keys-LICENSE`). They include the four key constants of the device's report cipher. No Ulanzi binary or firmware is in the repository or the package. Whether publishing the constants is appropriate is the owner's call.

## 没有核对的 / Not checked

- 宣传视频和它的素材（在别的分支上，不在这次盘点里）：旁白的合成语音、第三方应用的画面、音乐。
- 项目主页上的内容。
- 内核里其余的预编译插件（koffi、sharp 的 `.node`、`node-addon-require-builtin`、Harness 的 `system.node`）：看过它们链接的库和内含的字符串，没有发现编入别的项目，但没有逐个对照构建文件。
- Node.js 的 `LICENSE` 涵盖它内置的库，没有逐项核对。
- DeepSeek Harness 自己的 79 个包和其余第三方包：按 `package.json` 里的许可和包内是否带许可文件统计，没有逐个读内容。
- 语音服务、模型服务这类用户自己配置的外部服务的条款。

- The promo film and its material (on other branches, outside this inventory): the synthetic narration voices, footage of other apps, music.
- What the project site shows.
- The other prebuilt add-ons in the kernel (koffi, sharp's `.node`, `node-addon-require-builtin`, the harness's `system.node`): their linkage and strings show nothing else built in, but they were not compared with their build files.
- Node.js's `LICENSE` covers the libraries built into it; not checked entry by entry.
- DeepSeek Harness's own 79 packages and the remaining third-party packages: counted by the license in `package.json` and by whether a license file is present, not read one by one.
- The terms of services the user sets up themselves, such as speech and model services.

## 已经齐全的 / Already in order

供对照：AU05 Keys 的 MIT 文本、Opus 的版权与许可声明、Node.js 的 `LICENSE`（在 `kernel/node/` 下）、sherpa-onnx 的 Apache License 2.0、ONNX Runtime 1.28.2 的许可和它的第三方声明，以及其余 131 个第三方 npm 包各自带着的许可文件，都随应用分发。VibeWand 的 `LICENSE` 也在包里。

For reference, these ship with the app: AU05 Keys's MIT text, Opus's copyright and license notices, Node.js's `LICENSE` (under `kernel/node/`), sherpa-onnx's Apache License 2.0, ONNX Runtime 1.28.2's license with its third-party notices, and the license files that the other 131 third-party npm packages carry themselves. VibeWand's own `LICENSE` is in the bundle as well.
