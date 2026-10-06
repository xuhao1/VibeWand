# VibeWand promo / 宣传片

Everything the promotional film is made from, so that the film can be built again from this folder alone. The film itself is rendered into `output/promo/cut/`, which git ignores.

宣传片的全部素材和源文件，只靠这个目录就能重新生成成片。成片渲染到 `output/promo/cut/`，不进仓库。

| File / 文件 | What it is / 内容 |
| --- | --- |
| `script.zh.md`, `script.en.md` | The screenplay of each version, scene by scene / 中文版和英文版的分场剧本 |
| `vo.<language>.json`, `timeline.<language>.json` | Narration lines and voices; when each scene and line starts (`zh`, `en`) / 旁白文字与音色；每场、每句的起始时间（`zh`、`en`） |
| `vo/<language>/` | The narration as recorded, and when each word is spoken / 旁白录音，以及每个词的时间 |
| `takes/` | The filmed overlay (VP9 with transparency) and what the script did when; `<take>.webm` with the app in Chinese, `<take>.en.webm` in English / 录下的悬浮窗（带透明通道的 VP9）及脚本的动作时间；`<take>.webm` 是中文界面，`<take>.en.webm` 是英文界面 |
| `src/` | The page that draws every frame, in either language: `stage.js` (timeline, subtitles, backdrop), `mock.js` (shared pieces), `scenes/*.js` / 逐帧绘制画面的页面，两种语言共用 |
| `film/*.json` | Scripts the film build of VibeWand plays while its overlay is recorded / 录制悬浮窗时由拍摄版 VibeWand 执行的脚本 |
| `tools/` | Setup, sound, rendering, encoding, the copies for the site; recording and speech for making new material / 安装、声音、渲染、编码、主页用的版本；以及重新录制和配音用的工具 |

## Build the film / 生成成片

Needs Node.js 22, [uv](https://docs.astral.sh/uv/), ffmpeg (with libvpx and libx264) and Google Chrome. Made on macOS; emoji in a few labels come from the system font.

需要 Node.js 22、[uv](https://docs.astral.sh/uv/)、ffmpeg（带 libvpx 和 libx264）和 Google Chrome。成片在 macOS 上制作，少数标签里的 emoji 用的是系统字体。

```sh
bash promo/tools/setup.sh                        # pinned libraries, fonts and Python packages, into ignored folders
bash promo/tools/build.sh zh VibeWand-promo-zh   # → output/promo/cut/VibeWand-promo-zh.mp4 and …-no-narration.mp4
bash promo/tools/build.sh en VibeWand-promo-en   # the English version
```

`setup.sh` fetches from the npm registry; `NPM_REGISTRY=https://registry.npmmirror.com bash promo/tools/setup.sh` uses a mirror. `build.sh` unpacks the takes, works out the page's data and sound cues, computes the sound, renders every frame in headless Chrome (11,184 of them for the Chinese version) and encodes them twice; about ten minutes on an M2 Max. Nothing in it needs the network, a microphone, a device or VibeWand itself. Two builds have the same sound, sample for sample; their pictures differ only in a few pixels of blurred edges, which Chrome's compositor does not draw the same way twice.

`setup.sh` 从 npm 源下载；用镜像时 `NPM_REGISTRY=https://registry.npmmirror.com bash promo/tools/setup.sh`。`build.sh` 解开悬浮窗素材，生成页面数据和音效时间点，计算声音，在无头 Chrome 里逐帧渲染（中文版 11,184 帧）并编码两次，M2 Max 上约十分钟。这一步不需要网络、麦克风、设备，也不需要 VibeWand 本身。两次构建的声音逐个采样相同；画面只在模糊边缘的少量像素上有肉眼看不出的差别，因为 Chrome 的合成器每次画得不完全一样。

To look at single moments: `node promo/tools/render.mjs --stills 12.5,48 --scale 0.5`, then `bash promo/tools/sheet.sh` lays them out on one sheet.

只看某几个时刻：`node promo/tools/render.mjs --stills 12.5,48 --scale 0.5`，再用 `bash promo/tools/sheet.sh` 拼成一张总览。

## On the site / 放到主页

`bash promo/tools/web.sh` makes the copies the project site plays itself, `site/video/vibewand-zh.mp4` and `vibewand-en.mp4`: the same 1080p at 60 frames a second, about 20 MB each instead of 100. Git ignores them, and `bash scripts/publish-site.sh` publishes them with the page; `docs/development.md` has the rest.

`bash promo/tools/web.sh` 生成项目主页自己播放的版本：`site/video/vibewand-zh.mp4` 和 `vibewand-en.mp4`，同样是 1080p、每秒 60 帧，各约 20 MB（成片约 100 MB）。它们不进仓库，由 `bash scripts/publish-site.sh` 随页面一起发布，其余见 `docs/development.md`。

## Cover / 封面

`node promo/tools/cover.mjs` renders `src/cover.html` in Chinese and English, in 16:9, 4:3 and the 1.91:1 of a shared link, into `output/promo/cover/`. The 16:9 pictures are also the title picture of the READMEs and the site, and the English 1.91:1 one is the site's sharing picture; `docs/images/README.md` says how those copies are made.

`node promo/tools/cover.mjs` 把 `src/cover.html` 渲染成中英文各三种比例的封面：16:9、4:3，以及分享链接用的 1.91:1，放在 `output/promo/cover/`。16:9 的两张同时是 README 和项目主页的题图，英文的 1.91:1 那张是主页的分享图；副本的生成方式见 `docs/images/README.md`。

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
# Narration: edit vo.zh.json or vo.en.json, then (uses the online service; changed lines only)
output/promo-tools/venv/bin/python promo/tools/tts.py zh   # or en

# Overlay: the film build of the app, the recorder, then one take per script (macOS 26, Screen Recording allowed)
VIBEWAND_REUSE_HELPER=1 VIBEWAND_APP_PATH="$PWD/dist/film/VibeWand.app" bash scripts/build-app.sh
mkdir -p output/promo/bin && xcrun swiftc -O promo/tools/wincap.swift -o output/promo/bin/wincap
bash promo/tools/overlay-take.sh ov-core promo/film/ov-core.json 28.5 -hudExpanded YES -hudDisplayMode full
bash promo/tools/overlay-take.sh ov-templates promo/film/ov-templates.json 21 -hudExpanded YES -hudDisplayMode full
bash promo/tools/overlay-take.sh ov-cmd-music promo/film/ov-cmd-music.json 17.5 -hudExpanded YES -hudDisplayMode full
bash promo/tools/overlay-take.sh ov-cmd-keynote promo/film/ov-cmd-keynote.json 18.5 -hudExpanded YES -hudDisplayMode full

# The same four with the app in English: the take is named <take>.en, and the two command scripts have English words
bash promo/tools/overlay-take.sh ov-core.en promo/film/ov-core.json 28.5 -hudExpanded YES -hudDisplayMode full -vibeWand.language english
bash promo/tools/overlay-take.sh ov-templates.en promo/film/ov-templates.json 21 -hudExpanded YES -hudDisplayMode full -vibeWand.language english
bash promo/tools/overlay-take.sh ov-cmd-music.en promo/film/ov-cmd-music.en.json 17.5 -hudExpanded YES -hudDisplayMode full -vibeWand.language english
bash promo/tools/overlay-take.sh ov-cmd-keynote.en promo/film/ov-cmd-keynote.en.json 18.5 -hudExpanded YES -hudDisplayMode full -vibeWand.language english
```

`overlay-take.sh` quits a running VibeWand first (two cannot share the devices; open yours again afterwards), places the overlay and records a rectangle around it, then packs the take into `takes/`. Film mode draws the overlay dark whatever the system's appearance. The placement and rectangle default to the author's second display and are set with `VIBEWAND_FILM_ANCHOR` and `VIBEWAND_FILM_RECT`. A new take differs from the old one by a few frames of timing, which the scenes follow by themselves: they read the times from the take.

`overlay-take.sh` 会先退出正在运行的 VibeWand（两个实例不能共用设备，录完请自行重新打开），摆好悬浮窗并录下它周围的一块矩形，再把素材打包进 `takes/`。拍摄模式下悬浮窗总是深色，与系统外观无关。摆放位置和矩形默认是作者的第二块屏幕，可用 `VIBEWAND_FILM_ANCHOR` 和 `VIBEWAND_FILM_RECT` 修改。重新录的素材在时间上会差几帧，场景会自己跟上：它们从素材里读取时间。
