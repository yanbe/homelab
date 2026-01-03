{ pkgs, lib, ... }:
let
  # https://trapexit.github.io/mergerfs/latest/extended_usage_patterns/#tiered-cache
  # see also: ./disko.nix
  backingMountPoint = "/mnt/mergerfs/backing";
  cachedMountPoint = "/mnt/mergerfs/cached";
  ssdRotationThresholdUseInPercent = 2; # SSDの容量使用率がN%以上になったらbacking HDD poolへの退避プロセス(cache-mover)対象にする
  ssdRotationLockFile = "/var/lock/ssd-rotation.lock";
  mergerfsSSDRotatorScript = pkgs.writeShellApplication {
    name = "mergerfs-ssd-rotator";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.flock
      pkgs.gawk
      pkgs.mount
      pkgs.mergerfs-tools
    ];
    text = ''
      cooldown_threshold=${toString ssdRotationThresholdUseInPercent} # ${toString ssdRotationThresholdUseInPercent}%以上で/mnt/ssd-cooldownにマウントポイントを移動する
      [[ "$1" == "-v" ]] && verbose=1
      base_dir=/mnt/ssd
      if [[ ! -e $base_dir ]]; then
        cur_status=-active
      else
        cur_status=
      fi
      cur_dir=$base_dir$cur_status

      lock=${ssdRotationLockFile}
      exec 9>$lock
      if ! flock -n -x 9; then
        echo "another script is already running for SSD rotation. exiting" >&2
        exit 0
      fi
      df -P $cur_dir/* | awk 'NR>=2 {gsub("('$cur_dir'/|%)",""); print $6,$5}' | while IFS=' ' read -r name use; do
        if (( use < cooldown_threshold )); then
          next_status=-active
          if (( verbose )); then
            echo "$cur_dir/$name is $use% use (< $cooldown_threshold%). keeping active" >&2
          fi
        else
          next_status=-cooldown
          if (( verbose )); then
            echo "$cur_dir/$name reached $use% use (>= $cooldown_threshold%). going cooldown" >&2
          fi
        fi
        if [[ "$cur_status" != "$next_status" ]]; then
          # ActiveからあらたにHDDに退避する準備が必要であることが分かったSSDに対する処理
          # MergerFSが新たなcreateを受け付けないようにするため、一度branchesから取り除き、
          if [[ $cur_status == "-active" && $next_status == "-cooldown" ]]; then
            mergerfs.ctl -m ${cachedMountPoint} remove path $base_dir$cur_status/"$name"
          fi

          # /mnt/ssd-cooldown としてマウントしなおし、MergerFSのbranchとしても NC で追加する
          mkdir -p $base_dir$next_status/"$name"
          mount --move $base_dir$cur_status/"$name" $base_dir$next_status/"$name"
          if [[ $cur_status == "-active" && $next_status == "-cooldown" ]]; then
            mergerfs.ctl -m ${cachedMountPoint} add path $base_dir$next_status/"$name"=NC
          fi
          rmdir -p --ignore-fail-on-non-empty $base_dir$cur_status/"$name"
        fi
      done
    '';
  };
  backingConf =  pkgs.writeText "mergerfs-backing.conf" ''
    branches=/mnt/hdd/esata_pmp*:/mnt/hdd/usb3_bot* 
    mountpoint=${backingMountPoint}
    # TODO: 同じ接続内(eSATA PMP内 や USB BOT内)並行write/readはひどいボトルネックになるのでなるべく発生しないようにしたい
    #       ただし接続を共有しないストレージ間については平行アクセスをむしろ推奨したい→両接続に1つずつ手動でディレクトリをつくる
    category.create=msppfrd
    func.getattr=newest
    minfreespace=5G
    cache.files=partial
    fsname=mergerfs/backing
  '';
  cachedConf = pkgs.writeText "mergerfs-cached.conf" ''
    branches=/mnt/ssd-active/*:/mnt/ssd-cooldown/*=NC:/mnt/ssd-drain/*=RO:/mnt/hdd/esata_pmp*=NC:/mnt/hdd/usb3_bot*=NC
    mountpoint=${cachedMountPoint}
    # TODO: ./ROMs は 各SSDに分散された状態を維持してSSDに退避させたくないので最初にディレクトリを作る
    category.create=epff
    func.getattr=newest
    minfreespace=5G
    cache.files=partial
    fsname=mergerfs/cached
  '';

  mergerfsCacheMoverScript = pkgs.writeShellApplication {
    name = "mergerfs-cache-mover";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.flock
      pkgs.lsof
      pkgs.gawk
      pkgs.mount
      pkgs.mergerfs-tools
      pkgs.rsync
    ];
    text = ''
      [[ "$1" == "-v" ]] && verbose=1
      base_dir=/mnt/ssd

      lock=${ssdRotationLockFile}
      exec 9>$lock
      if ! flock -n -x 9; then
        echo "another script is already running for SSD rotation. exiting" >&2
        exit 0
      fi

      find /mnt/ssd-{cooldown,drain}/* -type d  -mindepth 0 -maxdepth 0 2>/dev/null | awk 'BEGIN{FS="/"}{print $0,$4}' | while read -r curr_mountpoint name; do
        if (( verbose )); then
          echo "checking opened files: $curr_mountpoint" >&2
        fi
        if ! lsof +D "$curr_mountpoint" | grep -q .; then
          next_status=-drain
          if (( verbose )); then
            echo "no one opening files under $curr_mountpoint . going drain" >&2
          fi
        else
          next_status=-cooldown
          if (( verbose )); then
            echo "someone is opening files under $curr_mountpoint . keeping cooldown" >&2
          fi
        fi

        if [[ $next_status == "-drain" ]]; then
          drain_mountpoint=$base_dir$next_status/"$name"
          if [[ $curr_mountpoint != "$drain_mountpoint" ]]; then
            # /mnt/ssd-drain/$name としてマウントしなおし、MergerFSのbranchとしても RO で入れ替える
            mergerfs.ctl -m ${cachedMountPoint} remove path "$curr_mountpoint"
            mkdir -p "$drain_mountpoint"
            mount --move "$curr_mountpoint" "$drain_mountpoint"
            mergerfs.ctl -m ${cachedMountPoint} add path "$drain_mountpoint"=RO
            rmdir -p --ignore-fail-on-non-empty "$curr_mountpoint"
          fi

          # これでdrain対象SSDへの書き込みはなくなったので、Drain(backing pool; HDD)への退避を開始する
          if (( verbose )); then
            echo "starting drain from $drain_mountpoint/ to ${backingMountPoint}/" >&2
          fi
          rsync -a --remove-source-files "$drain_mountpoint"/ ${backingMountPoint}/
          find "$drain_mountpoint" -depth -type d -empty -not -path "$drain_mountpoint" -delete

          # Drainが完了したのでActive SSDとして再マウントする
          if (( verbose )); then
            echo "drain finished. now move mountpint $drain_mountpoint to active one" >&2
          fi
          mergerfs.ctl -m ${cachedMountPoint} remove path "$drain_mountpoint"
          final_status=-active
          active_mountpoint=$base_dir$final_status/"$name"

          mkdir -p "$active_mountpoint"
          mount --move "$drain_mountpoint" "$active_mountpoint"
          rmdir -p --ignore-fail-on-non-empty "$drain_mountpoint"

          if (( verbose )); then
            echo "mountpoint is successfully promoted to $active_mountpoint . now going to back to active on MergerFS ${cachedMountPoint} branch" >&2
          fi
          mergerfs.ctl -m ${cachedMountPoint} add path "$active_mountpoint"

          if (( verbose )); then
            echo "$active_mountpoint is now active on MergerFS ${cachedMountPoint} again." >&2
          fi
        fi
      done
    '';
  };
in {
  systemd.services.mergerfs-ssd-rotator = {
    enable = true;
    description = "Rotate SSD mountpoints based on their free space (service)";
    script = "${lib.getExe mergerfsSSDRotatorScript} -v";
    after = [
      "mnt-ssd-sata_p0.mount"
      "mnt-ssd-sata_p1.mount"
      "mnt-ssd-sata_p2.mount"
      "mnt-ssd-sata_p3.mount"
      "mnt-ssd-usb_uas_p5.mount"
    ];
    wantedBy = [ "multi-user.target" ];
    reloadTriggers = [
      mergerfsSSDRotatorScript
      cachedMountPoint
      ssdRotationLockFile
      ssdRotationThresholdUseInPercent
    ];
  };
  systemd.timers.mergerfs-ssd-rotator = {
    enable = true;
    description = "Rotate SSD mountpoints based on their free space (timer)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnUnitActiveSec = "1m";
      Unit = "mergerfs-ssd-rotator.service";
    };
  };

  systemd.services.mergerfs-backing = {
    enable = true;
    description = "Mount MergerFS internal backing (HDDs) storage pool";
    path = [
      pkgs.coreutils
      pkgs.mergerfs
      pkgs.fuse
    ];
    preStart = "mkdir -p ${backingMountPoint}";
    script = "mergerfs -f -o config=${backingConf}";
    postStop = "fusermount -uz ${backingMountPoint} && rmdir -p ${backingMountPoint}";
    after = [
      "mnt-hdd-esata_pmp_p0.mount"
      "mnt-hdd-esata_pmp_p1.mount"
      "mnt-hdd-esata_pmp_p2.mount"
      "mnt-hdd-esata_pmp_p3.mount"

      "mnt-hdd-esata_pmp_p5.mount"
      "mnt-hdd-esata_pmp_p6.mount"
      "mnt-hdd-esata_pmp_p7.mount"
      "mnt-hdd-esata_pmp_p8.mount"

      "mnt-hdd-usb3_bot_p0.mount"
      "mnt-hdd-usb3_bot_p1.mount"
      "mnt-hdd-usb3_bot_p2.mount"
      "mnt-hdd-usb3_bot_p4.mount"
    ];
    wantedBy = [ "multi-user.target" ];
    reloadTriggers = [
      pkgs.mergerfs
      backingConf
      backingMountPoint
    ];
  };
  
  systemd.services.mergerfs-cached = {
    enable = true;
    description = "Mount MergerFS cached (SSDs in front of HDDs) storage pool";
    path = [
      pkgs.coreutils
      pkgs.mergerfs
      pkgs.fuse
    ];
    preStart = "mkdir -p ${cachedMountPoint}";
    script = "mergerfs -f -o config=${cachedConf}";
    postStop = "fusermount -uz ${cachedMountPoint} && rmdir -p ${cachedMountPoint}";
    after = [
      "mergerfs-ssd-rotator.service"
      "mergerfs-backing.service"
    ];
    requires = [
      "mergerfs-ssd-rotator.service"
      "mergerfs-backing.service"
    ];
    wantedBy = [ "multi-user.target" ];
    reloadTriggers = [
      pkgs.mergerfs
      mergerfsSSDRotatorScript
      cachedConf
      cachedMountPoint
    ];
  };

  systemd.services.mergerfs-cache-mover = {
    enable = true;
    description = "Drain files from cooldown SSDs to MergerFS backing storage pool (service)";
    script = "${lib.getExe mergerfsCacheMoverScript} -v";
    after = [
      "mergerfs-cached.service"
    ];
    requires = [
      "mergerfs-cached.service"
    ];
    wantedBy = [ "multi-user.target" ];
    reloadTriggers = [
      mergerfsCacheMoverScript
      cachedMountPoint
      ssdRotationLockFile
    ];
  };

  systemd.timers.mergerfs-cache-mover = {
    enable = true;
    description = "Drain files from cooldown SSDs to MergerFS backing storage pool (timer)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnUnitActiveSec = "3m";
      Unit = "mergerfs-cache-mover.service";
    };
  };

}
