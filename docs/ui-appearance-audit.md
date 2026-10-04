# 全界面外观审查 / Full interface appearance audit

本轮覆盖设置的六个主页面、动作选择、手势时序、设备连接、应用适配编辑，以及悬浮窗。目标是让信息密度、标题层级、控件对齐和保存反馈在整个应用中一致，而不只调整设备布局。

This pass covers all six settings pages, the action library, gesture timing, device connection, application profile editor, and the floating overlay. The goal is consistent density, hierarchy, alignment and save feedback across the application.

## 统一标准 / Shared visual standards

- 主页面使用统一的内容宽度与左右边距，短页面不靠超大标题或空白撑开；较长内容在主体区域滚动。
- 同级卡片使用一致的标题、内边距、圆角和细分隔线。辅助说明采用 11–12 pt 次要文本，主控件采用 12–13 pt 文本。
- 设置弹窗使用 20 pt 半粗体标题，标题区、内容区和操作区分别排列；主要内容保持 16–20 pt 间距。
- 值、状态和主操作清楚区分。数值使用等宽数字，状态不能只靠颜色传达。
- 中英文都可即时切换；较长英文说明允许折行，避免挤压控件。
- 原生窗口、文件面板与键盘操作保持 macOS 习惯。

Use consistent page margins and widths, compact card hierarchy, 20 pt sheet titles, 11–12 pt supporting copy, 12–13 pt controls and 16–20 pt section spacing. Distinguish values, status and actions; allow English text to wrap. Preserve native macOS dialogs and keyboard behavior.

## 页面范围 / Page coverage

| 页面 / Surface | 原有问题 / Baseline problem | 审查与修改方向 / Review and change |
| --- | --- | --- |
| 通用 / General | 状态行、语言选择与语音说明缺少统一层级，权限入口和普通信息混在一起。 / Status, language, dictation and permission actions lacked a shared hierarchy. | 紧凑状态摘要；语言、权限、语音各自明确；检查长设备名与应用名。 / Compact status; clear language, permissions and dictation sections; long-name handling. |
| 设备与按键 / Devices & inputs | 大图与标题占据过多空间，映射列表不够显眼。 / The image and heading consumed too much mapping space. | 紧凑工具栏、受控图片高度、映射与右侧编辑器对齐；检查所有设备与摇杆方向。 / Compact toolbar and image; aligned bindings and inspector; all templates and stick directions. |
| 应用适配 / Applications | 内置与自定义适配需要相同的行密度与状态表达。 / Built-in and custom profiles needed consistent rows and states. | 统一列表、启用状态、模板类型、编辑与添加入口；自定义编辑器检查长标题。 / Consistent lists, enabled states, template types and edit/add actions; long editor titles. |
| 悬浮面板 / Overlay | 滑块缺少即时数值，显示选项和管理操作缺少组织。 / Sliders lacked values; visibility and management actions lacked grouping. | 数值与滑块对齐；显示、外观和位置管理分别表达；检查实际浮窗齿轮入口。 / Aligned slider values; clear visibility, appearance and position controls; inspect the floating settings button. |
| 开发者 / Developer | 运行模式、兼容性开关与诊断信息视觉权重相同。 / Modes, compatibility switches and diagnostics competed at the same visual weight. | 明确当前模式与说明；统一开关行；诊断文字与导出操作成组。 / Clear active mode and description; aligned toggles; grouped diagnostics and export. |
| 关于 / About | 品牌、作者和外链需要更紧凑的整体排版。 / Branding, author attribution and links needed a more compact composition. | 品牌信息与作者信息清晰分区；个人与项目链接可读、可点；检查英文职称折行。 / Clear brand and author sections; readable links; wrapping of the English academic title. |

## 弹窗与细节 / Sheets and details

| 弹窗 / Sheet | 已实现的外观调整 / Implemented appearance changes |
| --- | --- |
| 动作选择 / Action library | 独立标题区与底栏；显示当前动作及默认/自定义来源；分类内搜索、清除按钮与明确空状态；紧凑可滚动动作列表；默认动作徽标与单独的恢复默认入口。 / Separate heading and footer; current/default/custom labels; category search, clear button and empty state; compact scrolling list; default badges and restore action. |
| 手势时序 / Gesture timing | 两项时间使用统一卡片行、等宽数值胶囊和范围端点；解释双击与长按关系；底栏显示自动保存状态。 / Consistent timing rows, monospaced value capsules, range endpoints and a timing relationship note; automatic-save feedback. |
| 设备连接 / Device connection | 实物缩略图与配置就绪状态；按键连接与麦克风听写分开；导入为主要操作；解除绑定仅在存在配置时显示。就绪状态仅描述配置，不伪称硬件已连接。 / Device thumbnail and profile readiness; separate connection and microphone sections; prominent import action; unlink only for configured profiles. Readiness does not claim a live hardware connection. |
| 应用适配编辑 / Application profile editor | 纳入整体审查；核对应用身份、模板选择、快捷键编辑和保存操作的层级与空间。 / Included in the review: app identity, template selection, shortcut editing and save actions. |

## 视觉验收 / Visual acceptance

2026-10-04，使用 VibeWand 0.5.2 的实际原生界面完成审查。[六页截图图集](ui-appearance-gallery.html)包含 18 张主页面截图：中文 1220×790、英文 1100×750、深色中文 1100×750。

Reviewed the implemented native VibeWand 0.5.2 interface on 2026-10-04. The [six-page gallery](ui-appearance-gallery.html) contains 18 screenshots: Chinese at 1220×790, English at 1100×750, and dark Chinese at 1100×750.

- [x] 六个主页面逐张检查，无标题、正文、开关或主操作裁切；英文长文正常换行。 / All six pages inspected in every gallery variant; no clipped headings, text, switches or primary actions.
- [x] 三套设备布局逐一检查。VibeKey/遥控器采用竖图与列表并排，手柄保留横图与双列列表，照片热点和映射编辑器可见。 / All three device layouts inspected; portrait devices use adjacent lists, while Controller uses a landscape photo and two-column list.
- [x] 四类弹窗均在原生窗口检查：动作、时序、连接、应用编辑。 / All four native sheets inspected: actions, timing, connection and app editing.
- [x] 动作搜索验证匹配与无结果状态，Escape 关闭不修改配置。 / Action search and the empty state checked; Escape dismisses without changing a binding.
- [x] 时序数值、范围、滑条和固定底栏检查；保留离散数值精度并去掉密集刻度。 / Timing values, ranges, sliders and footer checked; discrete precision is retained without dense tick marks.
- [x] 应用编辑器检查中文浅色与英文深色，快捷键列、表头和保存栏完整可见。 / App editor inspected in light Chinese and dark English; shortcut columns, header and footer remain visible.
- [x] 悬浮面板实际预览检查紧凑与展开两种状态，开关右对齐，百分比与范围值可读。 / Overlay preview checked in compact and expanded forms; switches align right and percentage values remain readable.
- [x] 深色设备照片与热点复核；低对比度的滑条范围文字改为 secondary。 / Dark device images and hotspots checked; faint slider endpoints use stronger secondary text.
- [x] 回归测试 112 项通过，应用成功构建并通过签名验证。 / 112 regression tests pass; the app builds and passes signature verification.

审查期间临时切换的语言、设备模板和按键说明状态均已恢复。图集由应用自身导出，不包含其他应用窗口；深色截图只改变设置窗口的外观，右侧浮窗预览忠实显示实际浮窗，因此会沿用系统当前主题。

Temporary language, layout and button-guide choices were restored. Gallery images are exported from the app's own views. Dark review changes only the settings window appearance; the overlay preview retains the real overlay's current system appearance.


## 0.5.3 原生外观与交互补充 / Native appearance and interaction follow-up

语言只保留在「通用」，左下角仅显示版本；模板显示名统一为 VibeKey。侧栏按钮整行可点，并增加悬停与选中反馈。设置窗口、页头、卡片和弹窗采用原生毛玻璃，随 macOS 明暗外观变化；系统降低透明度时使用不透明的语义色。

Language is available only in General; the sidebar footer shows the version. The layout is named VibeKey. Sidebar rows have full-width hit regions with hover and selection feedback. Native materials follow macOS light/dark appearance and respect Reduce Transparency.

悬浮窗右上角增加 × 隐藏按钮，与设置齿轮分开；隐藏不会停止设备控制，可从菜单栏或悬浮面板设置重新显示。浮窗预览与导出正确解析浅色和深色外观。

The overlay has a separate × hide button beside its settings gear. Hiding it keeps device input running; show it again through the menu bar or Overlay settings. Preview/export colors resolve against the selected appearance.

本轮验收：112 项回归测试通过、构建及签名验证通过；实际点击侧栏文字右侧空白成功切换到通用；实际点击 × 隐藏后，显示开关为关闭，重新打开后面板恢复。审查了当前明暗材质、预览和浮窗按钮布局。`ui-audit/` 与图集已更新至 0.5.3。

Validation: 112 regression tests pass; the build and signature verify. Clicking blank space to the right of the General label navigates correctly. The × button hides the overlay and clears its visibility switch; turning the switch on restores it. Current light/dark materials, previews and overlay controls have been visually reviewed. The gallery now shows 0.5.3.

0.5.3 最后一张悬浮面板截图使用用户当前窗口大小；其余图集沿用标准与紧凑尺寸。
The final 0.5.3 Overlay capture uses the current user window size; the remaining gallery retains the standard and compact review sizes.
