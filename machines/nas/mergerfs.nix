{ pkgs, lib, ... }:
let
  # https://trapexit.github.io/mergerfs/latest/extended_usage_patterns/#tiered-cache
  # see also: ./disko.nix
  backingMountPoint = "/mnt/mergerfs/backing";
  cachedMountPoint = "/mnt/mergerfs/cached";
  hddReadaheadSize = 16384;  # 512B * x (16384 * 512 = 8MB)
  ssdRotationThresholdUseInPercent = 75; # SSDの容量使用率がN%以上になったらbacking HDD poolへの退避プロセス(cache-mover)対象にする
  ssdRotationLockFile = "/var/lock/ssd-rotate.lock";
  ssdDrainExcludes = "{'ROMs','Documents'}"; # rsync の --exclude オプション 。指定するとランダム読み書き性能が重要なアプリケーション（SyncThingなど）向けにHDDに退避せずSSDに置いたままにできる 
  ssdDrainMinSize = "8m"; # このサイズ未満のファイルはSSDに保持したままにする。小さいファイルはSSDの容量をあまり圧迫しないし、HDDに移すことでランダムアクセス性能がボトルネックになるため。全部同期したければ0に
  backingConf =  pkgs.writeText "mergerfs-backing.conf" ''
    branches=/mnt/hdd/esata_pmp*:/mnt/hdd/usb3_bot* 
    mountpoint=${backingMountPoint}
    # TODO: 同じ接続内(eSATA PMP内 や USB BOT内)並行write/readはひどいボトルネックになるのでなるべく発生しないようにしたい
    #       ただし接続を共有しないストレージ間については平行アクセスをむしろ推奨したい→両接続に1つずつ手動でディレクトリをつくる
    category.create=msppfrd
    minfreespace=10G
    passthrough.io=rw
    cache.files=partial
    func.readdir=cor:5:2
    readahead=8192
    xattr=nosys
    security-capability=false
    cache.attr=3600
    cache.readdir=true
    async-read=false
    fsname=mergerfs/backing
  '';
  cachedConf = pkgs.writeText "mergerfs-cached.conf" ''
    # NOTE: /mnt/ssd/ は mergerfsSSDRotatorScript によって空き領域がチェックされた上で適切なモードで追加される 
    branches=/mnt/hdd/esata_pmp*=NC:/mnt/hdd/usb3_bot*=NC
    mountpoint=${cachedMountPoint}
    # TODO: ./ROMs は 各SSDに分散された状態を維持してSSDに退避させたくないので最初にディレクトリを作る
    category.create=lus
    minfreespace=10G
    passthrough.io=rw
    cache.files=partial
    func.readdir=cor:8:2
    readahead=8192
    xattr=noattr
    security-capability=false
    cache.attr=3600
    cache.readdir=true
    async-read=false
    fsname=mergerfs/cached
  '';
  mergerfsHDDReadaheadScript = pkgs.writeShellApplication {
    name = "mergerfs-hdd-readahead";
    runtimeInputs = [
      pkgs.util-linux
    ];
    text = ''
      for dev in /dev/sd[b-z]; do
        if [[ "$(cat /sys/block/"$(basename "$dev")"/queue/rotational)" == "1" ]]; then
          blockdev --setra ${toString hddReadaheadSize} "$dev"
        fi
      done
    '';
  };
  mergerfsSSDRotatorScript = pkgs.writeShellApplication {
    name = "mergerfs-ssd-rotator";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.flock
      pkgs.gawk
      pkgs.mergerfs-tools
    ];
    text = ''
      cooldown_threshold=${toString ssdRotationThresholdUseInPercent} # ${toString ssdRotationThresholdUseInPercent}%以上で/mnt/ssd-cooldownにマウントポイントを移動する
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
      exec 9>$lock
      if ! flock -n -x 9; then
        echo "another script is already running for SSD rotation. exiting" >&2
        exit 0
      fi

      # 起動時以外にも mergerfs-cached.service がリスタートするとSSDのbranch参加状態もリセットされるので、状態をリセットする
      if (( init )); then
        if (( verbose )); then
          echo "called with --init option. initializing state" >&2
        fi
        rm -f $state_base_dir/*
      fi

      df -P $mount_base_dir/* | awk 'NR>=2 {gsub("('$mount_base_dir'/|%)",""); print $6,$5}' | while IFS=' ' read -r name use; do
        cur_state=$(touch $state_base_dir/"$name" && cat $state_base_dir/"$name")
        if [[ $cur_state == "drain" ]]; then
          # drain 中のプロセスを強制終了した時などにここに来ることがある
          if (( verbose )); then
            echo "$mount_base_dir/$name is in drain state. skipping" >&2
          fi
          continue
        fi

        if (( use < cooldown_threshold )); then
          if (( verbose )); then
            echo "$mount_base_dir/$name is $use% use (< $cooldown_threshold%). keeping active" >&2
          fi
          next_state=active
        else
          if (( verbose )); then
            echo "$mount_base_dir/$name reached $use% use (>= $cooldown_threshold%). going cooldown" >&2
          fi
          next_state=cooldown
        fi
        if [[ $cur_state != "$next_state" ]]; then
          mergerfs.ctl -m ${cachedMountPoint} remove path $mount_base_dir/"$name"
          if [[ $next_state == "cooldown" ]]; then
            next_mode=NC
          else
            next_mode=RW
          fi
          mergerfs.ctl -m ${cachedMountPoint} add path $mount_base_dir/"$name"="$next_mode"
          echo "$next_state" > $state_base_dir/"$name"
        fi
      done
    '';
  };

  mergerfsCacheMoverScript = pkgs.writeShellApplication {
    name = "mergerfs-cache-mover";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.flock
      pkgs.lsof
      pkgs.gawk
      pkgs.mergerfs-tools
      pkgs.rsync
    ];
    text = ''
      verbose=0
      for arg in "$@"; do
        if [[ $arg == "-v" ]]; then
          verbose=1
        fi
      done

      mount_base_dir=/mnt/ssd
      state_base_dir=/var/lib/ssd-rotate

      lock=${ssdRotationLockFile}
      exec 9>$lock
      if ! flock -n -x 9; then
        echo "another script is already running for SSD rotation. exiting" >&2
        exit 0
      fi
      find $state_base_dir/* -type f -maxdepth 0 -exec basename {} \; | while read -r name; do
        cur_state=$(touch $state_base_dir/"$name" && cat $state_base_dir/"$name")
        cur_mountpoint=$mount_base_dir/$name
        if [[ $cur_state == "" ]]; then
          echo "$cur_mountpoint 's state is uninitialized. skipping" >&2
          continue
        fi

        if [[ $cur_state == "active" ]]; then
          echo "$cur_mountpoint is active state. skipping" >&2
          continue
        fi
        # cooldown or (had canceled or aborted) drain

        if (( verbose )); then
          echo "checking mountpoint's file opening status: $cur_mountpoint ($cur_state)" >&2
        fi
        
        if lsof +D "$cur_mountpoint" | grep -q .; then
          if (( verbose )); then
            echo "someone is opening files under $cur_mountpoint . keeping $cur_state" >&2
          fi
          continue
        fi

        if (( verbose )); then
          echo "no one opening files under $cur_mountpoint . going drain" >&2
        fi
        echo drain > $state_base_dir/"$name"

        if (( verbose )); then
          echo "making MergerFS branch $cur_mountpoint read only." >&2
        fi
        mergerfs.ctl -m ${cachedMountPoint} remove path "$cur_mountpoint"
        mergerfs.ctl -m ${cachedMountPoint} add path "$cur_mountpoint"=RO

        # これでdrain対象SSDへの書き込みはなくなったので、Drain(backing pool; HDD)への退避を開始する
        echo "starting drain from $cur_mountpoint/ to ${backingMountPoint}/" >&2

        rsync -a --exclude=${ssdDrainExcludes} --min-size ${ssdDrainMinSize} --remove-source-files "$cur_mountpoint"/ ${backingMountPoint}/
        find "$cur_mountpoint" -depth -type d -empty -not -path "$cur_mountpoint" -delete

        # Drainが完了したのでActive SSDとして再マウントする
        if (( verbose )); then
          echo "drain finished. now move mountpint $cur_mountpoint to active one" >&2
        fi
        mergerfs.ctl -m ${cachedMountPoint} remove path "$cur_mountpoint"
        mergerfs.ctl -m ${cachedMountPoint} add path "$cur_mountpoint"=RW

        if (( verbose )); then
          echo "$cur_mountpoint is now active branch on MergerFS ${cachedMountPoint} again." >&2
        fi
        echo active > $state_base_dir/"$name"
      done
    '';
  };
in {
  systemd.services.mergerfs-hdd-readahead = {
    enable = true;
    description = "Set readahead parameters to HDDs";
    script = lib.getExe mergerfsHDDReadaheadScript;
    wantedBy = [ "local-fs.target" ];
    restartTriggers = [
      pkgs.util-linux
      mergerfsHDDReadaheadScript
      hddReadaheadSize
    ];
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
    unitConfig.WantsMountsFor = [
      "/mnt/hdd/esata_pmp_p1"
      "/mnt/hdd/esata_pmp_p2"
      "/mnt/hdd/esata_pmp_p3"

      "/mnt/hdd/esata_pmp_p5"
      "/mnt/hdd/esata_pmp_p6"
      "/mnt/hdd/esata_pmp_p7"
      "/mnt/hdd/esata_pmp_p8"

      "/mnt/hdd/usb3_bot_p0"
      "/mnt/hdd/usb3_bot_p1"
      "/mnt/hdd/usb3_bot_p2"
      "/mnt/hdd/usb3_bot_p4"
    ];
    wantedBy = [ "local-fs.target" ];
    restartTriggers = [
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
    # mergerfs-backing.serviceの後の実行順とすることで、HDD群がマウント済みであることを間接的に保障している
    after = [ "mergerfs-backing.service" ];
    requires = [ "mergerfs-backing.service" ];
    wantedBy = [ "local-fs.target" ];
    restartTriggers = [
      pkgs.mergerfs
      cachedConf
      cachedMountPoint
    ];
  };

  systemd.services.mergerfs-ssd-rotator-init = {
    enable = true;
    description = "Rotate SSD mountpoints based on their free space (service)";
    script = "${lib.getExe mergerfsSSDRotatorScript} -v --init";
    unitConfig.WantsMountsFor = [
      "/mnt/ssd/sata_p0"
      "/mnt/ssd/sata_p1"
      "/mnt/ssd/sata_p2"
      "/mnt/ssd/sata_p3"
      "/mnt/ssd/usb3_uas_p5"
    ];
    after = [
      "mergerfs-cached.service"
    ];
    requires = [
      "mergerfs-cached.service"
    ];
    wantedBy = [ "local-fs.target" ];
  };

  systemd.services.mergerfs-ssd-rotator-update = {
    enable = true;
    description = "Rotate SSD mountpoints based on their free space (service)";
    script = "${lib.getExe mergerfsSSDRotatorScript} -v";
    reloadTriggers = [
      mergerfsSSDRotatorScript
      cachedMountPoint
      ssdRotationLockFile
      ssdRotationThresholdUseInPercent
    ];
  };

  systemd.timers.mergerfs-ssd-rotator-update = {
    enable = true;
    description = "Rotate SSD mountpoints based on their free space (timer)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1m";
      Unit = "mergerfs-ssd-rotator-update.service";
    };
  };

  systemd.services.mergerfs-cache-mover = {
    enable = true;
    description = "Drain files from cooldown SSDs to MergerFS backing storage pool (service)";
    script = "${lib.getExe mergerfsCacheMoverScript} -v";
    reloadTriggers = [
      mergerfsCacheMoverScript
      cachedMountPoint
      ssdRotationLockFile
      ssdDrainExcludes
    ];
  };

  systemd.timers.mergerfs-cache-mover = {
    enable = true;
    description = "Drain files from cooldown SSDs to MergerFS backing storage pool (timer)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3m";
      OnUnitActiveSec = "3m";
      Unit = "mergerfs-cache-mover.service";
    };
  };

}
