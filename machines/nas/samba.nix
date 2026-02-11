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

        # 高速転送用
        "aio read size" = "4M";
        "aio write size" = "4M";
        "use sendfile" = "yes";
        "strict sync" = "no";
        "sync always" = "no";
        "durable handles" = "no";
        "kernel oplocks" = "yes";
        oplocks = "yes";
        "server multi channel support" = "yes";

        "server signing" = "auto";
        "client signing" = "auto";

        # ゲストアクセス（家庭内向け）を無効化
        "guest account" = "nobody";
        "map to guest" = "never";
        "security" = "user";
        # root でのログインを明示的に許可（追加）
        "invalid users" = [];

        # 許可するネットワークを限定 [cite: 11]
        "hosts allow" = "192.168.0.0/16 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";

        # SnapRAID関連ファイルを隠す
        "hide files" = "/snapraid.*/";
        "veto files" = "/snapraid.*/";
        "delete veto files" = "no";
      };
      Shared = {
        # see also: ./mergerfs.nix
        path = "/mnt/mergerfs/cached";
        "read only" = "no";
        browseable = "yes";

        "guest ok" = "no";
        # 許可するユーザーを root に限定
        "valid users" = "root";

        "force user" = "root";
        "force group" = "root";

        "vfs objects" = "shadow_copy2";
        "shadow:snapdirseverywhere" = "yes";
        "shadow:localtime" = "yes";
        "shadow:format" = "@%Y.%m.%d-%H.%M.%S";
      };
    };
  };
}