# mothership git sync — path-aware pull + nixos-rebuild (systemd timer = cron)
#
# enable on the metal only. watches origin/main, classifies diffs:
#   user-vms only  → member switch (host must activate units; peers should stay up)
#   host fabric    → full switch
#   edge/sites/... → pull, no rebuild
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mothership.gitSync;
  syncBin = pkgs.writeShellScriptBin "mothership-git-sync" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.git
        pkgs.util-linux
        pkgs.gawk
        pkgs.gnugrep
        pkgs.nix
        pkgs.nixos-rebuild
        pkgs.systemd
      ]
    }:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
    exec ${pkgs.bash}/bin/bash ${../scripts/mothership-git-sync} "$@"
  '';
in
{
  options.mothership.gitSync = {
    enable = lib.mkEnableOption "path-aware git pull + activate on a timer";

    remote = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/tinkerhub0/mothership.git";
      description = "git remote (public https or ssh)";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
    };

    srcDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mothership/src";
      description = "working tree the timer pulls into";
    };

    flakeHost = lib.mkOption {
      type = lib.types.str;
      default = "mothership";
      description = "nixosConfigurations.<name> for nixos-rebuild";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "2min";
      description = "systemd OnUnitActiveSec after each run finishes";
    };

    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "30s";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      syncBin
      pkgs.git
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/mothership 0755 root root -"
      "d /var/lib/mothership/git-sync 0755 root root -"
    ];

    systemd.services.mothership-git-sync = {
      description = "mothership path-aware git sync + activate";
      after = [
        "network-online.target"
        "nix-daemon.service"
      ];
      wants = [ "network-online.target" ];
      # packages (not raw strings) so nixos wires bin/ correctly
      path = with pkgs; [
        bash
        coreutils
        git
        util-linux
        gawk
        gnugrep
        nix
        nixos-rebuild
        systemd
      ];
      environment = {
        MOTHERSHIP_SRC = cfg.srcDir;
        MOTHERSHIP_REMOTE = cfg.remote;
        MOTHERSHIP_BRANCH = cfg.branch;
        MOTHERSHIP_FLAKE = cfg.flakeHost;
        NIX_CONFIG = "experimental-features = nix-command flakes";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${syncBin}/bin/mothership-git-sync";
        TimeoutStartSec = "2h";
        Nice = 10;
        # never take down the host activation if a sync is mid-flight
        RemainAfterExit = false;
      };
      # do not block boot/switch; timer invokes later
      unitConfig = {
        RefuseManualStart = false;
      };
    };

    systemd.timers.mothership-git-sync = {
      description = "mothership git sync timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # first run a few minutes after boot; then every interval after each finish
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.interval;
        RandomizedDelaySec = cfg.randomizedDelaySec;
        # avoid instant catch-up when the unit is first enabled on a long-uptime box
        Persistent = false;
        Unit = "mothership-git-sync.service";
      };
    };

    environment.etc."mothership/git-sync.txt".text = ''
      mothership git sync: on
      remote:   ${cfg.remote}
      branch:   ${cfg.branch}
      src:      ${cfg.srcDir}
      flake:    .#${cfg.flakeHost}
      interval: ${cfg.interval}

      member PR (user-vms only) → switch host, start microvm@you, peers stay up
      fabric PR (modules/hosts/lib/flake) → full switch
      edge/site only → pull, no mothership rebuild

      journal: journalctl -u mothership-git-sync -f
      manual:  mothership-git-sync
      dry-run: MOTHERSHIP_DRY_RUN=1 mothership-git-sync
    '';
  };
}
