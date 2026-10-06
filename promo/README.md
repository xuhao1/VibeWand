# VibeWand promo / 宣传片

Everything the promotional film is made from. The film itself is rendered into `output/promo/cut/`, which git ignores.

宣传片的全部源文件。成片渲染到 `output/promo/cut/`，不进仓库。

| File / 文件 | What it is / 内容 |
| --- | --- |
| `script.zh.md` | The screenplay, scene by scene / 分场剧本 |
| `vo.zh.json`, `timeline.zh.json` | Narration lines and voices; when each scene and line starts / 旁白文字与音色；每场、每句的起始时间 |
| `src/` | The page that draws every frame: `stage.js` (timeline, subtitles, backdrop), `mock.js` (shared pieces), `scenes/*.js` / 逐帧绘制画面的页面 |
| `film/*.json` | Scripts the film build of VibeWand plays while its overlay is recorded / 录制悬浮窗时由拍摄版 VibeWand 执行的脚本 |
| `tools/` | Speech, sound, recording, rendering and encoding / 配音、声音、录制、渲染、编码 |

## What is real / 哪些是真实画面

- **VibeWand's overlay is filmed.** `Sources/VibeKeyBridge/Film.swift` adds a `--film <script.json>` mode to the app: a scripted device presses the controls, a replayed recogniser supplies the words, and `tools/wincap.swift` records the overlay window alone, with transparency. These takes run in demo mode, where no action reaches any app; command-mode takes use a stand-in kernel that names its steps without performing them. The film labels them as such.
- **The app windows are drawn**, to follow what the overlay does. They are labelled "界面示意" on screen.
- **Narration** is synthesised with Microsoft Edge's online voices through `edge-tts`. **Music and effects** are computed in `tools/sound.py`; nothing is sampled.

- **悬浮窗是实机录制的。**`Sources/VibeKeyBridge/Film.swift` 给应用加了 `--film <脚本>` 模式：按脚本按键的设备、回放的识别结果，再由 `tools/wincap.swift` 单独录下悬浮窗（保留透明）。这些镜头在演示模式下录制，操作不会发给任何应用；号令模式的镜头用的是只报步骤、不执行的演示内核，片中有标注。
- **应用窗口是绘制的**，跟随悬浮窗的动作，画面上标了“界面示意”。
- **旁白**通过 `edge-tts` 用微软 Edge 在线语音合成；**配乐和音效**由 `tools/sound.py` 计算生成，没有采样素材。

## Rebuild / 重新生成

```sh
bash promo/tools/setup.sh                                   # libraries, fonts, Python packages (into ignored folders)
output/promo-tools/venv/bin/python promo/tools/tts.py promo/vo.zh.json output/promo/vo/zh
VIBEWAND_REUSE_HELPER=1 VIBEWAND_APP_PATH="$PWD/dist/film/VibeWand.app" bash scripts/build-app.sh
xcrun swiftc -O promo/tools/wincap.swift -o output/promo/bin/wincap
bash promo/tools/overlay-take.sh ov-core promo/film/ov-core.json 28.5 -hudExpanded YES -hudDisplayMode full   # and the other takes
bash promo/tools/seq.sh ov-core "crop=1160:1160:0:0"        # each take
bash promo/tools/build.sh zh VibeWand-promo-zh               # page data, sound, frames, and both encodes
```

`overlay-take.sh` quits a running VibeWand first (two cannot share the devices) and records the overlay at the position its own window had on the author's second display; change the rectangle in the script for another setup. `node promo/tools/render.mjs --stills 12.5,48 --scale 0.5` renders single moments for a look, and `bash promo/tools/sheet.sh` lays them out on one sheet.

`overlay-take.sh` 会先退出正在运行的 VibeWand（两个实例不能共用设备），并按作者第二块屏幕上悬浮窗的位置录制；换环境时改脚本里的矩形。`node promo/tools/render.mjs --stills 12.5,48 --scale 0.5` 可以只渲染某几个时刻来检查，`bash promo/tools/sheet.sh` 把它们拼成一张总览。
