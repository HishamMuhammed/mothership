# public landa.tharavad.xyz → local landa-api (control plane)
# API itself is not in this flake — lives in /var/lib/landa (see landa repo deploy)
{
  config,
  lib,
  ...
}:
let
  cfg = config.mothership.landaProxy;
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
  };

  config = lib.mkIf cfg.enable {
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

    environment.etc."mothership/landa-proxy.txt".text = ''
      landa:    http://${cfg.domain}/
      upstream: ${cfg.upstream}
      health:   http://${cfg.domain}/health
    '';
  };
}
