{ pkgs, lib, ... }:
let
  # https://trapexit.github.io/mergerfs/latest/extended_usage_patterns/#tiered-cache
  # see also: ./disko.nix
  backingMountPoint = "/mnt/mergerfs/backing";
  cachedMountPoint = "/mnt/mergerfs/cached"; # 512B * x (16384 * 512 = 8MB)
  ssdRotationThresholdUseInPercent = 75; # SSDの容量使用率がN%以上になったらbacking HDD poolへの退避プロセス(cache-mover)対象にする
  ssdRotationLockFile = "/var/lock/ssd-rotate.lock";
  ssdDrainExcludes = "{'ROMs','Documents'}"; # rsync の --exclude オプション 。指定するとランダム読み書き性能が重要なアプリケーション（SyncThingなど）向けにHDDに退避せずSSDに置いたままにできる
  ssdDrainMinSize = "8m"; # このサイズ未満のファイルはSSDに保持したままにする。小さいファイルはSSDの容量をあまり圧迫しないし、HDDに移すことでランダムアクセス性能がボトルネックになるため。全部同期したければ0に
  snapshotEnabledDirs = "/mnt/mergerfs/cached/Documents"; # Samba経由でshadow copyを有効にするために、rsyncによるスナップショットを有効にするディレクトリ。GLOB({Documents,Projects})で複数指定も可能
  backingConf = pkgs.writeText "mergerfs-backing.conf" ''
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
    cache.attr=1
    cache.readdir=false
    async-read=false
    fsname=mergerfs/backing
  '';
  cachedConf = pkgs.writeText "mergerfs-cached.conf" ''
    # NOTE: /mnt/ssd/ は mergerfsSSDRotatorScript によって空き領域がチェックされた上で適切なモードで追加される
    branches=/mnt/hdd/esata_pmp*=NC:/mnt/hdd/usb3_bot*=NC
    mountpoint=${cachedMountPoint}
    # TODO: SSDに維持したいファイルを転送する際は category.create=mfs にし、が終わったらcategory.create=ffにする
    category.create=ff
    minfreespace=10G
    passthrough.io=rw
    cache.files=partial
    func.readdir=cor:8:2
    readahead=8192
    xattr=noattr
    security-capability=false
    cache.attr=1
    cache.readdir=false
    async-read=false
    fsname=mergerfs/cached
  '';

  mergerfsSSDRotatorScript = pkgs.writeShellApplication {
    name = "mergerfs-ssd-rotator";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.flock
      pkgs.gawk
      pkgs.mergerfs-tools
    ];
    text = ''
      cooldown_threshold=${toString ssdRotationThresholdUseInPercent}
      cachedMountPoint="${cachedMountPoint}"
      ssdRotationLockFile="${ssdRotationLockFile}"

      ${builtins.readFile ./mergerfs-ssd-rotator.sh}
    '';
  };
  mergerfsCacheMoverScript = pkgs.writeShellApplication {
    name = "mergerfs-cache-mover";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.flock
      pkgs.lsof
      pkgs.mergerfs-tools
      pkgs.rsync
    ];
    text = ''
      ssdRotationLockFile="${ssdRotationLockFile}"
      cachedMountPoint="${cachedMountPoint}"
      backingMountPoint="${backingMountPoint}"
      ssdDrainExcludes="${ssdDrainExcludes}"
      ssdDrainMinSize="${ssdDrainMinSize}"

      ${builtins.readFile ./mergerfs-cache-mover.sh}
    '';
  };
  snapshotOnModifyScript = pkgs.writeShellApplication {
    name = "mergerfs-snapshot";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.inotify-tools
      pkgs.rsync
      pkgs.findutils
    ];
    text = ''
      snapshotEnabledDirs="${snapshotEnabledDirs}"

      ${builtins.readFile ./mergerfs-snapshot.sh}
    '';
  };
in
{
  systemd.services.mergerfs-backing = {
    # ... (after, before, wants は前回のままでOK)
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      TimeoutStopSec = "30s";
    };

    path = [
      pkgs.coreutils
      pkgs.mergerfs
      pkgs.fuse
    ];

    # 修正：一度アンマウントを試みてから、ディレクトリの権限を 777 に
    preStart = ''
      mkdir -p ${backingMountPoint}
    '';

    # 修正：オプションを整理
    # default_permissions を除外（または明示的に no に）するために
    # オプションをシンプルにします
    script = "mergerfs -f -o config=${backingConf},allow_other,use_ino,cache.files=off";

    postStop = "${pkgs.fuse}/bin/fusermount -u -z ${backingMountPoint} || true";
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.mergerfs-cached = {
    # ...
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      TimeoutStopSec = "30s";
    };

    path = [
      pkgs.coreutils
      pkgs.mergerfs
      pkgs.fuse
    ];
    preStart = ''
      mkdir -p ${cachedMountPoint}
    '';

    # 修正：こちらも同様に整理
    script = "mergerfs -f -o config=${cachedConf},allow_other,use_ino,cache.files=off";
    postStart = "${lib.getExe mergerfsSSDRotatorScript} --init";

    postStop = "${pkgs.fuse}/bin/fusermount -u -z ${cachedMountPoint} || true";
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.mergerfs-ssd-rotator = {
    enable = true;
    description = "Rotate SSD mountpoints based on their free space (service)";
    script = "${lib.getExe mergerfsSSDRotatorScript}";
    after = [
      "mergerfs-cached.service"
    ];
    serviceConfig = {
      Type = "oneshot";
    };
    wantedBy = [ "default.target" ];
  };

  systemd.timers.mergerfs-ssd-rotator = {
    enable = true;
    description = "Rotate SSD mountpoints based on their free space (timer)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1m";
      Unit = "mergerfs-ssd-rotator.service";
    };
  };

  systemd.services.mergerfs-cache-mover = {
    enable = true;
    description = "Drain files from cooldown SSDs to MergerFS backing storage pool (service)";
    script = "${lib.getExe mergerfsCacheMoverScript}";
    serviceConfig = {
      Type = "oneshot";
    };
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

  systemd.services.mergerfs-snapshot-on-modify = {
    enable = true;
    description = "Create snapshot on modification under specified directories";

    # 強力な依存関係の追加
    requires = [ "mergerfs-cached.service" ];
    after = [
      "mergerfs-cached.service"
      "local-fs.target"
    ];
    bindsTo = [ "mergerfs-cached.service" ];

    serviceConfig = {
      Type = "simple";
      # 失敗してもすぐリトライせず、少し待たせる（無限ループ対策）
      Restart = "on-failure";
      RestartSec = "10s";
      # サービスが暴走した時にシステムを止めないように
      StartLimitIntervalSec = "60s";
      StartLimitBurst = 3;
    };

    path = [
      pkgs.coreutils
      pkgs.rsync
      pkgs.inotify-tools
      pkgs.bash
    ];

    script = "${lib.getExe snapshotOnModifyScript}";

    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.mergerfs-snapshot-cleanup = {
    description = "Cleanup old MergerFS snapshots";
    after = [ "mergerfs-cached.service" ];
    requires = [ "mergerfs-cached.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };

    script =
      let
        cleanupScript = pkgs.writeShellApplication {
          name = "mergerfs-snapshot-cleanup";
          runtimeInputs = [
            pkgs.findutils
            pkgs.coreutils
            pkgs.bash
          ];
          text = ''
            snapshotEnabledDirs="${snapshotEnabledDirs}"

            ${builtins.readFile ./mergerfs-snapshot-cleanup.sh}
          '';
        };
      in
      "${cleanupScript}/bin/mergerfs-snapshot-cleanup";
  };
}
