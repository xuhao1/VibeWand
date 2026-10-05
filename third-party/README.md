# Third-party notices

`Sources/AU05Device/Protocol.swift` adapts report encryption/decryption, command formats and physical button identifiers from [AU05 Keys](https://github.com/elliclee/ulanzi-au05-keys), revision `7819351a5ba5c68874d0519fabe3bf62db47e328` (`Battery.swift`, `VendorKeys.swift`, `Core.swift`). Copyright (c) 2026 AU05 Keys contributors. The complete MIT license is retained in [AU05-Keys-LICENSE](AU05-Keys-LICENSE) and included in app bundles.

The native HID transport and lifecycle are implemented here. No Ulanzi proprietary binary or firmware is distributed.

The optional DualSense microphone helper bundles libopus from [Opus / Xiph.Org](https://opus-codec.org/). Its upstream [copyright and license notices](Opus-COPYING.txt) are retained here and shipped in the app resources as `Opus-COPYING.txt`. These third-party notices remain independent of the VibeWand noncommercial license.

Command mode's kernel is assembled by `scripts/build-kernel.sh` and shipped in the app under `Contents/Resources/kernel`; none of it is stored in this repository.

- [Node.js](https://nodejs.org/) 24.21.0, the official Apple Silicon build, unmodified and with its original signature. Its license, which also covers the libraries built into it, ships as `kernel/node/LICENSE`.
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 0.2.0-rc.2 (MIT), limited to the packages named in `kernel/package.json`, together with the dependencies recorded in `kernel/package-lock.json`. Each package ships with its own license file inside `kernel/node_modules`.

VibeWand's profile for the kernel (`kernel/profile`) is part of VibeWand.
