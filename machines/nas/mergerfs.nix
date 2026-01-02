{ pkgs, lib, ... }:
let
  # https://trapexit.github.io/mergerfs/latest/extended_usage_patterns/#tiered-cache
  # see also: ./disko.nix
  cachedMountPoint = "/mnt/mergerfs/cached";
  backingMountPoint = "/mnt/mergerfs/backing";

  mergerfsSSDRotatorScript = pkgs.writeShellApplication {
    name = "mergerfs-ssd-rotator";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      echo "Hello, mergerfsSSDRotatorScript!"
    '';
  };
  cachedConf = pkgs.writeText "mergerfs-cached.conf" ''
    branches=/mnt/ssd/*:/mnt/hdd/esata_pmp*=NC:/mnt/hdd/usb3_bot*=NC
    mountpoint=${cachedMountPoint}
    # TODO: ./ROMs は 各SSDに分散された状態を維持してSSDに対比させたくないので最初にディレクトリを作る
    category.create=msppfrd
    func.getattr=newest
    minfreespace=5G
    cache.files=partial
    fsname=mergerfs-cached
  '';
  backingConf =  pkgs.writeText "mergerfs-backing.conf" ''
    branches=/mnt/hdd/esata_pmp*:/mnt/hdd/usb3_bot* 
    mountpoint=${backingMountPoint}
    # TODO: 同じ接続内(eSATA PMP内 や USB BOT内)並行write/readはひどいボトルネックになるのでなるべく発生しないようにしたい
    #       ただし接続を共有しないストレージ間については平行アクセスをむしろ推奨したい→両接続に1つずつ手動でディレクトリをつくる
    category.create=msppfrd
    func.getattr=newest
    minfreespace=5G
    cache.files=partial
    fsname=mergerfs-backing
  '';

  mergerfsCacheMoverScript = pkgs.writeShellApplication {
    name = "mergerfs-cache-mover";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      echo "Hello mergerfsCacheMoverScript!"
    '';
  };
in {
  systemd.services.mergerfs-ssd-rotator = {
    enable = true;
    description = "Rotate SSD mountpoints based on their free space";
    script = lib.getExe mergerfsSSDRotatorScript;
    after = [
      "mnt-ssd-sata_p0.mount"
      "mnt-ssd-sata_p1.mount"
      "mnt-ssd-sata_p2.mount"
      "mnt-ssd-sata_p3.mount"
      "mnt-ssd-usb_uas_p5.mount"
    ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [
      mergerfsSSDRotatorScript
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
    restartTriggers = [
      pkgs.mergerfs
      mergerfsSSDRotatorScript
      cachedConf
      cachedMountPoint
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
    restartTriggers = [
      pkgs.mergerfs
      backingConf
      backingMountPoint
    ];
  };

  systemd.services.mergerfs-cache-mover = {
    enable = true;
    description = "Move files from SSD to MergerFS backing storage pool";
    script = lib.getExe mergerfsCacheMoverScript;
    after = [
        "mergerfs-cached.service"
        "mergerfs-backing.service"
    ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [
      mergerfsCacheMoverScript
    ];
  };
}
