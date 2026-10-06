# VibeWand promo / 宣传片

Everything the promotional film is made from, so that the film can be built again from this folder alone. The film itself is rendered into `output/promo/cut/`, which git ignores.

宣传片的全部素材和源文件，只靠这个目录就能重新生成成片。成片渲染到 `output/promo/cut/`，不进仓库。

| File / 文件 | What it is / 内容 |
| --- | --- |
| `script.zh.md` | The screenplay, scene by scene / 分场剧本 |
| `vo.zh.json`, `timeline.zh.json` | Narration lines and voices; when each scene and line starts / 旁白文字与音色；每场、每句的起始时间 |
| `vo/zh/` | The narration as recorded, and when each word is spoken / 旁白录音，以及每个词的时间 |
| `takes/` | The filmed overlay (VP9 with transparency) and what the script did when / 录下的悬浮窗（带透明通道的 VP9）及脚本的动作时间 |
| `src/` | The page that draws every frame: `stage.js` (timeline, subtitles, backdrop), `mock.js` (shared pieces), `scenes/*.js` / 逐帧绘制画面的页面 |
| `film/*.json` | Scripts the film build of VibeWand plays while its overlay is recorded / 录制悬浮窗时由拍摄版 VibeWand 执行的脚本 |
| `tools/` | Setup, sound, rendering, encoding; recording and speech for making new material / 安装、声音、渲染、编码；以及重新录制和配音用的工具 |

## Build the film / 生成成片

Needs Node.js 22, [uv](https://docs.astral.sh/uv/), ffmpeg (with libvpx and libx264) and Google Chrome. Made on macOS; emoji in a few labels come from the system font.

需要 Node.js 22、[uv](https://docs.astral.sh/uv/)、ffmpeg（带 libvpx 和 libx264）和 Google Chrome。成片在 macOS 上制作，少数标签里的 emoji 用的是系统字体。

```sh
bash promo/tools/setup.sh                        # pinned libraries, fonts and Python packages, into ignored folders
bash promo/tools/build.sh zh VibeWand-promo-zh   # → output/promo/cut/VibeWand-promo-zh.mp4 and …-no-narration.mp4
```

`setup.sh` fetches from the npm registry; `NPM_REGISTRY=https://registry.npmmirror.com bash promo/tools/setup.sh` uses a mirror. `build.sh` unpacks the takes, works out the page's data and sound cues, computes the sound, renders 11,184 frames in headless Chrome and encodes them twice; about ten minutes on an M2 Max. Nothing in it needs the network, a microphone, a device or VibeWand itself. Two builds have the same sound, sample for sample; their pictures differ only in a few pixels of blurred edges, which Chrome's compositor does not draw the same way twice.

`setup.sh` 从 npm 源下载；用镜像时 `NPM_REGISTRY=https://registry.npmmirror.com bash promo/tools/setup.sh`。`build.sh` 解开悬浮窗素材，生成页面数据和音效时间点，计算声音，在无头 Chrome 里渲染 11,184 帧并编码两次，M2 Max 上约十分钟。这一步不需要网络、麦克风、设备，也不需要 VibeWand 本身。两次构建的声音逐个采样相同；画面只在模糊边缘的少量像素上有肉眼看不出的差别，因为 Chrome 的合成器每次画得不完全一样。

To look at single moments: `node promo/tools/render.mjs --stills 12.5,48 --scale 0.5`, then `bash promo/tools/sheet.sh` lays them out on one sheet.

只看某几个时刻：`node promo/tools/render.mjs --stills 12.5,48 --scale 0.5`，再用 `bash promo/tools/sheet.sh` 拼成一张总览。

## Cover / 封面

`node promo/tools/cover.mjs` renders `src/cover.html` in Chinese and English, 16:9 and 4:3, into `output/promo/cover/`. The 16:9 pictures are also the title picture of the READMEs and the site; `docs/images/README.md` says how those copies are made.

`node promo/tools/cover.mjs` 把 `src/cover.html` 渲染成中英文、16:9 和 4:3 共四张封面，放在 `output/promo/cover/`。16:9 的两张同时是 README 和项目主页的题图，副本的生成方式见 `docs/images/README.md`。

## What is real / 哪些是真实画面

- **VibeWand's overlay is filmed.** `Sources/VibeKeyBridge/Film.swift` adds a `--film <script.json>` mode to the app: a scripted device presses the controls, a replayed recogniser supplies the words, a kernel names its steps without performing them, and `tools/wincap.swift` records the overlay window alone, with transparency. The takes run in demo mode, where no action reaches any app. The film labels them as such.
- **The app windows are drawn**, to follow what the overlay does. They are labelled "界面示意" on screen.
- **Narration** is synthesised with Microsoft Edge's online voices through `edge-tts`. **Music and effects** are computed in `tools/sound.py`; nothing is sampled.

- **悬浮窗是实机录制的。**`Sources/VibeKeyBridge/Film.swift` 给应用加了 `--film <脚本>` 模式：按脚本按键的设备、回放的识别结果、只报步骤不执行的内核，再由 `tools/wincap.swift` 单独录下悬浮窗（保留透明）。这些镜头在演示模式下录制，操作不会发给任何应用，片中有标注。
- **应用窗口是绘制的**，跟随悬浮窗的动作，画面上标了“界面示意”。
- **旁白**通过 `edge-tts` 用微软 Edge 在线语音合成；**配乐和音效**由 `tools/sound.py` 计算生成，没有采样素材。

## Make new material / 重新制作素材

Only needed when the narration or the overlay itself should change; the results replace files in `vo/` and `takes/`.

只在要改旁白或悬浮窗画面时才需要；结果会替换 `vo/` 和 `takes/` 里的文件。

```sh
# Narration: edit vo.zh.json, then (uses the online service; changed lines only)
output/promo-tools/venv/bin/python promo/tools/tts.py zh

# Overlay: the film build of the app, the recorder, then one take per script (macOS 26, Screen Recording allowed)
VIBEWAND_REUSE_HELPER=1 VIBEWAND_APP_PATH="$PWD/dist/film/VibeWand.app" bash scripts/build-app.sh
mkdir -p output/promo/bin && xcrun swiftc -O promo/tools/wincap.swift -o output/promo/bin/wincap
bash promo/tools/overlay-take.sh ov-core promo/film/ov-core.json 28.5 -hudExpanded YES -hudDisplayMode full
bash promo/tools/overlay-take.sh ov-templates promo/film/ov-templates.json 21 -hudExpanded YES -hudDisplayMode full
bash promo/tools/overlay-take.sh ov-cmd-music promo/film/ov-cmd-music.json 17.5 -hudExpanded YES -hudDisplayMode full
bash promo/tools/overlay-take.sh ov-cmd-keynote promo/film/ov-cmd-keynote.json 18.5 -hudExpanded YES -hudDisplayMode full
```

`overlay-take.sh` quits a running VibeWand first (two cannot share the devices; open yours again afterwards), places the overlay and records a rectangle around it, then packs the take into `takes/`. The placement and rectangle default to the author's second display and are set with `VIBEWAND_FILM_ANCHOR` and `VIBEWAND_FILM_RECT`. A new take differs from the old one by a few frames of timing, which the scenes follow by themselves: they read the times from the take.

`overlay-take.sh` 会先退出正在运行的 VibeWand（两个实例不能共用设备，录完请自行重新打开），摆好悬浮窗并录下它周围的一块矩形，再把素材打包进 `takes/`。摆放位置和矩形默认是作者的第二块屏幕，可用 `VIBEWAND_FILM_ANCHOR` 和 `VIBEWAND_FILM_RECT` 修改。重新录的素材在时间上会差几帧，场景会自己跟上：它们从素材里读取时间。
