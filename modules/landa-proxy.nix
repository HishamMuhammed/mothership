# landa public edge:
#   landa.tharavad.xyz      → static console (webRoot)
#   landa-back.tharavad.xyz → usually memberPublish → alvin:8787 (not local)
# Optional local API unit if manageService + apiDomain set with local upstream.
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
    enable = lib.mkEnableOption "nginx landa console (+ optional local API)";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "landa.tharavad.xyz";
      description = "static UI host";
    };

    apiDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "If set, nginx vhost for API on this host (else use memberPublish)";
    };

    upstream = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:8787";
      description = "landa-api when apiDomain is local";
    };

    webRoot = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/landa/web/dist";
      description = "built Vite console (index.html + assets)";
    };

    # same-origin proxy so Better Auth cookies work without HTTPS
    apiProxy = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "http://10.99.0.2:9080";
      description = "upstream for /v1 /api/auth /health (mothership publish router)";
    };

    apiProxyHost = lib.mkOption {
      type = lib.types.str;
      default = "landa-back.tharavad.xyz";
      description = "Host header for apiProxy (memberPublish virtual host)";
    };

    manageService = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install local landa-api.service on this host";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.landa = lib.mkIf cfg.manageService { };
    users.users.landa = lib.mkIf cfg.manageService {
      isSystemUser = true;
      uid = landaUid;
      group = "landa";
      home = "/var/lib/landa-home";
      createHome = true;
      description = "landa postgres + control plane";
    };

    services.nginx = {
      enable = true;
      virtualHosts =
        {
          "${cfg.domain}" = {
            forceSSL = true;
            enableACME = true;
            root = cfg.webRoot;
            locations =
              {
                "/" = {
                  tryFiles = "$uri $uri/ /index.html";
                };
              }
              // lib.optionalAttrs (cfg.apiProxy != null) {
                "/v1/" = {
                  proxyPass = cfg.apiProxy;
                  recommendedProxySettings = false;
                  extraConfig = ''
                    proxy_http_version 1.1;
                    proxy_set_header Host ${cfg.apiProxyHost};
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header Cookie $http_cookie;
                    proxy_pass_header Set-Cookie;
                    proxy_read_timeout 300s;
                  '';
                };
                "/api/" = {
                  proxyPass = cfg.apiProxy;
                  recommendedProxySettings = false;
                  extraConfig = ''
                    proxy_http_version 1.1;
                    proxy_set_header Host ${cfg.apiProxyHost};
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header Cookie $http_cookie;
                    proxy_pass_header Set-Cookie;
                    proxy_read_timeout 300s;
                  '';
                };
                "/health" = {
                  proxyPass = "${cfg.apiProxy}/health";
                  recommendedProxySettings = false;
                  extraConfig = ''
                    proxy_http_version 1.1;
                    proxy_set_header Host ${cfg.apiProxyHost};
                  '';
                };
              };
            extraConfig = ''
              add_header X-Content-Type-Options nosniff always;
              add_header X-Frame-Options DENY always;
            '';
          };
        }
        // lib.optionalAttrs (cfg.apiDomain != null) {
          "${cfg.apiDomain}" = {
            forceSSL = true;
            enableACME = true;
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
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    systemd.services.landa-api = lib.mkIf cfg.manageService {
      description = "landa control plane API";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
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
        LANDA_CORS_ORIGIN = "*";
      };
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/var/lib/landa";
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'export PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/var/lib/landa/node_modules/.bin:$PATH; cd /var/lib/landa && nix --extra-experimental-features \"nix-command flakes\" develop -c landa-pg start'";
        ExecStart = "${pkgs.bash}/bin/bash -c 'export PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/var/lib/landa/node_modules/.bin:$PATH; cd /var/lib/landa && exec nix --extra-experimental-features \"nix-command flakes\" develop -c npm run api'";
        Restart = "on-failure";
        RestartSec = "5";
      };
    };

    environment.etc."mothership/landa-proxy.txt".text = ''
      ui:      https://${cfg.domain}/
      webRoot: ${cfg.webRoot}
      api:     ${
        if cfg.apiDomain != null then "https://${cfg.apiDomain}/ (local upstream ${cfg.upstream})" else "memberPublish → landa-back (alvin:8787)"
      }
      TLS:     ACME (enableACME + forceSSL)
    '';
  };
}

