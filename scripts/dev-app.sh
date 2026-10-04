#!/bin/bash
# Fast development bundle: debug build, reused microphone helper, no backups.
# Signs with the sole Apple Development identity when present so macOS keeps
# the Accessibility grant across rebuilds.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
VIBEWAND_CONFIGURATION=debug VIBEWAND_REUSE_HELPER=1 VIBEWAND_KEEP_PREVIOUS=0 VIBEWAND_DOCK_APP="${VIBEWAND_DOCK_APP:-0}" \
  VIBEWAND_APP_PATH="${VIBEWAND_APP_PATH:-$task_root/dist/dev/VibeWand.app}" \
  bash "$task_root/scripts/build-app.sh"
