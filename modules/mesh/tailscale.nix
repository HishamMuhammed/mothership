# tailscale client — joins Headscale via public serverUrl (edge front door).
# control plane host also uses serverUrl so traffic goes edge→WG→local Headscale
# (Headscale may bind tunnel IP only, not 127.0.0.1).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mothership.mesh;
  # always public front door URL so every node uses the same coordination path
  loginServer = cfg.serverUrl;
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

    environment.systemPackages = [ pkgs.tailscale ];

    environment.etc."mothership/mesh-bootstrap.md".text = ''
      # mesh bootstrap (Headscale on mothership, public front door on edge)
      public login-server: ${cfg.serverUrl}
      MagicDNS base: ${cfg.baseDomain}

      ## 0. WireGuard front door keys
      scripts/install-wg-front-keys
      # edge + mothership must show: wg show wg-front

      ## 1. on mothership (control plane)
      sudo -u headscale headscale users create tinkerhub
      sudo -u headscale headscale users list
      KEY=$(sudo -u headscale headscale preauthkeys create -u 1 --reusable --expiration 168h)
      echo "$KEY"
      sudo tailscale up --login-server=${cfg.serverUrl} --authkey="$KEY" --hostname=mothership --reset

      ## 2. on edge / laptops
      sudo tailscale up --login-server=${cfg.serverUrl} --authkey="$KEY" --hostname=<name> --reset
    '';
  };
}
