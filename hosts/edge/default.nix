# hosts/edge — public control plane (VPS @ 178.105.120.5).
# static public IP. Headscale lives here. mothership joins as a node.
#
#   ssh nixos@178.105.120.5
#   sudo nixos-rebuild switch --flake .#edge
{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/admins.nix
    ../../modules/tools.nix
    ../../modules/mesh/headscale.nix
    ../../modules/mesh/tailscale.nix
  ];

  networking.hostName = "edge";
  networking.hostId = "e5a1c0de";
  networking.useDHCP = lib.mkDefault true;

  # cloud VPS: grub is common; pin device after hardware-configuration is real
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

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
