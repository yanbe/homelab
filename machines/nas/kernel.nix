{ pkgs, ... }:

{
  # 1. カーネルパッケージの定義と、ignoreConfigErrors の適用
  boot.kernelPackages = pkgs.linuxPackages_6_18.extend (selfK: superK: {
    kernel = superK.kernel.override { ignoreConfigErrors = true; };
  });

  # TPM 1.2 を扱うために必要なカーネルモジュール
  boot.initrd.kernelModules = [ "tpm_tis" "tpm_infineon" ];

  # 2. Adiantum を有効にするためのパッチ設定
  boot.kernelPatches = [
    {
      name = "enable-aditum-for-n54l";
      patch = null;
      extraConfig = ''
        CRYPTO_ADIANTUM y
        CRYPTO_CHACHA20 y
        CRYPTO_CHACHA20_X86_64 y
        CRYPTO_POLY1305 y
        CRYPTO_POLY1305_X86_64 y
        CRYPTO_NHPOLY1305 y
        CRYPTO_NHPOLY1305_SSE2 y
        CRYPTO_AES y
        CRYPTO_AES_X86_64 y
        CRYPTO_LIB_AES y
        CRYPTO_LIB_CHACHA y
        CRYPTO_LIB_POLY1305 y
        CRYPTO_SIMD y
        CRYPTO_CRYPTD y
        CRYPTO_MANAGER y
        CRYPTO_USER_API_SKCIPHER y
        CRYPTO_HMAC y
        CRYPTO_SHA256 y
      '';
    }
  ];
}