#!/bin/bash
# Joins rendered frames and a mix into a film. Usage: encode.sh <frames-dir> <fps> <mix.wav> <out.mp4> [crf]
set -euo pipefail
ffmpeg -hide_banner -loglevel error -y -framerate "$2" -i "$1/%06d.jpg" -i "$3" \
  -vf "scale=in_color_matrix=bt601:out_color_matrix=bt709:in_range=pc:out_range=tv,format=yuv420p" \
  -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:v libx264 -preset slow -crf "${5:-15}" -c:a aac -b:a 256k -shortest -movflags +faststart "$4"
ffprobe -v error -show_entries format=duration,size -of csv=p=0 "$4"
