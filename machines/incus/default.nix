{
  lib,
  ...
}:

{
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  boot.kernelParams = [
    "pcie_aspm=force"
    "pcie_aspm.policy=powersave"
  ];
}
