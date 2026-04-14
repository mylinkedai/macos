#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <folder>" >&2
  exit 1
fi

root=$1

if [[ ! -d "$root" ]]; then
  echo "Folder not found: $root" >&2
  exit 1
fi

root=$(cd "$root" && pwd)

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found in PATH" >&2
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffprobe not found in PATH" >&2
  exit 1
fi

date_dirs=()
while IFS= read -r dir; do
  date_dirs+=("$dir")
done < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)

for dir in "${date_dirs[@]}"; do
  date=${dir:t}
  if [[ $date =~ '^[0-9]{8}$' ]]; then
    echo "$date"
  fi
done

for dir in "${date_dirs[@]}"; do
  date=${dir:t}
  if [[ ! $date =~ '^[0-9]{8}$' ]]; then
    continue
  fi

  echo "Processing date folder: $date"

  videos=()
  while IFS= read -r video; do
    videos+=("$video")
  done < <(find "$dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.m4v" \) | sort)

  if (( ${#videos[@]} == 0 )); then
    echo "Skipping $date: no videos found" >&2
    continue
  fi

  list_file=$(mktemp)
  trap 'rm -f "$list_file"' EXIT
  valid_count=0

  for video in "${videos[@]}"; do
    name=${video:t}
    echo "Checking file: $name"

    if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 "$video" >/dev/null 2>&1; then
      echo "Skipping invalid video: $video" >&2
      continue
    fi

    video_codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 "$video" | head -n 1)
    duration=$(ffprobe -v error -show_entries format=duration -of default=nokey=1:noprint_wrappers=1 "$video" | head -n 1 || true)

    if [[ -z "$duration" ]]; then
      duration="unknown"
    fi

    echo "Using video only: $name | video=$video_codec duration=$duration"
    printf "file '%s'\n" "${video//\'/\'\\\'\'}" >> "$list_file"
    valid_count=$((valid_count + 1))
  done

  if (( valid_count == 0 )); then
    echo "Skipping $date: no valid videos found" >&2
    rm -f "$list_file"
    trap - EXIT
    continue
  fi

  output="$root/$date.mp4"
  echo "Creating $output from $valid_count files ..."
  ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list_file" -map 0:v:0 -c:v copy -an "$output"

  echo "Created: $output"
  rm -f "$list_file"
  trap - EXIT
done

echo "Done."
