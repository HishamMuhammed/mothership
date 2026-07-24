# tailscale client — joins Headscale (local on edge, remote URL on mothership).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mothership.mesh;
  loginServer =
    if cfg.controlPlane then
      "http://127.0.0.1:${toString cfg.listenPort}"
    else
      cfg.serverUrl;
in
{
  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "server";
      extraUpFlags = [
        "--login-server=${loginServer}"
        "--hostname=${config.networking.hostName}"
        "--accept-dns=true"
      ];
    };

    # serve only on control plane after join; soft-fail before join
    systemd.services.tailscale-serve-headscale = lib.mkIf cfg.controlPlane {
      description = "tailscale serve → local Headscale (after mesh join)";
      after = [
        "tailscaled.service"
        "headscale.service"
        "network-online.target"
      ];
      wants = [
        "tailscaled.service"
        "headscale.service"
        "network-online.target"
      ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.tailscale
        pkgs.coreutils
        pkgs.gnugrep
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        SuccessExitStatus = "0 1";
        ExecStart = pkgs.writeShellScript "tailscale-serve-headscale" ''
          set -u
          for i in $(seq 1 30); do
            if tailscale status --json 2>/dev/null | grep -q '"BackendState": "Running"'; then
              tailscale serve reset || true
              tailscale serve --bg --https=443 http://127.0.0.1:${toString cfg.listenPort} && exit 0
              exit 0
            fi
            sleep 1
          done
          echo "tailscale not joined yet — skip serve"
          exit 0
        '';
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve reset";
      };
    };

    environment.systemPackages = [ pkgs.tailscale ];

    environment.etc."mothership/mesh-bootstrap.md".text = ''
      # mesh bootstrap
      control plane (edge): ${cfg.serverUrl}
      MagicDNS base: ${cfg.baseDomain}

      ## on edge (first)
      sudo -u headscale headscale users create tinkerhub
      sudo -u headscale headscale users list
      KEY=$(sudo -u headscale headscale preauthkeys create -u 1 --reusable --expiration 168h)
      sudo tailscale up --login-server=http://127.0.0.1:${toString cfg.listenPort} --authkey="$KEY" --hostname=edge --reset

      ## on mothership / laptops
      sudo tailscale up --login-server=${cfg.serverUrl} --authkey="$KEY" --hostname=<name> --reset
      # ssh mothership@mothership   # after MagicDNS
      # ssh alvin@alvin             # member VM
    '';
  };
}
