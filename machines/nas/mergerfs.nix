{ pkgs, ... }:
let
  # https://trapexit.github.io/mergerfs/latest/extended_usage_patterns/#tiered-cache
  # see also: ./disko.nix
  mergerfsConf = pkgs.writeText "mergerfs.conf" ''
    branches=/mnt/ssd*:/mnt/hdd_esata_pmp*=NC:/mnt/hdd_usb3_bot*=NC
    mountpoint=/mnt/storage
    category.create=pfrd
    func.getattr=newest
    minfreespace=5G
    cache.files=partial
    fsname=mergerfs
  '';
  mergerfsBaseConf =  pkgs.writeText "mergerfs-base.conf" ''
    branches=/mnt/hdd_esata_pmp*:/mnt/hdd_usb3_bot*
    mountpoint=/mnt/storage-base
    category.create=epff
    func.getattr=newest
    minfreespace=5G
    cache.files=partial
    fsname=mergerfs-base
  '';
in {
  systemd.services.mergerfs = {
    enable = true;
    description = "Mount MergerFS shared storage pool";
    path = [
      pkgs.coreutils
      pkgs.mergerfs
      pkgs.fuse
    ];
    preStart = "mkdir -p /mnt/storage";
    script = "mergerfs -f -o config=${mergerfsConf}";
    postStop = "fusermount -uz /mnt/storage && rmdir /mnt/storage";
    after = [
      "mnt-ssd_sata_p0.mount"
      "mnt-ssd_sata_p1.mount"
      "mnt-ssd_sata_p2.mount"
      "mnt-ssd_sata_p3.mount"
      "mnt-ssd_usb_uas_p5.mount"

      "mnt-hdd_esata_pmp_p0.mount"
      "mnt-hdd_esata_pmp_p1.mount"
      "mnt-hdd_esata_pmp_p2.mount"
      "mnt-hdd_esata_pmp_p3.mount"

      "mnt-hdd_esata_pmp_p5.mount"
      "mnt-hdd_esata_pmp_p6.mount"
      "mnt-hdd_esata_pmp_p7.mount"
      "mnt-hdd_esata_pmp_p8.mount"

      "mnt-hdd_usb3_bot_p0.mount"
      "mnt-hdd_usb3_bot_p1.mount"
      "mnt-hdd_usb3_bot_p2.mount"
      "mnt-hdd_usb3_bot_p4.mount"
    ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [
      pkgs.mergerfs
      mergerfsConf
    ];
  };

  systemd.services.mergerfs-base = {
    enable = true;
    description = "Mount MergerFS base storage pool";
    path = [
      pkgs.coreutils
      pkgs.mergerfs
      pkgs.fuse
    ];
    preStart = "mkdir -p /mnt/storage-base";
    script = "mergerfs -f -o config=${mergerfsBaseConf}";
    postStop = "fusermount -uz /mnt/storage-base && rmdir /mnt/storage-base";
    after = [
      "mnt-hdd_esata_pmp_p0.mount"
      "mnt-hdd_esata_pmp_p1.mount"
      "mnt-hdd_esata_pmp_p2.mount"
      "mnt-hdd_esata_pmp_p3.mount"

      "mnt-hdd_esata_pmp_p5.mount"
      "mnt-hdd_esata_pmp_p6.mount"
      "mnt-hdd_esata_pmp_p7.mount"
      "mnt-hdd_esata_pmp_p8.mount"

      "mnt-hdd_usb3_bot_p0.mount"
      "mnt-hdd_usb3_bot_p1.mount"
      "mnt-hdd_usb3_bot_p2.mount"
      "mnt-hdd_usb3_bot_p4.mount"
    ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [
      pkgs.mergerfs
      mergerfsBaseConf
    ];
  };
}
