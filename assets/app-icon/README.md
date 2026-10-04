# VibeWand app icon

The approved AI reference (magic wand, code brackets and five voice bars) is the raster source. The rounded tile retains its original dark gradient, perspective and light effects; only its exterior is transparent.

- `reference.png`: unmodified approved reference.
- `AppIcon.png`: 1024 × 1024 RGBA app icon with a clean antialiased outer silhouette.
- `AppIcon.icns`: ten standard macOS representations from 16 px through 1024 px, including Retina sizes.
- `BrandMarkLight.png`: transparent in-app mark with saturated blue/violet details for light sidebars and About pages, generated with the built-in image tool. The high-resolution original is `BrandMarkLight-source.png` and its exact prompt is in `BrandMarkLight-prompt.txt`.

Re-export with the native macOS tools:

```sh
swift scripts/export-app-icon.swift assets/app-icon/reference.png assets/app-icon/AppIcon.png
bash scripts/build-icon.sh
```

The built-in image generation tool was used for background-extraction trials. The final export applies the clean tile outline to the original reference to preserve its interior artwork. No SVG redraw is used.

`scripts/build-app.sh` generates the ICNS into the application resources and declares `CFBundleIconFile`. The application loads that resource for its Dock icon; direct SwiftPM launches use the PNG source.

The settings sidebar and About page share `BrandMark`, using the light artwork in light appearance and the approved app icon in dark appearance.

The menu bar uses `MenuBarIcon.make()`, a 22 × 18 pt native vector template with a diagonal wand, separated code brackets and five small voice bars. AppKit controls its light/dark and highlighted tint; Retina rendering remains sharp. `MenuBarIcon.svg` records the equivalent shape for design tools.
