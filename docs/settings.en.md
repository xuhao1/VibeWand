# Settings and remapping

[简体中文](settings.md) · [Default controls](core-experience.en.md) · [Documentation](README.md)

## Unified settings and graphical editing

The menu bar keeps everyday entry points. One native settings window groups configuration into eight sidebar pages. The editor pairs a device picture and input list with an inspector for the selected control. Settings appears in the Dock while open or minimized; clicking its Dock icon restores the window. Closing settings returns to menu-bar operation without stopping device input.

| Page | Purpose |
| --- | --- |
| General | Interface language, device and foreground-app status, Accessibility permission, and dictation information; since 0.10.0 also the way into the [first-run guide](getting-started.en.md#the-first-run-guide) |
| Devices & inputs | Device photo hotspots, input groups, contextual gestures, action library, timing, and layout import / export; since 0.10.0 the [Keyboard](device-templates.en.md#keyboard) layout, whose key combinations are recorded by pressing them, a custom keyboard's extra keys included |
| Applications | Built-in adapter switches, custom apps, Chat / Browser presets, and editable shortcuts |
| Overlay | Visibility, descriptions, size, opacity, position, and image export |
| Developer | Demo, physical-event capture, compatibility, diagnostics, and reconnect; since 0.10.0, opening the first-run guide or making it appear at the next launch as it does the first time |
| About | Version, license, author, and personal / project website links |
| Voice input | External / built-in dictation, system / API, microphone source (follow the device / system sound input, and, in development, the microphone the keyboard uses), vocabulary and subject hint, language, endpoint, separate keys, testing and exports; since 0.10.0 one more service, [SenseVoice](voice-input.md#本机-sensevoice--sensevoice-on-this-mac) on this Mac, with where its models are and the button that downloads them |
| Command mode | The switch and what it sends, the kernel (built in or plugin mode) and its model, what the model can use (tool scope, seeing the window and clicking in it), [hearing and speaking](command-mode.en.md#hearing-and-speaking), in development (saying results aloud, letting the voice service's model hear the command and act, its voice), the permission mode, how long a conversation is kept, the keyboard command key, viewing and clearing local records; see [Command mode](command-mode.en.md) |

## Remap a control

The editing flow is **template → physical button → context → gesture → action**. Click the photo or its input list, then edit that button in the inspector. Controller groups include face buttons, shoulders, stick presses, D-pad, and auxiliary controls. Physical names such as “□ Square” stay separate from the assigned action, so remapping does not make the button's name misleading. Since 0.10.2 every controller button has five gestures, R1 / R2 included: press, double press, long press, hold, and “press at once, repeat while held”; “Controls” at the top of the page draws the current layout as one picture, see [Default controls](core-experience.en.md#the-controls-card).

Contexts include default, reading / empty draft, editing, conversations, models, effort, and application switching. Open a gesture to choose from the searchable action library. **Use default** restores inheritance; **Unassigned** explicitly disables it. Reset the selected input in the current context, or restore the whole template. Edits are saved locally as they happen.

The library groups **System** actions (dictation, application switching), **Application** actions (conversations, models, candidates, editing, native keys), and **VibeWand** actions (settings, overlay, button guide).

## Save, share, and reset a layout

Each template stores its own gestures and timing. The visible **Import**, **Export**, and **Reset** buttons manage the active template's gesture JSON. **Connect device…** shows live connection status. Controller automatically discovers USB or paired Bluetooth devices through macOS GameController, without an HID import. Advanced compatibility allows an explicit override or a return to automatic detection; Remote still needs a measured profile. Switching layouts stops old input and updates the floating panel's device and input indicators. Importing a layout does not pair hardware or create an audio input.

## Language and About

Switch between Chinese and English on the General page. The initial choice follows the first preferred system language: Chinese selects Simplified Chinese; other languages select English. Explicit choices are saved locally. Menus, settings, action names, and floating feedback update without restarting or altering stored mappings. App recognition continues to accept its existing Chinese and English Accessibility labels.

The About page identifies the author as **Dr. Xu**, and includes [personal](http://xuhao1.me) and [project](https://vibewand.xuhao1.me) website links, the app version, PolyForm Noncommercial license, and source-available project information and commercial licensing requirements.

See [Settings design](settings-design.md) for the concept and implemented interface, and [Device photography](design-device-assets.md) for image provenance and physical-control hotspots.

## Floating feedback

The overlay shows connection state, interaction context, action hints, and physical press / release / rotation feedback. It avoids taking keyboard focus, can be dragged, and follows system appearance. Size, opacity, and button descriptions are configurable, and the panel can be exported as PNG. A small gear in its upper-right corner opens settings in both live and demo modes.

Live feedback comes from physical events. Demo mode allows clicking the panel to operate simulated conversations and drafts. Image export renders only the panel, not the target application's contents.
