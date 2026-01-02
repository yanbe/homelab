{ pkgs , ... }:
{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
    openFirewall = true;
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;  
  };

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server role" = "standalone server";
        "netbios name" = "NAS";
        "server string" = "N54L ZFS Server";
        security = "user";

        # 高速転送用
        "aio read size" = 1;
        "aio write size" = 1;
        "use sendfile" = "no";
        "strict sync" = "no";
        "sync always" = "no";
        "server multi channel support" = "yes";

        "server signing" = "auto";
        "client signing" = "auto";

        # ゲストアクセス（家庭内向け）
        "guest account" = "nobody";
        "map to guest" = "bad user";

        "hosts allow" = "192.168.0.0/16 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";

        # SnapRAID関連ファイルを隠す
        "hide files" = "/snapraid.*/";
        "veto files" = "/snapraid.*/";
        "delete veto files" = "no";
      };
      media = {
        # see also: ./mergerfs.nix
        path = "/mnt/mergerfs/cached";
        "read only" = "no";
        "guest ok" = "yes";
        "force user" = "root";
        "force group" = "root";

        "strict locking" = "no";
        oplocks = "no";
        "kernel oplocks" = "no";
      };
    };
  };
}