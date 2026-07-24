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

  # Hetzner Cloud / Robot: DHCP on any ethernet; avoid missing the NIC after install
  networking.usePredictableInterfaceNames = false; # keep eth0 like rescue
  networking.useDHCP = false;
  networking.interfaces.eth0.useDHCP = true;
  # Hetzner Cloud often needs this gateway for /32 assignments if DHCP is thin
  # (harmless if DHCP already provides a route)
  networking.defaultGateway = lib.mkDefault {
    address = "172.31.1.1";
    interface = "eth0";
  };
  networking.nameservers = lib.mkDefault [
    "185.12.64.1"
    "185.12.64.2"
  ];

  systemd.network.enable = true;
  systemd.network.networks."10-eth0" = {
    matchConfig.Name = "eth0";
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
    };
    linkConfig.RequiredForOnline = "routable";
  };

  # Hetzner Cloud CX* is usually /dev/sda
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
