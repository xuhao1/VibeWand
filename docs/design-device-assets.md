# Device photography / 设备图像

The redesigned mapping screen uses a recognizable product photograph with selectable hardware controls. These generic controller and remote images were generated with the built-in image-generation tool on 2026-10-04. They contain no manufacturer logos and do not assert hardware compatibility. The existing `controller.png` remains the VibeKey / AU05 asset.

重新设计的按键配置界面使用真实产品照片风格的设备图像，并在对应实体按键上叠加可交互热点。以下通用手柄和遥控器图像于 2026-10-04 使用内置图像生成工具制作，不带厂商标识，不代表设备兼容性认证。原有 `controller.png` 继续用于 VibeKey / AU05。

| Asset / 资源 | Native dimensions / 原始尺寸 | Opaque body bounding box / 主体边界（alpha > 128） |
| --- | --- | --- |
| `assets/device/gamepad.png` | 1536 × 1024 | (36, 45) – (1500, 990) |
| `assets/device/remote.png` | 1024 × 1536 | (329, 36) – (695, 1500) |

Both files preserve the generated RGBA channel (alpha extrema 0–254). They were copied directly into the project; no programmatic background removal, cropping, or repainting was used. The faint halo visible in some raw previews is fully or almost fully transparent.

两张图均保留生成工具输出的 RGBA 透明通道（alpha 范围 0–254）。图像直接复制进项目，没有使用程序去背景、裁切或重绘；部分原始预览中可见的光晕为完全或几乎完全透明的像素。

## Hotspots / 热点坐标

Coordinates are relative to the **entire original image**, with `(0, 0)` at its top-left and `(1, 1)` at its bottom-right. Aspect-fit the image, then multiply by that fitted image rectangle and add its origin. Do not multiply by the enclosing panel size when that panel has letterboxing. These are manually inspected centers, not device input identifiers. The initial controller layout uses only right-hand controls.

坐标相对于**完整原始图像**，左上角为 `(0, 0)`，右下角为 `(1, 1)`。图像等比缩放后，用实际显示图像的矩形换算坐标，再加上其原点偏移。面板存在留白时，不应直接用面板尺寸换算。坐标为人工检查后的按键中心，不是设备输入标识。手柄默认配置仅使用右手按键。

| Device / 设备 | Physical control / 实体按键 | Logical control / 逻辑键 | x | y |
| --- | --- | --- | ---: | ---: |
| Controller | R1 front bumper / 前肩键 | `left` | 0.782 | 0.136 |
| Controller | R2 rear trigger / 后扳机 | `right` | 0.783 | 0.070 |
| Controller | □ | `dial` | 0.7305 | 0.3711 |
| Controller | × | `ok` | 0.7956 | 0.4697 |
| Controller | ○ | `escape` | 0.860 | 0.3711 |
| Controller | △ | `voice` | 0.7956 | 0.2725 |
| Controller | L1 front bumper / 前肩键 | `l1` | 0.218 | 0.136 |
| Controller | L2 rear trigger / 后扳机 | `l2` | 0.216 | 0.070 |
| Controller | Left stick press / 左摇杆按下 | `leftStickPress` | 0.352 | 0.559 |
| Controller | Right stick press / 右摇杆按下 | `rightStickPress` | 0.650 | 0.559 |
| Controller | D-pad up / 方向上 | `dpadUp` | 0.209 | 0.303 |
| Controller | D-pad down / 方向下 | `dpadDown` | 0.209 | 0.444 |
| Controller | D-pad left / 方向左 | `dpadLeft` | 0.1595 | 0.3711 |
| Controller | D-pad right / 方向右 | `dpadRight` | 0.2526 | 0.3711 |
| Controller | Options / 选项 | `options` | 0.7031 | 0.2344 |
| Controller | Create / 创建 | `create` | 0.295 | 0.2344 |
| Controller | Home / 主页 | `home` | 0.500 | 0.555 |
| Controller | Touchpad press / 触控板按下 | `touchpad` | 0.500 | 0.277 |
| Controller | Mute / 静音 | `mute` | 0.500 | 0.640 |
| Remote | Microphone / 语音键 | `voice` | 0.500 | 0.180 |
| Remote | Center confirm / 中央确认键 | `dial` | 0.500 | 0.333 |
| Remote | D-pad left / 方向左 | `left` | 0.391 | 0.333 |
| Remote | D-pad right / 方向右 | `right` | 0.608 | 0.333 |
| Remote | Back / 返回 | `escape` | 0.391 | 0.483 |
| Remote | Menu / 菜单 | `ok` | 0.608 | 0.483 |
| Remote | Power / 电源 | `power` | 0.500 | 0.0944 |
| Remote | Home / 主页 | `home` | 0.500 | 0.483 |
| Remote | Volume up / 音量加 | `volumeUp` | 0.500 | 0.569 |
| Remote | Volume down / 音量减 | `volumeDown` | 0.500 | 0.641 |
| Remote | D-pad up / 方向上 | `dpadUp` | 0.500 | 0.262 |
| Remote | D-pad down / 方向下 | `dpadDown` | 0.500 | 0.404 |

The six primary controls retain the default single-hand experience. Extra physical controls can be configured through the extended mapping model; their appearance in this image does not establish hardware input compatibility. R1 and R2 are close together at small sizes; use separate external callouts or offset labels rather than covering the button faces with large text boxes. The source of these coordinates is `Sources/VibeWandBridge/DeviceArtwork.swift`.

六个主要按键保留默认单手操作体验。额外实体按键可通过扩展的映射模型配置；照片中存在某个按键不代表已经验证其输入兼容性。缩小时 R1 与 R2 距离较近，应使用独立引线标注或错开标签，避免用大块文字覆盖真实按键。对应坐标源码位于 `Sources/VibeWandBridge/DeviceArtwork.swift`。

## Stick direction overlays / 摇杆方向入口

Version 0.5.1 adds four selectable directions around each stick center, alongside the existing press hotspot. These are navigation overlays drawn over the same generated photograph, not extra physical buttons or a newly generated asset. The Sticks filter lists each stick's Up / Down / Left / Right / Press entries independently. The underlying controller image and the physical press coordinates above remain unchanged.

0.5.1 在每根摇杆中心周围增加四个可选择的方向入口，保留中心按下热点。这些是叠加在原照片上的导航入口，不是额外实体按钮，也没有重新生成设备素材。「摇杆」分组分别列出两根摇杆的上 / 下 / 左 / 右 / 按下。控制器原图与上表的实体按下坐标保持不变。

## Generation prompts / 生成提示词

### Controller initial generation

> Use case: product-mockup. Asset type: transparent PNG product photograph for a Steam-inspired macOS controller configuration screen. Generate ONE entire generic modern white-and-black ergonomic game controller, a recognizable PS5-style silhouette but no wordmarks, manufacturer marks or logos. Actual transparent background with clean alpha edges, no ground plane, no cast shadow, no text or floating labels. Landscape framing 3:2, the controller centered fills about 90% of width, symmetrical unrotated horizontally, both handles and all edges fully visible with comfortable transparent margin. Camera near straight-on top/front at a slight elevated angle sufficient to see the narrow top edge and both right shoulder controls clearly; face surface dominates. Accurate physical anatomy: white shell handles either side, dark central inset, two symmetric black analog sticks below center, left directional cross, broad central dark textured touchpad, slim left and right auxiliary buttons flanking touchpad; right four circular face buttons in diamond with triangle at top, circle at right, cross at bottom, square at left; R1 and R2 right shoulder elements and L1 L2 left shoulder physically distinct and visible on top edge. Small center home icon button and separate microphone mute button. Matte textured premium plastic, softly lit studio product photography, crisp subtly realistic surface texture, beautiful neutral white shell without blue glow. No extra objects, no UI, no annotations. Intended use: clickable hotspots will be placed over real hardware buttons in the UI.

### Controller final refinement

> Use case: precise-object-edit. Edit this exact generic controller product photograph for a button-mapping UI. Preserve its camera direction, white shell, black center, correct triangle/circle/cross/square buttons, dpad, two sticks, all face control positions, beautiful realistic texture and photographic style. Maintain real transparent background; no scene, no shadow, no text outside hardware. Make ONLY the upper shoulders more accurately readable: expose TWO DISTINCT black shoulder buttons on EACH shoulder, with a narrow horizontal front bumper closer to viewer and a separate raised rear trigger behind it. On right side, bumper small engraved label R1 and rear trigger small engraved label R2, so both can receive independent clickable hotspots. Mirror physical structure on left shoulder with L1 and L2. Enlarge transparent margins to at least 5 percent around the full complete device, keeping landscape 3:2 frame. Do not add UI or annotations. Full device must be completely inside canvas.

### Remote

> Use case: product-mockup. Asset type: transparent PNG hardware photograph for native macOS remote-control configuration panel. Primary request: ONE full-length slim premium generic voice TV remote, directly straight-on front view, absolutely upright, no perspective rotation, symmetric vertical silhouette. True transparent background with clean alpha edges, NO shadow or surrounding backdrop. Portrait 2:3 canvas; remote centered fills 88 percent height and 45 percent width, completely visible with margin around every edge. Body: beautiful matte charcoal anodized-looking plastic, softly rounded rectangle corners, realistic subtle grain, studio product photograph, softly lit but crisply resolved with readable physical buttons. Exact control anatomy from top to bottom: one small circular POWER button centered near top with white power icon; one small circular MICROPHONE/VOICE button centered beneath it with white microphone icon; one large round directional pad ring with a separate round CENTER CONFIRM button, subtle white chevrons up/down/left/right on the ring and a tiny white dot on center; below dpad a row of THREE small separate circular buttons, BACK arrow on LEFT, HOME outline house in CENTER, three-line MENU icon on RIGHT; below these a single narrow vertical volume rocker with '+' on upper half and '−' on lower half; ample plain body area at bottom for hand grip. Only these controls. No alphabetic text, manufacturer or brand logos, no decorative doodles, no extra objects, no UI, no floating labels. Hardware button centers must be clear for later clickable hotspots. Sophisticated and utilitarian object, suitable for both AI-work and media navigation.
