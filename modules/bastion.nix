# public SSH bastion — members + operator host selectors.
#
#   member:    ssh you@you.<publicDomain>  → microVM (via mothership)
#   operator:  ssh mothership@<publicDomain> → mothership metal (WG)
#              ssh edge@<publicDomain>       → edge local shell
#
#   path (member):
#     internet → edge:22 (member key) → WG → mothership → VM (bastion key)
#
# Headscale stays internal (unique private IPs between VMs/admins).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mothership.bastion;
  bastionPub = import ../lib/bastionPubKey.nix;
  adminKeys = import ../lib/adminKeys.nix;

  memberDir = ../user-vms;
  dirEntries = if builtins.pathExists memberDir then builtins.readDir memberDir else { };
  memberFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "template.nix"
  ) dirEntries;
  rawMembers = lib.mapAttrs' (
    file: _:
    let
      name = lib.removeSuffix ".nix" file;
    in
    {
      inherit name;
      value = import (memberDir + "/${file}");
    }
  ) memberFiles;
  enabledMembers = lib.filterAttrs (_n: m: (m.enabled or true) && ((m.keys or [ ]) != [ ])) rawMembers;

  reserved = [
    "root"
    "nixos"
    "mothership"
    "edge"
    "nobody"
    "sshd"
  ];

  # member: you@you → microVM via mothership ProxyJump
  memberJump = pkgs.writeShellScript "bastion-jump-member" ''
    set -euo pipefail
    KEY="${cfg.privateKeyFile}"
    JUMP="${cfg.jumpHost}"
    if [ ! -r "$KEY" ]; then
      echo "bastion key missing on edge — operator: scripts/install-bastion-key" >&2
      exit 1
    fi
    # shell USER = member account (e.g. alvin) → VM hostname + login
    exec ${pkgs.openssh}/bin/ssh -tt \
      -i "$KEY" \
      -o IdentitiesOnly=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o GlobalKnownHostsFile=/dev/null \
      -o ProxyCommand="${pkgs.openssh}/bin/ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -W %h:%p root@''${JUMP}" \
      -o LogLevel=ERROR \
      "''${USER}@''${USER}"
  '';

  # operator: mothership@tharavad.xyz → mothership metal over WG
  metalJump = pkgs.writeShellScript "bastion-jump-mothership" ''
    set -euo pipefail
    KEY="${cfg.privateKeyFile}"
    JUMP="${cfg.jumpHost}"
    if [ ! -r "$KEY" ]; then
      echo "bastion key missing on edge — operator: scripts/install-bastion-key" >&2
      exit 1
    fi
    ssh_base=(
      ${pkgs.openssh}/bin/ssh
      -i "$KEY"
      -o IdentitiesOnly=yes
      -o StrictHostKeyChecking=no
      -o UserKnownHostsFile=/dev/null
      -o GlobalKnownHostsFile=/dev/null
      -o LogLevel=ERROR
    )
    # interactive login vs remote command (ForceCommand swallows argv; use SSH_ORIGINAL_COMMAND)
    if [ -n "''${SSH_ORIGINAL_COMMAND:-}" ]; then
      exec "''${ssh_base[@]}" mothership@"''${JUMP}" "''${SSH_ORIGINAL_COMMAND}"
    else
      exec "''${ssh_base[@]}" -tt mothership@"''${JUMP}"
    fi
  '';
in
{
  options.mothership.bastion = {
    enable = lib.mkEnableOption "public SSH bastion (edge): members + mothership@ / edge@ operators";

    # also trust bastion key on this host (mothership root + mothership user for hop)
    trustBastionKey = lib.mkEnableOption "authorize bastion pubkey for root + mothership (jump hop)";

    publicDomain = lib.mkOption {
      type = lib.types.str;
      default = "tharavad.xyz";
      description = ''
        DNS suffix. Apex and *.publicDomain A/AAAA → edge.
      '';
    };

    jumpHost = lib.mkOption {
      type = lib.types.str;
      default = "10.99.0.2";
      description = "mothership address from edge (WG tunnel IP).";
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/mothership/bastion/id_ed25519";
    };

    publicKey = lib.mkOption {
      type = lib.types.str;
      default = bastionPub;
      description = "Bastion public key injected into member VMs + mothership hop accounts.";
    };
  };

  config = lib.mkMerge [
    # ── mothership: accept bastion for ProxyJump + mothership@ hop ──────
    (lib.mkIf cfg.trustBastionKey {
      users.users.root.openssh.authorizedKeys.keys = lib.mkAfter [ cfg.publicKey ];
      users.users.mothership.openssh.authorizedKeys.keys = lib.mkAfter [ cfg.publicKey ];
    })

    # ── edge: members + operator selectors ──────────────────────────────
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = lib.all (n: !(lib.elem n reserved)) (lib.attrNames enabledMembers);
          message = "bastion: member name collides with reserved system user";
        }
      ];

      users.groups.bastion = { };

      systemd.tmpfiles.rules = [
        "d /var/lib/mothership/bastion 0750 root bastion -"
        # private key must be group-readable (ForceCommand runs as member/operator user)
        "z ${cfg.privateKeyFile} 0440 root bastion -"
      ];

      # members + edge@ + mothership@ group tweak (single users.users attr)
      users.users =
        (lib.mapAttrs (
          name: m: {
            isNormalUser = true;
            description = "bastion → microVM ${name}";
            extraGroups = [ "bastion" ];
            openssh.authorizedKeys.keys = m.keys;
          }
        ) enabledMembers)
        // {
          # mothership@ on edge: bastion group so ForceCommand can read hop key
          mothership.extraGroups = lib.mkAfter [ "bastion" ];
          # edge@tharavad.xyz → local shell on edge (admin keys)
          edge = {
            isNormalUser = true;
            description = "operator shell on edge";
            extraGroups = [
              "wheel"
              "bastion"
            ];
            openssh.authorizedKeys.keys = adminKeys;
          };
        };

      security.sudo.wheelNeedsPassword = false;
      nix.settings.trusted-users = lib.mkAfter [
        "edge"
        "mothership"
      ];

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = lib.mkDefault "prohibit-password";
        };
        extraConfig = ''
          # operator → mothership metal over WG
          Match User mothership
            ForceCommand ${metalJump}
            AllowTcpForwarding no
            X11Forwarding no
            PermitTunnel no
            AllowAgentForwarding no

          # members → their microVM (exclude operators)
          Match User *,!root,!nixos,!mothership,!edge
            ForceCommand ${memberJump}
            AllowTcpForwarding no
            X11Forwarding no
            PermitTunnel no
            AllowAgentForwarding no
        '';
      };

      environment.etc."mothership/bastion.txt".text = ''
        public SSH bastion
        ==================
        member (no mesh client):

          ssh <name>@<name>.${cfg.publicDomain}
          e.g. ssh alvin@alvin.${cfg.publicDomain}

        operator (admin keys from lib/adminKeys.nix):

          ssh mothership@${cfg.publicDomain}   → mothership metal (WG ${cfg.jumpHost})
          ssh edge@${cfg.publicDomain}         → edge local shell
          ssh root@${cfg.publicDomain}         → edge as root

        path (member): you → edge:22 → WG → mothership → VM
        path (mothership@): you → edge:22 → WG → mothership shell
        path (edge@): you → edge:22 → local shell

        DNS: apex + *.${cfg.publicDomain} → edge public IP

        operator bootstrap:
          scripts/install-bastion-key
          rebuild edge + mothership
      '';

      environment.systemPackages = [ pkgs.openssh ];
    })
  ];
}
