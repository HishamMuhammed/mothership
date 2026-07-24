# edge VPS — single disk, ESP + ext4 root (no ZFS; keep the control plane dumb).
# override device if the provider uses nvme0n1 / vda:
#   mothership.edge.diskDevice in default.nix
{
  config,
  lib,
  ...
}:
let
  disk = config.mothership.edge.diskDevice or "/dev/sda";
in
{
  options.mothership.edge.diskDevice = lib.mkOption {
    type = lib.types.str;
    default = "/dev/sda";
    description = "Block device for the VPS system disk (lsblk on Ubuntu first).";
  };

  config.disko.devices = {
    disk.main = {
      type = "disk";
      device = disk;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
