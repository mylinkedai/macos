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

typeset -A date_seen
hour_dirs=()

while IFS= read -r dir; do
  hour_dirs+=("$dir")
done < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)

for dir in "${hour_dirs[@]}"; do
  base=${dir:t}
  if [[ $base =~ '^[0-9]{10}$' ]]; then
    hour=${base[-2,-1]}
    day=${base[1,8]}

    if (( 10#$hour >= 12 )); then
      logical_day=$day
    else
      logical_day=$(date -j -v-1d -f "%Y%m%d" "$day" "+%Y%m%d")
    fi

    date_seen[$logical_day]=1
  fi
done

echo "Deleting pictures under $root ..."
find "$root" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.webp" \) -delete

echo "Renaming videos under hour folders ..."
for dir in "${hour_dirs[@]}"; do
  base=${dir:t}
  if [[ ! $base =~ '^[0-9]{10}$' ]]; then
    continue
  fi

  while IFS= read -r -d '' video; do
    name=${video:t}

    if [[ $name == ${base}_* ]]; then
      continue
    fi

    target="$dir/${base}_$name"
    if [[ -e "$target" ]]; then
      echo "Target already exists, skipping rename: $target" >&2
      continue
    fi

    mv "$video" "$target"
  done < <(find "$dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.m4v" \) -print0)
done

for logical_day in ${(ok)date_seen}; do
  mkdir -p "$root/$logical_day"
done

for dir in "${hour_dirs[@]}"; do
  base=${dir:t}
  if [[ ! $base =~ '^[0-9]{10}$' ]]; then
    continue
  fi

  hour=${base[-2,-1]}
  day=${base[1,8]}

  if (( 10#$hour >= 12 )); then
    logical_day=$day
  else
    logical_day=$(date -j -v-1d -f "%Y%m%d" "$day" "+%Y%m%d")
  fi

  date_folder="$root/$logical_day"

  while IFS= read -r -d '' video; do
    name=${video:t}
    target="$date_folder/$name"

    if [[ -e "$target" ]]; then
      echo "Target already exists, skipping move: $target" >&2
      continue
    fi

    mv "$video" "$target"
  done < <(find "$dir" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.m4v" \) -print0)
done

echo "Deleting empty folders under $root ..."
find "$root" -depth -type d -empty -delete

echo "Done."
