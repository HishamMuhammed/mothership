# hosts/edge — public control plane (VPS @ 178.105.120.5).
# install: Ubuntu (or any SSH Linux) → nixos-anywhere --flake .#edge
# day-2:  sudo nixos-rebuild switch --flake .#edge
{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./disko.nix
    ../../modules/base.nix
    ../../modules/admins.nix
    ../../modules/tools.nix
    ../../modules/mesh/headscale.nix
    ../../modules/mesh/tailscale.nix
  ];

  networking.hostName = "edge";
  networking.hostId = "e5a1c0de";
  networking.useDHCP = lib.mkDefault true;

  # Hetzner Cloud CX* is usually /dev/sda; check with lsblk on Ubuntu first
  mothership.edge.diskDevice = "/dev/sda";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.enable = lib.mkForce false;

  mothership.mesh = {
    enable = true;
    controlPlane = true;
    baseDomain = "mesh.tinkerhub";
    mothershipIPv4 = "100.64.0.1";
    serverUrl = "http://178.105.120.5:8080";
  };

  networking.firewall.allowedTCPPorts = [
    22
    8080
  ];
  networking.firewall.allowedUDPPorts = [ 41641 ];

  environment.systemPackages = with pkgs; [
    git
    curl
    jq
  ];

  system.stateVersion = "26.05";
}
