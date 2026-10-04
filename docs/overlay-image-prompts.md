# Overlay image prompts

Generated with the built-in imagegen tool. Both prompts use `assets/device/gamepad.png` as their reference. Existing photos are retained.

## UI concept

Use case: ui-mockup. Asset type: VibeWand floating HUD design concept for native macOS Liquid Glass. Generate a polished side-by-side desktop mockup with TWO narrow floating rounded glass HUDs, one light and one dark, on a softly defocused desktop backdrop. Use the attached controller product photo as the reference for the physical gamepad, keeping accurate button positions. Each HUD roughly 430x420 points. Header VibeWand, tiny green connected dot, gear and hide x. The gamepad photo is medium-sized in the upper middle, surrounded by concise graphical callouts and thin elbow arrows terminating on actual buttons: right shoulder pair label 'R1 / R2 · 上一个 / 下一个', touchpad '滑动 · 光标', Triangle '按住 · 听写', Square '退格', Circle '返回', Cross '确认会话'. Clearly highlight Cross in blue to indicate the next action. Each arrow must connect its label to the correct actual physical control, route cleanly without crossing labels. The bottom has a compact contextual glass strip showing '选择会话' and '× 确认  ·  ○ 返回'. A small secondary gesture strip can show '长按 × 会话  ·  双击 × 切应用'. Elegant SF-style typography, subtle white rim reflections, real translucent refractive glass with backdrop blur, quiet blue accent, readable text, generous but compact spacing. Keep the generic title 手柄, no controller brand text, no assistant brand names, no marketing copy, no bright neon. This is a high-fidelity implementation concept, not an entire settings page.

Output: `docs/images/overlay-liquid-glass-concept.png`.

## Transparent cutout

Use case: background-extraction. Edit target: attached existing white-and-black controller product photograph. Remove only the entire studio background and all empty areas between/around the grips, yielding genuine transparent alpha. Preserve the exact controller shape, button positions, symbols, plastic texture, proportions, front-on view and neutral white/black color. Keep internal dark touchpad and controller body opaque; remove external background, not black parts of the device. Output a clean transparent cutout with the same 3:2 framing, no shadow rectangle, no extra text, no new branding, no changes to physical buttons. This cutout will be placed on a native macOS glass HUD.

Output: `assets/device/gamepad-overlay.png`. Transparent background requested; alpha was checked at two background points (0) and inside the controller body (0.992).
