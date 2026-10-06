#!/bin/bash
# Publish site/ to the repository GitHub Pages serves as vibewand.xuhao1.me.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_clone="$(mktemp -d)"
trap 'rm -rf "$task_clone"' EXIT
git clone --quiet --depth 1 https://github.com/xuhao1/vibewand-site.git "$task_clone"
rsync -a --delete --exclude .git --exclude .DS_Store "$task_root/site/" "$task_clone/"
git -C "$task_clone" add -A
if git -C "$task_clone" diff --cached --quiet; then echo "The published site is already up to date."; exit 0; fi
# That repository is public: commit with the owner's GitHub address, not the one this checkout uses.
git -C "$task_clone" -c user.name=XuHao -c user.email=xuhao1@users.noreply.github.com \
    commit --quiet -m "${1:-Publish site}"
git -C "$task_clone" push --quiet origin HEAD:main
echo "Published. https://vibewand.xuhao1.me follows within a minute or two."
