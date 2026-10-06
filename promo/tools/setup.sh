#!/bin/bash
# Fetches what the promo is built with, at the versions it was made with, into places git ignores: the page's
# animation library and fonts (promo/src/vendor), the headless-browser driver, and the Python packages for sound
# and speech. Needs Node.js, uv, ffmpeg and Google Chrome. NPM_REGISTRY names another registry to fetch from.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_tools="$task_root/output/promo-tools"
mkdir -p "$task_tools"
cp "$task_root/promo/tools/package.json" "$task_root/promo/tools/package-lock.json" "$task_tools/"
(cd "$task_tools" && npm ci --no-audit --no-fund ${NPM_REGISTRY:+--registry="$NPM_REGISTRY"} >/dev/null)
[ -x "$task_tools/venv/bin/python" ] || uv venv --python 3.12 "$task_tools/venv" >/dev/null
uv pip install --python "$task_tools/venv/bin/python" -r "$task_root/promo/tools/requirements.txt" >/dev/null
task_vendor="$task_root/promo/src/vendor"
rm -rf "$task_vendor"; mkdir -p "$task_vendor"
cp "$task_tools/node_modules/gsap/dist/gsap.min.js" "$task_vendor/"
for task_font in noto-sans-sc sora jetbrains-mono; do cp -R "$task_tools/node_modules/@fontsource/$task_font" "$task_vendor/$task_font"; done
echo "ready: $task_vendor"
