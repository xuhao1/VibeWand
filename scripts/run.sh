#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_app="$task_root/dist/VibeWand.app"
if [ ! -d "$task_app" ]; then bash "$task_root/scripts/build-app.sh"; fi
open "$task_app" --args "$@"
