# 许可与版权遗留项 / Licensing and copyright: open items

[文档目录 / Documentation](README.md) · [第三方记录 / Third-party notices](../third-party/README.md) · [许可证 / License](../LICENSE)

截至 2026-10-07。0.10.0 到 0.11.0 带着下面这些项发布在私有仓库里，当时采用的是 PolyForm Noncommercial 1.0.0。作者 2026-10-07 为正式开源做了决定：VibeWand 改用 GPL-3.0，另由作者提供商业授权；两个带 copyleft 的库都保留。第 1 到 5 项据此处理完；第 7 项里的标识符当天也改了；作者确认版权归他本人，源码出处指向上游仓库即可。第 8 项作者当天决定照常公开；第 6 项里手柄图已重画并经作者认可，其余图片仍未核对。已经发出去的那些版本，仍按发布时的条款。本文是工程上的盘点，不是法律意见。

As of 2026-10-07. Versions 0.10.0 to 0.11.0 were published in the private repository with the items below open, under PolyForm Noncommercial 1.0.0. On 2026-10-07 the owner decided, for opening the project: VibeWand moves to the GPL-3.0 with a commercial license available from the author, and both copyleft libraries stay. Items 1 to 5 are settled accordingly, and the identifiers in item 7 were renamed the same day; the owner confirmed that the copyright is his and that pointing at the upstream repositories for source is enough. The owner decided the same day to publish the constants of item 8 as they are; in item 6 the controller picture was redrawn and approved by him, and the other pictures remain unchecked. Copies already released keep the terms they were released under. This is an engineering inventory, not legal advice.

| # | 事项 / Item | 结果 / Outcome | 状态 / Status |
| --- | --- | --- | --- |
| 1 | sherpa-onnx 的预编译库里有 GPL 的 eSpeak NG / eSpeak NG (GPL) inside sherpa-onnx's prebuilt library | 照原样保留；GPL 文本、它自带的声明和源码出处已附 / kept as published, with the GPL text, its own notices and its source named | 已定 / settled |
| 2 | libvips 及其内置库是 LGPL / libvips and the libraries built into it (LGPL) | 保留；LGPL 文本、源码出处和替换方法已附 / kept, with the LGPL text, its source and how to replace it | 已定 / settled |
| 3 | 许可文本和声明随包附上 / License texts and notices in the bundle | 已取齐；一个包上游没有发布文本 / collected; one package has no text upstream | 已处理 / done |
| 4 | SenseVoice 模型的协议要求署名 / The SenseVoice models' terms ask for attribution | 下载处和文档写明了作者与协议；VAD 文件核对过出处 / author and terms stated where the download is offered and in the guide; the VAD file traced to its origin | 已处理 / done |
| 5 | VibeWand 自己的许可 / VibeWand's own license | `GPL-3.0-only`，另有作者的商业授权；贡献条款已写 / `GPL-3.0-only` with a commercial license from the author; contribution terms written | 已定 / settled |
| 6 | 设备插画、图标和文档图片 / Device artwork, icon and documentation images | 手柄图已重画并经作者认可；其余没有核对 / the controller picture was redrawn and approved by the owner; the rest is not checked | 部分 / partly |
| 7 | 名称与商标 / Names and trademarks | 免责声明已覆盖被操作的应用；标识符改为 `org.vibewand.bridge` 和 `VibeWandBridge`，输入法组件的标识符因 macOS 的限制保留 / the disclaimers cover the apps operated; the identifiers are now `org.vibewand.bridge` and `VibeWandBridge`, and the input method keeps its identifier because of a macOS limit | 已定，留一处 / settled, one left |
| 8 | AU05 协议里的密钥常量 / The key constants of the AU05 protocol | 照常公开 / published as they are | 已定 / settled |

## 1. sherpa-onnx 预编译库里的 eSpeak NG（GPL-3.0-or-later）

**在哪。**`Contents/Resources/kernel/node_modules/sherpa-onnx-darwin-arm64/libsherpa-onnx-c-api.dylib`，sherpa-onnx 1.13.8，0.10.0 起随本机 SenseVoice 听写引入。

**情况。**两个 sherpa-onnx 包标的是 Apache-2.0，但这个库里还静态编入了十个别的库，其中语音合成用的 eSpeak NG 是 GPL-3.0-or-later（`csukuangfj/espeak-ng`，提交 `ed530aa1`）。VibeWand 只做识别，从不调用合成的代码，但代码在随包分发的库里。核对的依据：库里有 eSpeak NG 自己的函数（`espeak_ng_Initialize`、`TranslateRules`、`LoadPhData` 等）；sherpa-onnx 1.13.8 的 `CMakeLists.txt` 在 `SHERPA_ONNX_ENABLE_TTS` 打开（默认）时引入 `espeak-ng-for-piper`；eSpeak NG 在那次提交上的 README 写的是 GPL 3 或更高。

**决定（2026-10-07）：照原样保留。**VibeWand 自己改用 GPL-3.0 以后（第 5 项），它和这个库装在同一个包里没有许可上的冲突，所以没有换库。补上的东西：GPL 3.0 的文本就是随包分发的 [`LICENSE`](../LICENSE)；eSpeak NG 自带的 `COPYING.APACHE`、`COPYING.BSD2`、`COPYING.UCD` 放进了 `third-party/`；[第三方记录](../third-party/README.md)写了它在所编入提交上的源码地址，以及整个库的源码：sherpa-onnx `v1.13.8`，它的 `cmake` 目录按版本取各个库。

**还留着的两件事。**

- GPL 要求分发二进制期间源码一直取得到。现在指向的是别人的仓库（`csukuangfj/espeak-ng`、`k2-fsa/sherpa-onnx`），它们若消失，义务仍在分发者身上。作者 2026-10-07 的决定是指向上游仓库即可，不另留副本。
- 作者给出的商业授权只管得了 VibeWand 自己的代码。交给商业授权方的包如果还带着这个库，那一部分仍是 GPL。到那时把这一个库换成 sherpa-onnx 随同一版本发布的不含语音合成的构建：`sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib.tar.bz2`，8.3 MB，在它的 v1.13.8 发布页上。按它的构建文件，关掉合成后不会编入 eSpeak NG 和 piper-phonemize，C 接口对合成函数保留空实现，Node 插件应当仍能加载。**还没有试过**，换完要重新实测 SenseVoice。

**The library.** `Contents/Resources/kernel/node_modules/sherpa-onnx-darwin-arm64/libsherpa-onnx-c-api.dylib`, sherpa-onnx 1.13.8, shipped since 0.10.0 for SenseVoice dictation on this Mac. The two sherpa-onnx packages state Apache-2.0, but ten other libraries are built into this file, and one of them, eSpeak NG for speech synthesis, is under GPL-3.0-or-later (`csukuangfj/espeak-ng` at `ed530aa1`). VibeWand only recognises speech and never calls the synthesis code, but that code is in the library that ships. Evidence: the file holds eSpeak NG's own functions (`espeak_ng_Initialize`, `TranslateRules`, `LoadPhData` and more); sherpa-onnx 1.13.8's `CMakeLists.txt` includes `espeak-ng-for-piper` when `SHERPA_ONNX_ENABLE_TTS` is on, the default; eSpeak NG's README at that commit says GPL version 3 or later.

**Decided on 2026-10-07: it ships as published.** With VibeWand itself under the GPL-3.0 (item 5), the app and this library travel in one bundle without a conflict of licenses, so the library was not swapped. What was added: the GPL 3.0 text is the [`LICENSE`](../LICENSE) that ships in the bundle; eSpeak NG's own `COPYING.APACHE`, `COPYING.BSD2` and `COPYING.UCD` are in `third-party/`; the [third-party notice](../third-party/README.md) names its source at the revision built in, and the source of the whole library: sherpa-onnx at `v1.13.8`, whose `cmake` folder fetches each library at its revision.

**Two things remain.** The GPL asks that the source stay available for as long as the binary is distributed. The pointers lead to other people's repositories (`csukuangfj/espeak-ng`, `k2-fsa/sherpa-onnx`); should those disappear, the duty stays with whoever distributes, and the owner decided on 2026-10-07 that pointing at the upstream repositories is enough and keeps no copy of his own. And a commercial license from the author covers VibeWand's own code only: a bundle handed to a commercial licensee that still holds this library is GPL in that part. For such a bundle, replace this one library with the build sherpa-onnx publishes without speech synthesis, `sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib.tar.bz2` (8.3 MB, on its v1.13.8 release page). By its build files that build leaves eSpeak NG and piper-phonemize out, and its C API keeps empty implementations of the synthesis functions, so the Node add-on should still load. **Not tried yet**; SenseVoice has to be tested again after the swap.

## 2. libvips 及其内置库（LGPL-3.0-or-later）

**在哪。**`Contents/Resources/kernel/node_modules/@img/sharp-libvips-darwin-arm64/lib/libvips-cpp.8.18.7.dylib`（包版本 1.3.4，18 MB）。0.10.0 起，由 DeepSeek Harness 的图片存储组件 `@deepseek-ai/dsh-attachment-local` 经 sharp 0.35.5 引入；命令模式的窗口截图靠它把图存进对话。

**情况。**包标的是 LGPL-3.0-or-later。它旁边的 `README.md` 列出了编进去的每个库：libvips、glib、pango、librsvg、libheif、libexif、fribidi、proxy-libintl 按 LGPLv3 使用，cairo 是 MPL 1.1，其余是 BSD、MIT、zlib 一类；`versions.json` 给出版本。包里没有 LGPL 和 GPL 的文本。这份清单取自包自己的说明，没有另外对二进制做核对。

**决定（2026-10-07）：保留。**它未经修改，作为单独的动态库随包分发，只在给模型看图时加载。LGPL 3.0 的文本放在 `third-party/GNU-LGPL-3.0.txt`，它所依据的 GPL 3.0 就是 [`LICENSE`](../LICENSE)，两者都随包分发。[第三方记录](../third-party/README.md)写了源码出处，以及怎样换上自己构建的库并重新签名。

**实测过的和没有实测的。**重新签名的步骤在 0.11.0 的包的副本上做过：用同一个库改签后的文件充当重新构建的库，这时包的签名校验失败；执行记录里的那条 `codesign` 命令后校验通过，自带的 Node 经改动后的文件加载 sharp 并生成了一张图片。没有做的是从源码真正构建一个 libvips 再换上去，以及重新签名后 macOS 是否要求重新授予权限。

**The library.** `Contents/Resources/kernel/node_modules/@img/sharp-libvips-darwin-arm64/lib/libvips-cpp.8.18.7.dylib` (package 1.3.4, 18 MB), shipped since 0.10.0. It comes with sharp 0.35.5, which DeepSeek Harness's picture store `@deepseek-ai/dsh-attachment-local` uses; command mode's window picture is kept with the conversation through it. The package states LGPL-3.0-or-later. The `README.md` beside the library lists everything built into it: libvips, glib, pango, librsvg, libheif, libexif, fribidi and proxy-libintl used under LGPLv3, cairo under MPL 1.1, the rest under BSD, MIT and zlib style licenses; `versions.json` gives the versions. Neither the LGPL nor the GPL text is in the package. This list is the package's own; the binary was not inspected separately.

**Decided on 2026-10-07: it stays.** It ships unmodified as a separate dynamic library, loaded only when the model is shown a picture. The LGPL 3.0 text is `third-party/GNU-LGPL-3.0.txt` and the GPL 3.0 it builds on is the [`LICENSE`](../LICENSE); both ship in the bundle. The [third-party notice](../third-party/README.md) names the source and says how to put in a build of your own and sign the app again.

**What was tried and what was not.** The signing steps were run on a copy of the 0.11.0 bundle, with the same library signed differently standing in for a rebuilt one: the bundle then failed verification, verified again after the `codesign` command in the notice, and the bundled Node loaded sharp through the changed file and produced a picture. Not done: building libvips from source and putting that in, and seeing whether macOS asks for its permissions again after the app is signed anew.

## 3. 随包附上的许可文本和声明 / License texts and notices in the bundle

文本都放在 `third-party/`，随应用分发在 `Contents/Resources/third-party`。取自各项目在所用版本上的仓库，2026-10-07。

The texts are in `third-party/` and ship in the app as `Contents/Resources/third-party`. They were taken on 2026-10-07 from each project's repository at the version used.

**编进 `libsherpa-onnx-c-api.dylib` 的库**（清单取自 sherpa-onnx 1.13.8 的 `cmake` 目录，kaldifst 取自 kaldi-decoder 的；并核对过库里确有各自的代码）/ **the libraries built into `libsherpa-onnx-c-api.dylib`** (listed from sherpa-onnx 1.13.8's `cmake` folder, kaldifst from kaldi-decoder's, each confirmed to have code in the file):

| 库 / Library | 许可 / License | 文本 / Text |
| --- | --- | --- |
| kaldi-native-fbank 1.22.3、kaldi-decoder 0.3.0、simple-sentencepiece 0.7 | Apache-2.0 | 各自的 `LICENSE` 与 `sherpa-onnx-LICENSE` 是同一份文本，都没有 `NOTICE` 文件 / their `LICENSE` files are the text of `sherpa-onnx-LICENSE`; none has a `NOTICE` file |
| kaldifst 1.8.0 | Apache-2.0 | `kaldifst-LICENSE`，开头有它关于版权归属的说明 / opens with its note on who holds the copyright |
| OpenFst（`csukuangfj/openfst` `v1.8.5-2026-07-09`） | Apache-2.0 | `OpenFst-COPYING`，Copyright 2005-2026 Google LLC |
| JSON for Modern C++ 3.12.0 | MIT | `JSON-for-Modern-Cpp-LICENSE.MIT` |
| hclust-cpp（`csukuangfj/hclust-cpp` `2026-02-25`） | BSD-2-Clause | `hclust-cpp-LICENSE` |
| piper-phonemize（`csukuangfj/piper-phonemize` `f3ff95af`） | MIT | `piper-phonemize-LICENSE.md` |
| Eigen 5.0.1 | MPL-2.0 | 第三方记录里写了源码出处 / the notice names the source |
| eSpeak NG（`csukuangfj/espeak-ng` `ed530aa1`） | GPL-3.0-or-later | `LICENSE`，以及 `eSpeak-NG-COPYING.APACHE`、`.BSD2`、`.UCD`；见第 1 项 / see item 1 |

**九个发布时没有带许可文件的 npm 包** / **nine npm packages published without a license file**:

| 包 / Package | 许可 / License | 文本 / Text |
| --- | --- | --- |
| `@aws-sdk/credential-provider-http` 3.972.74、`@aws-sdk/credential-provider-login` 3.972.79、`@aws-sdk/nested-clients` 3.997.46 | Apache-2.0 | `AWS-SDK-for-JavaScript-LICENSE`；仓库没有 `NOTICE` 文件 / the repository has no `NOTICE` file |
| `@earendil-works/pi-ai` 0.87.1、`@earendil-works/pi-telemetry` 0.87.1 | MIT | `pi-LICENSE` |
| `@koromix/koffi-darwin-arm64` 3.1.1 | MIT | 同版本的 `koffi` 包带着 `LICENSE.txt`，已在包里 / the `koffi` package of the same version carries `LICENSE.txt`, already in the bundle |
| `data-uri-to-buffer` 4.0.1 | MIT | 全文在它自己的 `README.md` 里，已在包里 / the full text is in its own `README.md`, already in the bundle |
| `standardwebhooks` 1.1.1 | `package.json` 写 MIT / says MIT | 它的仓库里唯一的许可文件是 Apache License 2.0，保留为 `standard-webhooks-LICENSE`；项目没有为这个包发布 MIT 文本 / the one license file in its repository is the Apache License 2.0, kept as `standard-webhooks-LICENSE`; the project publishes no MIT text for the package |
| `proxy-agent-negotiate` 1.1.0 | `package.json` 写 MIT / says MIT | **上游没有文本**：包里和它在 `TooTallNate/proxy-agents` 的目录里都没有。同一作者、同一仓库的 `agent-base` 带着他的 MIT 文本，已在包里 / **no text upstream**, neither in the package nor in its folder of `TooTallNate/proxy-agents`; `agent-base`, by the same author from the same repository, carries his MIT text and is in the bundle |

内核的包升级后，这两张表要重新核对，`third-party/` 里的文本也要跟着换。

Both tables have to be checked again whenever the kernel's packages change, and the texts in `third-party/` replaced with them.

## 4. SenseVoice 的模型 / The SenseVoice models

模型不随应用分发，也不在仓库里。用户点“下载并准备”时，VibeWand 从 Hugging Face 或其镜像下载 DeepSeek Harness 的 SenseVoice 插件指定的文件：`csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`（SenseVoiceSmall 的转换版）和 `csukuangfj/vad`（Silero VAD）。

- 转换版仓库的 `LICENSE` 只有一行，指向 FunASR 的许可说明。原模型 `FunAudioLLM/SenseVoiceSmall` 标的是 [FunASR Model Open Source License Agreement 1.1](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE)（阿里巴巴）：使用、复制、修改和分享时必须注明出处和作者，并保留模型名称；它不是 OSI 许可，另有“不得无端诋毁”的条款，违反即终止。
- Silero VAD 的上游 `snakers4/silero-vad` 是 MIT，Copyright (c) 2020-present Silero Team；`csukuangfj/vad` 这个仓库本身没有任何许可说明。插件指定的那个文件（1,807,522 字节，SHA-256 `a35ebf52…f5af28`）与上游 `v4.0` 标签下的 `files/silero_vad.onnx` 逐字节相同：两者的 git blob 都是 `e6db48d6e2a0797a2ec173c008384f7710189344`。
- **已处理（2026-10-07）。**设置页“语音输入”的下载处和首次引导用的是同一个视图，它在下载前后都显示两个模型的名称、作者和协议，并链接到各自的页面和 FunASR 的协议原文；[语音输入文档](voice-input.md)两种语言都写了同样的内容；第三方记录补了 VAD 文件的核对结果。这处界面改动通过了编译，还没有在运行的应用里看过。

The models are neither shipped nor stored in the repository. When the user asks, VibeWand downloads the files that DeepSeek Harness's SenseVoice plug-in pins, from Hugging Face or its mirror: `csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` (a conversion of SenseVoiceSmall) and `csukuangfj/vad` (Silero VAD). The conversion's `LICENSE` is one line pointing at FunASR's license section. The original model, `FunAudioLLM/SenseVoiceSmall`, is under the [FunASR Model Open Source License Agreement 1.1](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE) (Alibaba): whoever uses, copies, modifies or shares it must attribute the source and author and keep the model names; it is not an OSI license, and it ends for anyone who “unjustifiably denigrates” the model. Silero VAD's upstream, `snakers4/silero-vad`, is MIT; the repository `csukuangfj/vad` states no license at all. The file the plug-in pins (1,807,522 bytes, SHA-256 `a35ebf52…f5af28`) is byte for byte `files/silero_vad.onnx` at the upstream tag `v4.0`: both have the git blob `e6db48d6e2a0797a2ec173c008384f7710189344`, and the upstream copyright line is “Copyright (c) 2020-present Silero Team”.

**Done on 2026-10-07.** The download under Voice input in Settings and the one in the first-run guide are the same view; before and after the download it names both models, their authors and their terms, with links to their pages and to the text of the FunASR agreement. The [voice input guide](voice-input.md) says the same in both languages, and the third-party notice records the check of the VAD file. The change to that view compiles; it has not been looked at in the running app.

## 5. VibeWand 自己的许可 / VibeWand's own license

**决定（2026-10-07）：`GPL-3.0-only`，另由作者提供商业授权。**作者想要的是：真正的开源，同时让想拿它闭源赚钱的人来找他。考虑过的其他选择：LGPL-3.0 允许别人把各模块链接进闭源产品，达不到这个目的；FSL、PolyForm Shield 这类许可能禁止转卖和竞品，但不算开源；原先的 PolyForm Noncommercial 连在公司里使用都要另行授权。GPL 挡不住的是带着源码、沿用 GPL 的再分发和售卖。选 `only` 而不是 `or-later`，是因为版权都在作者手里，以后要换版本随时可以。

- **改了什么。**[`LICENSE`](../LICENSE) 换成 GPL 3.0 的原文；两份 README、文档目录、应用的“关于”页和三个内核包的 `package.json` 都改了说法；“关于”页显示版权、无担保和许可，并能在访达里显示随包的许可文件，另有源码链接。
- **与其他组件的关系。**随包的第三方代码用的是 MIT、Apache-2.0、BSD、ISC、0BSD、Python-2.0、Unlicense、MPL-2.0、LGPL-3.0-or-later 和 GPL-3.0-or-later，都能与 GPL 3.0 的应用一起分发。内核和识别程序本来就在各自的进程里运行。SenseVoice 的模型不随应用分发。
- **外部贡献。**[贡献说明](../CONTRIBUTING.md#license-of-contributions--贡献的授权)现在写明：贡献按 `GPL-3.0-only` 授权给所有人，并另外授予作者按其他条款（包括商业授权）再授权的权利，版权仍归贡献者。到今天为止的 53 个提交都是作者自己的，没有需要补签的人。条款靠贡献者在拉取请求里写明同意来生效，没有配自动检查。
- **名称。**README 写明许可证不授予“VibeWand”名称和图标的商标权利，修改版要标明与原版不同（GPL 第 7 条允许附加的条款）。这个名称没有注册商标。
- **没有做的。**源文件没有逐个加许可声明，许可只在 `LICENSE`、README 和“关于”页里写明。项目主页的页脚和下载说明按[开发指南](development.md)的约定，等仓库公开时再加上许可。“关于”页的源码链接指向本仓库，公开之前打不开。商业授权的合同文本还没有。

**Decided on 2026-10-07: `GPL-3.0-only`, with a commercial license available from the author.** The owner wants real open source, and wants those who would make closed-source money from the code to come to him. What else was weighed: the LGPL-3.0 lets others link the modules into closed products and so misses the aim; licenses such as FSL and PolyForm Shield can forbid resale and competing products but are not open source; PolyForm Noncommercial, the license until now, asks for a separate license even for use inside a company. What the GPL does not stop is redistribution and sale with the source, under the GPL. `only` rather than `or-later` because the author holds all the copyright and can move to a later version whenever he wishes.

**What changed.** [`LICENSE`](../LICENSE) is the GPL 3.0 text; both READMEs, the documentation index, the app's About page and the `package.json` of the three kernel packages say so; the About page shows the copyright, the absence of warranty and the license, reveals the license files of the bundle in Finder and links to the source. **Other components.** The third-party code in the bundle is under MIT, Apache-2.0, BSD, ISC, 0BSD, Python-2.0, Unlicense, MPL-2.0, LGPL-3.0-or-later and GPL-3.0-or-later, all of which can be distributed with an app under the GPL 3.0; the kernel and the recogniser run in processes of their own in any case, and the SenseVoice models are not distributed with the app. **Contributions.** [CONTRIBUTING.md](../CONTRIBUTING.md#license-of-contributions--贡献的授权) now states that a contribution is licensed to everyone under `GPL-3.0-only` and that the author is also granted the right to license it under other terms, commercial ones included, while the contributor keeps the copyright. All 53 commits to date are the author's own, so nobody has to be asked after the fact. The terms take effect by the contributor saying so in the pull request; nothing checks it automatically. **The name.** The READMEs say the license grants no trademark rights in the name “VibeWand” or its icon and that a modified version has to be marked as different, terms section 7 of the GPL allows. The name is not a registered trademark. **Not done.** Source files carry no per-file notice; the license is stated in `LICENSE`, the READMEs and the About page. The project site's footer and download notes get their license statement when the repository is opened, as the [development guide](development.md) says. The About page's source link points at this repository and does not open until it is public. There is no text yet for a commercial license agreement.

## 6. 设备插画、图标和文档图片 / Device artwork, icon and documentation images

- **设备插画**（`assets/device/`，随包分发）。三张图都由图像生成工具生成，不带厂商标志。`controller.png` 生成时参考过厂商的 AU05 产品页，手柄那张的提示词要的是“可辨认的 PS5 风格轮廓”。[`assets/device/README.md`](../assets/device/README.md) 自己写着：反复修改不等于版权清理。外观设计方面没有做过核对。
- **手柄图已重画（2026-10-07）。**原图换成了本项目自己画的 `assets/device/gamepad.svg`：常见外形的单色外壳，四个动作键不带符号，没有用任何产品照片；应用、README、封面、项目主页的设备图和按键一览的渲染图都换了。0.11.2 起安装包里也是新图，README 和主页的悬浮窗截图换成了 0.11.2 的实拍，“能做什么”的四联图换成了用本仓库设备图合成的一张。还带着原图的有：文档里的历史渲染图和概念图、已发布的宣传片、0.11.1 及更早的安装包，以及仓库的提交历史。
- **应用图标和首页场景图。**AI 生成，来源和提示词记录在 [`assets/app-icon/README.md`](../assets/app-icon/README.md) 和 [`docs/images/README.md`](images/README.md)。没有核对所用工具对生成图像的条款，AI 生成图像的权利在各地规定不同。
- **文档里第三方应用的截图**，例如 `docs/images/terminal-v084-codex.jpg`（iTerm2 里的 Codex CLI）。

**The controller picture was redrawn on 2026-10-07.** It is now this project's own drawing, `assets/device/gamepad.svg`: a one-colour shell of a common shape with four plain action buttons, made without any product photograph. The app, the READMEs, the cover, the site's device picture and the renderings of the controls card use it. From 0.11.2 the package carries the new picture too, the overlay screenshot in the READMEs and on the site is one of 0.11.2, and the four scenes under “What it does” are composed from this repository's own device pictures. Still showing the former picture: historical renderings and concept pictures in the documentation, the published film, the packages up to 0.11.1, and the repository's commit history. **Device artwork** (`assets/device/`, shipped in the app): the three pictures were made with an image generation tool and carry no maker's mark. `controller.png` was generated with the maker's AU05 product sheet viewed as a reference, and the prompt for the gamepad asks for “a recognizable PS5-style silhouette”. [`assets/device/README.md`](../assets/device/README.md) itself says that repeated editing is not proof of clearance. Nothing has been checked on the side of design rights. **App icon and hero images**: generated, with sources and prompts recorded in [`assets/app-icon/README.md`](../assets/app-icon/README.md) and [`docs/images/README.md`](images/README.md); the terms of the tool for generated images were not checked, and rights in generated images differ by country. **Screenshots of other apps in the documentation**, such as `docs/images/terminal-v084-codex.jpg` (Codex CLI in iTerm2).

## 7. 名称与商标 / Names and trademarks

- **免责声明：已有。**两份 README 和项目主页在支持的应用那一节写着：应用的名称和图标是各自所有者的商标，只用来说明兼容性，VibeWand 与它们没有隶属、赞助或背书关系；设备那一节和[设备文档](device-templates.md)对设备厂商（Ulanzi、Sony、小米）有同样的声明。`assets/apps/` 的 README 写明那些图标不在本仓库的许可之内，也不进应用包。
- **“VibeKey”：已定（2026-10-07），留一处。**它是 Ulanzi 那款产品的名称，文档和代码里只用它指这款设备本身（包括它的按键模板 `DeviceTemplateID.vibeKey` 和设备的锁文件），属于指称性的用法。项目自己的标识符原先也带着这个名字，0.11.1 起改掉了：内部 target `VibeKeyBridge` 改为 `VibeWandBridge`，bundle ID `org.vibekey.bridge` 改为 `org.vibewand.bridge`，钥匙串里两个服务名同样改了。macOS 因此把它当成另一个应用：设置由新版本在第一次启动时接过来，权限要重新授予，见[开发指南](development.md)和[故障排除](troubleshooting.md)。**留下的一处是输入法组件，仍叫 `org.vibekey.inputmethod.VibeWand`。**当天实测：macOS 按标识符记住用户允许过哪些第三方输入法，应用不能替用户允许一个新的标识符，改了它，“边说边写”就对所有已经开着它的人失效。引导用户去允许的流程已经做了（请 macOS 启用、等着、发现后自己开启），但同一天接着查清：在 macOS 27.0 beta 上 macOS 该问用户的那一问不出现，系统设置的输入法列表里也不提供这一类输入法，换了标识符的人在这个版本上没有办法重新打开，见[语音输入](voice-input.md#在任何应用里边说边写--typing-as-you-speak-in-any-app)。所以现在不改：等某个 macOS 版本上那一问确实出现、并且用户点“允许”之后的那一段在真实系统上走通，再改；到时新组件还要换一个文件名，旧的要先取消选中并删除，因为 macOS 也按路径记输入法。旧名字另外只留在负责接手设置的那几处代码里。

**Disclaimers: in place.** Both READMEs and the project site say, where the supported apps are listed, that app names and icons are trademarks of their owners, shown only to indicate compatibility, and that VibeWand is not affiliated with, sponsored by or endorsed by them; the device section and the [device guide](device-templates.en.md) say the same of the device makers (Ulanzi, Sony, Xiaomi). The README of `assets/apps/` states that those icons are outside this repository's license and are not copied into the app bundle. **“VibeKey”: settled on 2026-10-07, with one identifier left.** It is the name of Ulanzi's product, and the documentation and the code use it only for that device itself, its button template `DeviceTemplateID.vibeKey` and the device's lock file included, which is use of a name to refer to the thing named. The project's own identifiers carried the name too and were changed with 0.11.1: the internal target `VibeKeyBridge` is `VibeWandBridge`, the bundle identifier `org.vibekey.bridge` is `org.vibewand.bridge`, and the two Keychain service names follow. macOS therefore treats it as a different app: the new version takes the settings over at its first launch and the permissions have to be granted again, see the [development guide](development.md) and [troubleshooting](troubleshooting.en.md). **What is left is the input method, still `org.vibekey.inputmethod.VibeWand`.** Tried that day: macOS remembers by identifier which input methods of other makers the user has allowed, and an app cannot allow a new identifier for the user, so changing it would switch “type as you speak” off for everyone who has it on. The flow that leads the user to allow it now exists (macOS is asked to enable it, VibeWand waits, notices and turns it on), but the same day it was also found that on macOS 27.0 beta the question macOS is meant to put to the user does not appear and the list of input sources in System Settings does not offer this kind of input method, so on that version someone whose identifier changed could not turn it on again; see [voice input](voice-input.md#在任何应用里边说边写--typing-as-you-speak-in-any-app). It is therefore not changed now: it waits until a macOS version does ask and what follows the user choosing Allow has been run on a real system. The renamed component will then also need a file name of its own, with the former one deselected and deleted first, since macOS keeps an input method by its path as well. Otherwise the former names remain only in the code that takes the settings over.

## 8. AU05 协议里的密钥常量 / The key constants of the AU05 protocol

`Sources/AU05Device/Protocol.swift` 里报文的加解密、命令格式和按键标识改编自 [AU05 Keys](https://github.com/elliclee/ulanzi-au05-keys)（MIT，许可文本已保留在 `third-party/AU05-Keys-LICENSE`）。其中有设备报文加密用的四个密钥常量。仓库和安装包里没有 Ulanzi 的任何二进制或固件。**决定（2026-10-07）：照常公开。**这四个常量是设备报文所用 TEA 算法的密钥，与 AU05 Keys 的 `Battery.swift` 里的完全一致，是随那个项目的 MIT 许可带署名引用的；它最初是怎样得到的，那个项目没有说明，本项目也没有自己提取过。

The report cipher, command formats and button identifiers in `Sources/AU05Device/Protocol.swift` are adapted from [AU05 Keys](https://github.com/elliclee/ulanzi-au05-keys) (MIT, text kept as `third-party/AU05-Keys-LICENSE`). They include the four key constants of the device's report cipher. No Ulanzi binary or firmware is in the repository or the package. **Decided on 2026-10-07: they are published as they are.** The four constants are the key of the TEA cipher the device's reports use, identical to those in AU05 Keys's `Battery.swift` and taken with attribution under that project's MIT license; how that project first obtained them it does not say, and this project never extracted them itself.

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

随应用分发的有：VibeWand 的 `LICENSE`（GPL 3.0），以及 `third-party/` 里的 AU05 Keys 的 MIT 文本、Opus 的版权与许可声明、sherpa-onnx 的 Apache License 2.0、ONNX Runtime 1.28.2 的许可和它的第三方声明、第 3 项两张表里的文本、LGPL 3.0 的文本；Node.js 的 `LICENSE` 在 `kernel/node/` 下；其余 131 个第三方 npm 包各自带着许可文件。

These ship with the app: VibeWand's `LICENSE` (the GPL 3.0), and in `third-party/` AU05 Keys's MIT text, Opus's copyright and license notices, sherpa-onnx's Apache License 2.0, ONNX Runtime 1.28.2's license with its third-party notices, the texts in the two tables of item 3 and the LGPL 3.0 text; Node.js's `LICENSE` under `kernel/node/`; and the license files that the other 131 third-party npm packages carry themselves.
