#!/bin/zsh

emulate -L zsh
set -euo pipefail

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required but not installed." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but not installed." >&2
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffprobe is required but not installed." >&2
  exit 1
fi

cd "$(dirname "$0")"

next_date() {
  python3 - "$1" <<'PY'
from datetime import datetime, timedelta
import sys

date_str = sys.argv[1]
date_obj = datetime.strptime(date_str, "%Y%m%d")
print((date_obj + timedelta(days=1)).strftime("%Y%m%d"))
PY
}

prev_date() {
  python3 - "$1" <<'PY'
from datetime import datetime, timedelta
import sys

date_str = sys.argv[1]
date_obj = datetime.strptime(date_str, "%Y%m%d")
print((date_obj - timedelta(days=1)).strftime("%Y%m%d"))
PY
}

logical_date_for_hour_dir() {
  local hour_dir_name="$1"
  local date_part="${hour_dir_name:0:8}"
  local hour_part="${hour_dir_name:8:2}"

  if (( 10#$hour_part >= 12 )); then
    printf '%s\n' "$date_part"
  else
    prev_date "$date_part"
  fi
}

move_videos_from_hour() {
  local hour_dir="$1"
  local date_dir="$2"
  local moved=1

  setopt local_options null_glob
  for video in "$hour_dir"/*.mp4(.N); do
    mv "$video" "$date_dir"/
    moved=0
  done

  return $moved
}

date_dir_has_mp4() {
  local date_dir="$1"

  setopt local_options null_glob
  local files=("$date_dir"/*.mp4(.N))
  (( ${#files[@]} > 0 ))
}

build_concat_list() {
  local date_dir="$1"
  local list_file="$2"
  local file
  local escaped
  local abs_date_dir
  local valid_count=0

  abs_date_dir="$(cd "$date_dir" && pwd -P)"
  : > "$list_file"
  while IFS= read -r -d '' file; do
    if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$file" >/dev/null 2>&1; then
      echo "Skipping bad video: $file"
      continue
    fi
    escaped=${file//\'/\'\\\'\'}
    printf "file '%s'\n" "$escaped" >> "$list_file"
    valid_count=1
  done < <(find "$abs_date_dir" -maxdepth 1 -type f -name '*.mp4' -print0 | sort -z)

  return $(( valid_count == 1 ? 0 : 1 ))
}

echo "Deleting pictures from subfolders..."
find . -mindepth 2 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -delete

dates=()
while IFS= read -r dir_name; do
  dates+=("$(logical_date_for_hour_dir "$dir_name")")
done < <(
  find . -mindepth 1 -maxdepth 1 -type d -name '20????????' -print \
    | sed 's|^\./||' \
    | sort
)

unique_dates=()
last_date=""
for date in "${dates[@]}"; do
  if [[ "$date" != "$last_date" ]]; then
    unique_dates+=("$date")
    last_date="$date"
  fi
done

for date in "${unique_dates[@]}"; do
  next="$(next_date "$date")"
  date_dir="./$date"
  found_any=0

  mkdir -p "$date_dir"
  echo "Processing $date from ${date}12 to ${next}11..."

  for hour in {12..23}; do
    hour_dir=$(printf "./%s%02d" "$date" "$hour")
    if [[ -d "$hour_dir" ]] && move_videos_from_hour "$hour_dir" "$date_dir"; then
      found_any=1
    fi
  done

  for hour in {0..11}; do
    hour_dir=$(printf "./%s%02d" "$next" "$hour")
    if [[ -d "$hour_dir" ]] && move_videos_from_hour "$hour_dir" "$date_dir"; then
      found_any=1
    fi
  done

  if [[ "$found_any" -eq 0 ]] && ! date_dir_has_mp4 "$date_dir"; then
    rmdir "$date_dir" 2>/dev/null || true
    echo "Skipping $date: no videos found."
    continue
  fi

  concat_list="$(mktemp)"
  trap 'rm -f "$concat_list"' EXIT
  if ! build_concat_list "$date_dir" "$concat_list" || [[ ! -s "$concat_list" ]]; then
    rm -f "$concat_list"
    trap - EXIT
    echo "Skipping merge for $date: no valid videos found."
    continue
  fi

  ffmpeg -hide_banner -loglevel warning -nostats -y -f concat -safe 0 -err_detect ignore_err -fflags +discardcorrupt -i "$concat_list" \
    -map 0:v:0 -map '0:a:0?' -c:v copy -c:a aac -b:a 64k -movflags +faststart "./${date}.mp4"
  rm -f "$concat_list"
  trap - EXIT
done

echo "Deleting empty folders..."
find . -depth -type d -empty -delete

echo "Done."
