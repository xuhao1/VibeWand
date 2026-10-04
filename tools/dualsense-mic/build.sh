#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
task_out="$task_root/output/dualsense-mic"
mkdir -p "$task_out"
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists opus; then
    opus_cflags=$(pkg-config --cflags opus)
    opus_libs=$(pkg-config --libs opus)
elif [ -f /opt/homebrew/include/opus/opus.h ]; then
    opus_cflags='-I/opt/homebrew/include'
    opus_libs='-L/opt/homebrew/lib -lopus'
elif [ -f /usr/local/include/opus/opus.h ]; then
    opus_cflags='-I/usr/local/include'
    opus_libs='-L/usr/local/lib -lopus'
else
    echo 'libopus development files are required (for example: brew install opus).' >&2
    exit 1
fi
# pkg-config usually returns the opus subdirectory; add its parent for <opus/opus.h>.
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists opus; then
    opus_cflags="$opus_cflags -I$(pkg-config --variable=includedir opus)"
fi
# Intentional word splitting for compiler flags supplied by pkg-config.
cc -std=c11 -Wall -Wextra -Werror $opus_cflags "$task_root/tools/dualsense-mic/test-protocol.c" $opus_libs -lz -o "$task_out/test-protocol"
"$task_out/test-protocol"
cc -std=c11 -Wall -Wextra -Werror $opus_cflags "$task_root/tools/dualsense-mic/probe.c" $opus_libs -lz -framework CoreFoundation -framework IOKit -o "$task_out/probe"
echo "Built $task_out/probe (baseline only by default)."
