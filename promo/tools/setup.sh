#!/bin/bash
# Fetches what the promo is built with into places git ignores: the page's animation library and fonts
# (promo/src/vendor), the headless-browser driver, and the Python packages for speech and sound.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_tools="$task_root/output/promo-tools"
mkdir -p "$task_tools"
cd "$task_tools"
[ -f package.json ] || npm init -y >/dev/null
npm install --no-audit --no-fund --registry="${NPM_REGISTRY:-https://registry.npmmirror.com}" playwright-core gsap @fontsource/noto-sans-sc @fontsource/sora @fontsource/space-grotesk @fontsource/jetbrains-mono >/dev/null
[ -x venv/bin/python ] || uv venv --python 3.12 venv >/dev/null
uv pip install --python venv/bin/python edge-tts numpy scipy pillow >/dev/null
task_vendor="$task_root/promo/src/vendor"
rm -rf "$task_vendor"; mkdir -p "$task_vendor"
cp node_modules/gsap/dist/gsap.min.js "$task_vendor/"
for task_font in noto-sans-sc sora space-grotesk jetbrains-mono; do cp -R "node_modules/@fontsource/$task_font" "$task_vendor/$task_font"; done
echo "ready: $task_vendor"
