#!/usr/bin/env bash
# Provided by Nix: ssdRotationLockFile, cachedMountPoint, backingMountPoint, ssdDrainExcludes, ssdDrainMinSize
ssdRotationLockFile=${ssdRotationLockFile:-/var/lock/ssd-rotate.lock}
cachedMountPoint=${cachedMountPoint:-/mnt/mergerfs/cached}
backingMountPoint=${backingMountPoint:-/mnt/mergerfs/backing}
ssdDrainExcludes=${ssdDrainExcludes:-"{'ROMs','Documents'}"}
ssdDrainMinSize=${ssdDrainMinSize:-"8m"}

verbose=0
for arg in "$@"; do
	if [[ $arg == "-v" ]]; then
		verbose=1
	fi
done

mount_base_dir=/mnt/ssd
state_base_dir=/var/lib/ssd-rotate

lock=${ssdRotationLockFile}
exec 9>"$lock"
if ! flock -n -x 9; then
	((verbose)) && echo "another script is already running for SSD rotation. exiting" >&2
	exit 0
fi
find $state_base_dir/* -type f -maxdepth 0 -exec basename {} \; | while read -r name; do
	cur_state=$(touch "$state_base_dir/$name" && cat "$state_base_dir/$name")
	cur_mountpoint=$mount_base_dir/$name
	if [[ $cur_state == "" ]]; then
		((verbose)) && echo "$cur_mountpoint 's state is uninitialized. skipping" >&2
		continue
	fi

	if [[ $cur_state == "active" ]]; then
		((verbose)) && echo "$cur_mountpoint is active state. skipping" >&2
		continue
	fi
	# cooldown or (had canceled or aborted) drain

	((verbose)) && echo "checking mountpoint's file opening status: $cur_mountpoint ($cur_state)" >&2

	if lsof +D "$cur_mountpoint" | grep -q .; then
		((verbose)) && echo "someone is opening files under $cur_mountpoint . keeping $cur_state" >&2
		continue
	fi

	((verbose)) && echo "no one opening files under $cur_mountpoint . going drain" >&2
	echo drain >"$state_base_dir/$name"

	((verbose)) && echo "making MergerFS branch $cur_mountpoint read only." >&2
	mergerfs.ctl -m "${cachedMountPoint}" remove path "$cur_mountpoint"
	mergerfs.ctl -m "${cachedMountPoint}" add path "$cur_mountpoint"=RO

	# これでdrain対象SSDへの書き込みはなくなったので、Drain(backing pool; HDD)への退避を開始する
	((verbose)) && echo "starting drain from $cur_mountpoint/ to ${backingMountPoint}/" >&2

	# shellcheck disable=SC2086
	rsync -a --exclude=${ssdDrainExcludes} --min-size="${ssdDrainMinSize}" --remove-source-files "$cur_mountpoint"/ "${backingMountPoint}"/
	find "$cur_mountpoint" -depth -type d -empty -not -path "$cur_mountpoint" -delete

	# Drainが完了したのでActive SSDとして再マウントする
	((verbose)) && echo "drain finished. now move mountpint $cur_mountpoint to active one" >&2
	mergerfs.ctl -m "${cachedMountPoint}" remove path "$cur_mountpoint"
	mergerfs.ctl -m "${cachedMountPoint}" add path "$cur_mountpoint"=RW

	((verbose)) && echo "$cur_mountpoint is now active branch on MergerFS ${cachedMountPoint} again." >&2
	echo active >"$state_base_dir/$name"
done
