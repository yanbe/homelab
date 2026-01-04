{ pkgs, config, lib, ... }:
let
  ssd_f2fs = name: device: {
    ${name} = {
      device = device;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          data = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "f2fs";
              mountpoint = "/mnt/ssd/${name}";
              extraArgs = [
                # f2fs mkfs f2fs-specific flags:
                "-O"
                "extra_attr,inode_checksum,sb_checksum,compression"
              ];
              mountOptions = [
                # f2fs マウント最適化パラメータ
                "compress_algorithm=zstd"
                "compress_chksum"
                "atgc"
                "gc_merge"
                "background_gc=off"
                "nodiscard" # services.fstrim で明示的に TRIMをおこなう
                "lazytime"
                "noatime"
                "nodiratime"
                "user_xattr"
                "nofail"
                "private"
              ];
            };
          };
        };
      };
    };
  };
  hdd_xfs = name: device: {
    ${name} = {
      device = device;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          data = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "xfs";
              mountpoint = "/mnt/hdd/${name}";
              extraArgs = [
                # mkfs.xfs に渡す追加オプション
                "-m" "crc=1"          # metadata CRC を有効化（推奨）
                "-m" "finobt=1"       # free inode btree を有効化
              ] ++ lib.lists.optionals (lib.hasInfix "pmp" name) [
                "-d" "agcount=16"
              ];
              mountOptions = [
                # マウント時のパフォーマンスオプション
                "noatime"
                "nodiratime"
                "inode64"
                "attr2"
                "logbufs=8"
                "logbsize=256k"
                "allocsize=512m"
                "nofail"
                "private"
              ];
            };
          };
        };
      };
    };
  };
in {
  disko.devices = {
    # {deviceType}_{connectionType}(_{specialUsage})(_{protocol})_{port}
    disk = {
      stick_usb2_in = {
        device = "/dev/disk/by-id/usb-BUFFALO_ClipDrive_408183A840A2D8B2-0:0";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            BOOT = {
              priority = 1;
              size = "1M";
              type = "EF02"; # for grub MBR
            };
            boot = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
                mountOptions = [ "noatime" ];
              };
            };
          };
        };
      };
      stick_usb3_ex = {
        device = "/dev/disk/by-id/usb-_USB_DISK_07083ACF31B4C014-0:0" ;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            nix = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/nix";
                mountOptions = [ "noatime" ];
              };
            };
          };
        };
      };
    }
    // ssd_f2fs "sata_p0" "/dev/disk/by-id/ata-INTEL_SSDSC2CT120A3_CVMP229202QL120BGN"
    // ssd_f2fs "sata_p1" "/dev/disk/by-id/ata-Samsung_SSD_750_EVO_120GB_S3F2NWAHC24663H"
    // ssd_f2fs "sata_p2" "/dev/disk/by-id/ata-Samsung_SSD_750_EVO_120GB_S2SGNWAH267962P"
    // ssd_f2fs "sata_p3" "/dev/disk/by-id/ata-Samsung_SSD_750_EVO_120GB_S3F2NWAHC04260K"
    # ssd_sata_p4 はない: esata(PMP)の中で最初に認識されたデバイス(接続状況によって不定)がBIOSからsata_p4になるので欠番にしている

    // ssd_f2fs "usb3_uas_p5" "/dev/disk/by-id/ata-ORICO_UB202412100698"
    // hdd_xfs "sata_parity_p5" "/dev/disk/by-id/ata-ST2000DL003-9VT166_5YD5AHQ8"

    # 裸族のスカイタワー10BayはeSATA・USBともには自分の環境ではコントローラーごとに４台ずつ計８台までしか安定して認識されない
    // hdd_xfs "esata_parity_pmp_p0" "/dev/disk/by-id/ata-WDC_WD20EARS-00S8B1_WD-WCAVY2626056"
    // hdd_xfs "esata_pmp_p1" "/dev/disk/by-id/ata-WDC_WD20EARS-00MVWB0_WD-WMAZA2671006"
    // hdd_xfs "esata_pmp_p2" "/dev/disk/by-id/ata-WDC_WD20EARS-00MVWB0_WD-WCAZA0260439"
    // hdd_xfs "esata_pmp_p3" "/dev/disk/by-id/ata-WDC_WD20EARS-00MVWB0_WD-WMAZA3492202"

    // hdd_xfs "esata_parity_pmp_p5" "/dev/disk/by-id/ata-SAMSUNG_HD203WI_S1UYJ1KSC06839"
    // hdd_xfs "esata_pmp_p6" "/dev/disk/by-id/ata-WDC_WD20EARS-00MVWB0_WD-WCAZA0146677"
    // hdd_xfs "esata_pmp_p7" "/dev/disk/by-id/ata-SAMSUNG_HD203WI_S1UYJ1KSC07024"
    // hdd_xfs "esata_pmp_p8" "/dev/disk/by-id/ata-SAMSUNG_HD203WI_S1UYJ1KSC07059"

    // hdd_xfs "usb3_bot_p0" "/dev/disk/by-id/ata-SAMSUNG_HD203WI_S1UYJ1KSC07027"
    // hdd_xfs "usb3_bot_p1" "/dev/disk/by-id/ata-SAMSUNG_HD103SJ_S246JD6ZC02757"
    // hdd_xfs "usb3_bot_p2" "/dev/disk/by-id/ata-MB0500EBNCR_WMAYP0E80UEX"
    // hdd_xfs "usb3_bot_p4" "/dev/disk/by-id/ata-TOSHIBA_MK2565GSX_Z0KHC1TVT"
    ;
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=2G"
        "defaults"
        "mode=755"
        "private"
      ];
    };
  };

  environment.persistence."/nix/persistent" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"
      #"/var/log" # for boot truble investigation purpose only
    ];
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}