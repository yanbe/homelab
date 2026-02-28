#!/usr/bin/env bash
# Provided by Nix: cooldown_threshold, cachedMountPoint, ssdRotationLockFile
cooldown_threshold=${cooldown_threshold:-75}
cachedMountPoint=${cachedMountPoint:-/mnt/mergerfs/cached}
ssdRotationLockFile=${ssdRotationLockFile:-/var/lock/ssd-rotate.lock}

verbose=0
init=0
for arg in "$@"; do
  if [[ $arg == "-v" ]]; then
    verbose=1
  fi
  if [[ $arg == "--init" ]]; then
    init=1
  fi
done

mount_base_dir=/mnt/ssd
state_base_dir=/var/lib/ssd-rotate
mkdir -p $state_base_dir

lock=${ssdRotationLockFile}
exec 9>"$lock"
if ! flock -n -x 9; then
  echo "another script is already running for SSD rotation. exiting" >&2
  exit 0
fi

# 起動時以外にも mergerfs-cached.service がリスタートするとSSDのbranch参加状態もリセットされるので、状態をリセットする
if (( init )); then
  (( verbose )) && echo "called with --init option. initializing state" >&2
  rm -f $state_base_dir/*
fi

df -P $mount_base_dir/* | awk 'NR>=2 {gsub("('$mount_base_dir'/|%)",""); print $6,$5}' | while IFS=' ' read -r name use; do
  cur_state=$(touch "$state_base_dir/$name" && cat "$state_base_dir/$name")
  if [[ $cur_state == "drain" ]]; then
    # drain 中のプロセスを強制終了した時などにここに来ることがある
    (( verbose )) && echo "$mount_base_dir/$name is in drain state. skipping" >&2
    continue
  fi

  if (( use < cooldown_threshold )); then
    (( verbose )) && echo "$mount_base_dir/$name is $use% use (< $cooldown_threshold%). keeping active" >&2
    next_state=active
  else
    (( verbose )) && echo "$mount_base_dir/$name reached $use% use (>= $cooldown_threshold%). going cooldown" >&2
    next_state=cooldown
  fi
  path_present=0
  if mergerfs.ctl -m "${cachedMountPoint}" info | grep -Fq -- "- $mount_base_dir/$name"; then
    path_present=1
  fi

  if [[ $cur_state != "$next_state" || $path_present -eq 0 ]]; then
    (( verbose )) && [[ $path_present -eq 0 ]] && echo "$mount_base_dir/$name is missing from srcmounts. re-adding." >&2
    mergerfs.ctl -m "${cachedMountPoint}" remove path "$mount_base_dir/$name"
    if [[ $next_state == "cooldown" ]]; then
      next_mode=NC
    else
      next_mode=RW
    fi
    mergerfs.ctl -m "${cachedMountPoint}" add path "$mount_base_dir/$name"="$next_mode"
    echo "$next_state" > "$state_base_dir/$name"
  fi
done
