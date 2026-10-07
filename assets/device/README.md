# Controller illustration

`controller.png` is the selected generated device illustration used by the native floating window. The unbranded render is generated with Codex's built-in imagegen tool, then refined in a second pass. Source variants are kept locally for comparison.

The manufacturer's [AU05 product sheet](https://docs.ulanzistudio.com/assets/01-vibekey.dVkwmbaX.png) was viewed as a functional reference for one dial and three keys. The source sheet is not included in the distributed App or repository. The generated illustration removes branding and changes the grille design; repeated editing is not treated as proof of copyright clearance.

Generation prompt: original front-on premium satin-silver handheld controller, one large machined dial above three circular microphone/check/cross keys, neutral studio lighting, transparent alpha background, no letters/logos/marketing layout/colored LEDs.

Refinement prompt: preserve dial/key geometry for software hit regions, replace vertical grille slots with three horizontal microperforation rows, smoother pearl-silver material, restrained precision details, true alpha background.

The App adds its own transient rings and direction indicators over the asset. macOS panel materials, typography and colors are rendered natively.

# Game controller drawing

`gamepad.svg` is this project's own drawing of a game controller, made on 2026-10-07, and `gamepad.png` is its rendering (`rsvg-convert -w 1536 -h 1024 gamepad.svg -o gamepad.png`). It replaced a generated picture that had been asked for as a recognizable PS5-style silhouette. The drawing is a one-colour shell of a common shape; its four action buttons carry no symbols, and its shoulder buttons are labelled L1, L2, R1 and R2. No product photograph or other maker's artwork was used. The centres of its controls are the hotspots in `Sources/VibeWandBridge/DeviceArtwork.swift`: move a control in the drawing and there together, and render again. The site's `img/device-gamepad.webp` is `cwebp -q 86 -resize 900 600` of the PNG.
