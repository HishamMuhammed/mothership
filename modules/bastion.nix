# public SSH bastion — Railway-style member access.
#
#   member:  ssh you@you.<publicDomain>
#            (no mesh, no Headscale, no Tailscale)
#
#   path:    internet → edge:22 (your key) → WG → mothership → VM (bastion key)
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
    "nobody"
    "sshd"
  ];

  jumpScript = pkgs.writeShellScript "bastion-jump" ''
    set -euo pipefail
    KEY="${cfg.privateKeyFile}"
    JUMP="${cfg.jumpHost}"
    if [ ! -r "$KEY" ]; then
      echo "bastion key missing on edge — operator: scripts/install-bastion-key" >&2
      exit 1
    fi
    # shell USER = member account (e.g. alvin) → VM hostname + login
    # internal hop only (WG + mesh). ProxyCommand so jump host also skips host keys.
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
in
{
  options.mothership.bastion = {
    enable = lib.mkEnableOption "public SSH bastion (edge): ssh you@you.domain → member VM";

    # also trust bastion key on this host (mothership root for ProxyJump)
    trustBastionKey = lib.mkEnableOption "authorize bastion pubkey for root (jump hop)";

    publicDomain = lib.mkOption {
      type = lib.types.str;
      # free wildcard DNS → edge IP; replace with real domain later
      default = "tharavad.xyz";
      description = ''
        DNS suffix for members. you.<publicDomain> must A/AAAA to edge.
        Zone already has wildcard * → edge (178.105.120.5).
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
      description = "Bastion public key injected into member VMs + mothership root.";
    };
  };

  config = lib.mkMerge [
    # ── mothership: accept bastion as jump user (root) ──────────────────
    (lib.mkIf cfg.trustBastionKey {
      users.users.root.openssh.authorizedKeys.keys = lib.mkAfter [ cfg.publicKey ];
    })

    # ── edge: member accounts + ForceCommand jump ───────────────────────
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
        # private key must be group-readable (ForceCommand runs as member user)
        "z ${cfg.privateKeyFile} 0440 root bastion -"
      ];

      # one Unix user per member — keys from git; session becomes VM shell
      users.users = lib.mapAttrs (
        name: m: {
          isNormalUser = true;
          description = "bastion → microVM ${name}";
          extraGroups = [ "bastion" ];
          # no password — ForceCommand always jumps to VM
          openssh.authorizedKeys.keys = m.keys;
        }
      ) enabledMembers;

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = lib.mkDefault "prohibit-password";
        };
        # Match all non-operator users
        extraConfig = ''
          Match User *,!root,!nixos,!mothership
            ForceCommand ${jumpScript}
            AllowTcpForwarding no
            X11Forwarding no
            PermitTunnel no
            AllowAgentForwarding no
        '';
      };

      environment.etc."mothership/bastion.txt".text = ''
        public SSH bastion (Railway-style)
        ==================================
        member UX (no mesh client):

          ssh <name>@<name>.${cfg.publicDomain}

        example:

          ssh alvin@alvin.${cfg.publicDomain}

        path:  you → edge:22 (your PR key) → WG → mothership → VM
        mesh / Headscale: operators + VMs only (invisible to members)

        DNS: *.${cfg.publicDomain} → edge public IP
        (sslip.io default needs no registrar; swap publicDomain when you have a real zone)

        operator:
          scripts/install-bastion-key
          rebuild edge + mothership
      '';

      environment.systemPackages = [ pkgs.openssh ];
    })
  ];
}
