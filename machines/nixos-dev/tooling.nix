{ config, pkgs, ... }:
let
  kernelVersion = config.boot.kernelPackages.kernel.modDirVersion;
  kernelDevPath = "${config.boot.kernelPackages.kernel.dev}/lib/modules/${kernelVersion}/build";
in
{
  environment.systemPackages =
    with pkgs;
    [
      bc
      binutils
      bison
      cargo
      clang
      clippy
      cpio
      curl
      elfutils
      fd
      file
      flex
      gdb
      git
      gnumake
      jq
      kmod
      lld
      linuxHeaders
      llvm
      mold
      openssl
      pahole
      pciutils
      perl
      pkg-config
      python3
      ripgrep
      rust-analyzer
      rustc
      rustfmt
      strace
      unzip
      usbutils
      wget
      zstd
      config.boot.kernelPackages.kernel.dev
    ];

  environment.variables = {
    KERNEL_BUILD_DIR = kernelDevPath;
    KERNEL_RELEASE = kernelVersion;
  };

  environment.etc."kernel-build-path".text = "${kernelDevPath}\n";
}
