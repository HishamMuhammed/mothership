# operators who can SSH metal / edge and rebuild.
# members live in user-vms/ — not here.
{ lib, ... }:
let
  adminKeys = import ../lib/adminKeys.nix;
in
{
  users.users.root.openssh.authorizedKeys.keys = adminKeys;

  users.users.mothership = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = adminKeys;
  };

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = adminKeys;
  };

  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [
    "root"
    "@wheel"
    "mothership"
    "nixos"
  ];
}
