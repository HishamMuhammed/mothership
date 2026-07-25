# Hetzner Cloud / KVM guest — initrd must see the virtio disk or boot dies with:
#   Timed out waiting for device /dev/disk/by-partlabel/disk-main-root
# fileSystems come from disko.nix (by-partlabel), not from here.
{
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_blk" # Hetzner Cloud root is almost always virtio-blk
    "virtio_scsi"
    "virtio_net"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
