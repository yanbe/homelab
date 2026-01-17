{
  # see also: ./disko.nix
  services.snapraid = {
    enable = true;
    dataDisks = {
      d01 = "/mnt/ssd/sata_p0/";
      d02 = "/mnt/ssd/sata_p1/";
      d03 = "/mnt/ssd/sata_p2/";
      d04 = "/mnt/ssd/sata_p3/";
      d05 = "/mnt/ssd/usb3_uas_p5/";

      d06 = "/mnt/hdd/esata_pmp_p1/";
      d07 = "/mnt/hdd/esata_pmp_p2/";
      d08 = "/mnt/hdd/esata_pmp_p3/";

      d09 = "/mnt/hdd/esata_pmp_p5/";
      d10 = "/mnt/hdd/esata_pmp_p6/";
      d11 = "/mnt/hdd/esata_pmp_p7/";
      d12 = "/mnt/hdd/esata_pmp_p8/";

      d13 = "/mnt/hdd/usb3_bot_p0/";
      d14 = "/mnt/hdd/usb3_bot_p1/";
      d15 = "/mnt/hdd/usb3_bot_p2/";
    };
    contentFiles = [
      "/mnt/hdd/esata_pmp_p1/snapraid.content"
      "/mnt/hdd/esata_pmp_p2/snapraid.content"
      "/mnt/hdd/esata_pmp_p6/snapraid.content"
    ];
    parityFiles = [
      "/mnt/hdd/sata_parity_p5/snapraid.parity"
      "/mnt/hdd/esata_parity_pmp_p0/snapraid.z-parity"
    ];
    sync.interval = "04:30";
    scrub.plan = 10;
    scrub.interval = "Sun *-*-* 05:00:00";
  };
}