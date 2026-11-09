#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <folder>"
  exit 1
fi

folder="${1%/}"
if [[ ! -d "$folder" ]]; then
  echo "Error: folder not found: $folder"
  exit 1
fi
folder="$(cd "$folder" && pwd)"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Error: ffmpeg is not installed or not in PATH"
  exit 1
fi

folder_name="$(basename "$folder")"
out_file="${folder_name}.mp4"

# Build a concat list from common video extensions.
files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find "$folder" -maxdepth 1 -type f \( \
  -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' -o -iname '*.mkv' -o -iname '*.avi' \
\) | LC_ALL=C sort)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "Error: no video files found in $folder"
  exit 1
fi

list_file="$(mktemp)"
cleanup() {
  rm -f "$list_file"
}
trap cleanup EXIT

for f in "${files[@]}"; do
  esc=${f//\'/\'\\\'\'}
  printf "file '%s'\n" "$esc" >> "$list_file"
done

echo "Merging ${#files[@]} files into $out_file"

# Phone videos can contain extra data/metadata tracks (for example Pixel's
# "mett" track) that MP4 concatenation cannot copy. Select only the primary
# video/audio tracks; the audio map is optional so silent videos still work.
stream_maps=(-map 0:v:0 -map '0:a:0?')

# Fast path: stream copy if codecs are compatible.
if ffmpeg -y -f concat -safe 0 -i "$list_file" \
  "${stream_maps[@]}" -dn -map_metadata -1 -map_chapters -1 \
  -c:v copy -c:a copy -movflags +faststart "$out_file"; then
  echo "Done: $out_file"
  exit 0
fi

echo "Copy concat failed; retrying with re-encode for compatibility..."
video_encoder=(libx264 -preset medium -crf 18)
if [[ "$(uname -s)" == "Darwin" ]] && \
   ffmpeg -hide_banner -encoders 2>/dev/null | grep 'h264_videotoolbox' >/dev/null; then
  # Hardware fallback is much faster than libx264 for 4K phone footage.
  video_encoder=(h264_videotoolbox -b:v 35M)
fi

ffmpeg -y -f concat -safe 0 -i "$list_file" \
  "${stream_maps[@]}" -dn -map_metadata -1 -map_chapters -1 \
  -c:v "${video_encoder[@]}" -c:a aac -b:a 192k \
  -movflags +faststart "$out_file"
echo "Done: $out_file"
