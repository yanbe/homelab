#!/usr/bin/env bash
# Provided by Nix: snapshotEnabledDirs
snapshotEnabledDirs=${snapshotEnabledDirs:-""}

verbose=0
for arg in "$@"; do
  if [[ "$arg" == "-v" ]]; then verbose=1; fi
done

set -eu

# マウント待機
(( verbose )) && echo "Waiting for mergerfs mount to become writable..."
for i in {1..30}; do
  # shellcheck disable=SC2086
  first_dir=$(eval echo "${snapshotEnabledDirs}" | cut -d' ' -f1)
  if touch "$first_dir/.write_test" 2>/dev/null; then
    rm "$first_dir/.write_test"
    (( verbose )) && echo "File system is writable."
    break
  fi
  [ "$i" -eq 30 ] && { echo "Timeout"; exit 1; }
  sleep 1
done

# SC2154 回避のため空の配列で初期化しておく
targets=()
# SC2086: ブレース展開のために意図的にクォートを外す
# SC2154: eval内での代入をShellCheckに許容させる
# shellcheck disable=SC2086,SC2154
eval "targets=(${snapshotEnabledDirs})"

# shellcheck disable=SC2154
for target in "${targets[@]}"; do
  mkdir -p "$target/.snapshots"
done

# shellcheck disable=SC2154
(( verbose )) && echo "Starting monitor on ${targets[*]}..."

# shellcheck disable=SC2086
inotifywait -m -r -e close_write -e moved_to --exclude ".snapshots" \
  --format "%T %w%f" --timefmt "@%Y.%m.%d-%H.%M.%S" ${snapshotEnabledDirs} | while read -r snapshot_ts modified_path; do

  (( verbose )) && echo "Change detected: $modified_path at $snapshot_ts" >&2

  snapshot_base_dir=""
  # shellcheck disable=SC2154
  for target in "${targets[@]}"; do
    if [[ "$modified_path" == "$target"* ]]; then
      snapshot_base_dir="$target"
      break
    fi
  done

  if [[ -z "$snapshot_base_dir" ]]; then continue; fi

  sleep 2 # デバウンス

  snapshot_dir="$snapshot_base_dir/.snapshots/$snapshot_ts"
  if [[ -d "$snapshot_dir" ]]; then continue; fi

  last_snap=$(find "$snapshot_base_dir/.snapshots" -maxdepth 1 -name "@*" -type d | sort | tail -n 1)

  mkdir -p "$snapshot_dir"
  if [[ -n "$last_snap" ]]; then
    rsync -a --delete --exclude ".snapshots/" --link-dest="$last_snap" "$snapshot_base_dir/" "$snapshot_dir/"
  else
    rsync -a --delete --exclude ".snapshots/" "$snapshot_base_dir/" "$snapshot_dir/"
  fi
  (( verbose )) && echo "Snapshot created at $snapshot_dir" >&2
done
