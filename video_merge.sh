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

# Fast path: stream copy if codecs are compatible.
if ffmpeg -y -f concat -safe 0 -i "$list_file" -c copy "$out_file"; then
  echo "Done: $out_file"
  exit 0
fi

echo "Copy concat failed; retrying with re-encode for compatibility..."
ffmpeg -y -f concat -safe 0 -i "$list_file" -c:v libx264 -preset medium -crf 18 -c:a aac -b:a 192k "$out_file"
echo "Done: $out_file"
