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
out_file="${folder_name}_270.mp4"
out_path="$(pwd)/$out_file"

# Sort by filename, matching video_merge.sh. Exclude our output when the input
# folder is also the current directory.
files=()
while IFS= read -r f; do
  [[ "$f" == "$out_path" ]] || files+=("$f")
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

# Rotation makes stream-copy impossible. Rotate while decoding the concatenated
# input so the video is encoded only once. A 270-degree clockwise rotation is
# equivalent to 90 degrees counter-clockwise.
video_encoder=(libx264 -preset ultrafast -crf 18)
if [[ "$(uname -s)" == "Darwin" ]] &&
   ffmpeg -hide_banner -encoders 2>/dev/null | grep 'h264_videotoolbox' >/dev/null; then
  video_encoder=(h264_videotoolbox -b:v 35M -allow_sw 1)
fi

echo "Merging and rotating ${#files[@]} files 270 degrees into $out_file"
ffmpeg -y -f concat -safe 0 -i "$list_file" \
  -map 0:v:0 -map '0:a:0?' -dn -map_metadata -1 -map_chapters -1 \
  -vf 'transpose=2' -c:v "${video_encoder[@]}" \
  -c:a aac -b:a 192k -movflags +faststart "$out_file"

echo "Done: $out_file"
