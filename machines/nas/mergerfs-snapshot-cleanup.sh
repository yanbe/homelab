#!/usr/bin/env bash
# Provided by Nix: snapshotEnabledDirs
snapshotEnabledDirs=${snapshotEnabledDirs:-""}

verbose=0
for arg in "$@"; do
	if [[ "$arg" == "-v" ]]; then verbose=1; fi
done

set -euo pipefail

# SC2086: ブレース展開のために意図的にクォートを外している
# SC2154: eval内で代入されるため、ShellCheckには見えない
# shellcheck disable=SC2086,SC2154
eval "targets=(${snapshotEnabledDirs})"

# shellcheck disable=SC2154
for target in "${targets[@]}"; do
	snap_dir="$target/.snapshots"

	if [ ! -d "$snap_dir" ]; then
		((verbose)) && echo "Directory $snap_dir does not exist. Skipping."
		continue
	fi

	((verbose)) && echo "Cleaning up old snapshots in $snap_dir..."

	# 30日以上経過したスナップショットを削除
	# findが空の場合に備え、|| true は不要（-exec が実行されないだけ）
	find "$snap_dir" -maxdepth 1 -type d -name "@GMT-*" -mtime +30 -exec rm -rf {} +
done

echo "Cleanup finished."
