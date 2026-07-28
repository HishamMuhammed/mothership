# public landa.tharavad.xyz → local landa-api (control plane)
# API code lives in /var/lib/landa (see landa repo deploy); this module
# fronts it with nginx and keeps a durable systemd unit + landa system user.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mothership.landaProxy;
  landaUid = 995;
in
{
  options.mothership.landaProxy = {
    enable = lib.mkEnableOption "nginx reverse proxy for landa API";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "landa.tharavad.xyz";
    };

    upstream = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8787";
      description = "landa-api listen address on this host";
    };

    manageService = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install durable landa-api.service (needs /var/lib/landa checkout)";
    };
  };

  config = lib.mkIf cfg.enable {
    # uid must match existing /var/lib/landa/.data ownership on edge
    users.groups.landa = { };
    users.users.landa = {
      isSystemUser = true;
      uid = landaUid;
      group = "landa";
      home = "/var/lib/landa-home";
      createHome = true;
      description = "landa postgres + control plane";
    };

    services.nginx = {
      enable = true;
      virtualHosts."${cfg.domain}" = {
        locations."/" = {
          proxyPass = cfg.upstream;
          extraConfig = ''
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 300s;
          '';
        };
        extraConfig = ''
          add_header X-Content-Type-Options nosniff always;
        '';
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 ];

    # durable unit (survives reboot; /run units do not)
    systemd.services.landa-api = lib.mkIf cfg.manageService {
      description = "landa control plane API";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # only start when deploy checkout exists
      unitConfig.ConditionPathExists = "/var/lib/landa/package.json";
      path = [
        pkgs.bash
        pkgs.nix
        pkgs.coreutils
      ];
      environment = {
        NODE_ENV = "production";
        LANDA_ROOT = "/var/lib/landa";
        LANDA_DATA = "/var/lib/landa/.data";
        PGDATA = "/var/lib/landa/.data/pg";
        PGHOST = "127.0.0.1";
        PGPORT = "5433";
        PGUSER = "landa";
        PGPASSWORD = "landa";
        PGDATABASE = "landa";
        DATABASE_URL = "postgres://landa:landa@127.0.0.1:5433/landa";
        LANDA_API_HOST = "127.0.0.1";
        LANDA_API_PORT = "8787";
        PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/var/lib/landa/node_modules/.bin";
      };
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/var/lib/landa";
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'cd /var/lib/landa && nix --extra-experimental-features \"nix-command flakes\" develop -c landa-pg start'";
        ExecStart = "${pkgs.bash}/bin/bash -c 'cd /var/lib/landa && exec nix --extra-experimental-features \"nix-command flakes\" develop -c npm run api'";
        Restart = "on-failure";
        RestartSec = "5";
      };
    };

    environment.etc."mothership/landa-proxy.txt".text = ''
      landa:    http://${cfg.domain}/
      upstream: ${cfg.upstream}
      health:   http://${cfg.domain}/health
    '';
  };
}
