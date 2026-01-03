{
  # see also: ./disko.nix
  services.snapraid = {
    enable = true;
    dataDisks = {
      d1 = "/mnt/ssd-active/sata_p0/";
      d2 = "/mnt/ssd-active/sata_p1/";
      d3 = "/mnt/ssd-active/sata_p2/";
      d4 = "/mnt/ssd-active/sata_p3/";
      d5 = "/mnt/ssd-active/usb3_uas_p5/";

      d6 = "/mnt/hdd/esata_pmp_p1/";
      d7 = "/mnt/hdd/esata_pmp_p2/";
      d8 = "/mnt/hdd/esata_pmp_p3/";

      d9 = "/mnt/hdd/esata_pmp_p5/";
      d10 = "/mnt/hdd/esata_pmp_p6/";
      d11 = "/mnt/hdd/esata_pmp_p7/";
      d12 = "/mnt/hdd/esata_pmp_p8/";

      d13 = "/mnt/hdd/usb3_bot_p1/";
      d14 = "/mnt/hdd/usb3_bot_p2/";
      d16 = "/mnt/hdd/usb3_bot_p4/";
    };
    contentFiles = [
      "/mnt/hdd/esata_pmp_p1/snapraid.content"
      "/mnt/hdd/esata_pmp_p2/snapraid.content"
      "/mnt/hdd/esata_pmp_p5/snapraid.content"
      "/mnt/hdd/usb3_bot_p1/snapraid.content"
    ];
    parityFiles = [
      "/mnt/hdd/sata_parity_p5/snapraid.parity"
      "/mnt/hdd/esata_parity_pmp_p0/snapraid.2-parity"
      "/mnt/hdd/usb3_parity_bot_p0/snapraid.3-parity"
    ];
    sync.interval = "04:30";
    scrub.plan = 10;
    scrub.interval = "Sun *-*-* 05:00:00";
  };
}