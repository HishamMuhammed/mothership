# public landing at tharavad.xyz (Astro static site)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mothership.landing;
  site = pkgs.callPackage ../sites/tharavad/package.nix { };
in
{
  options.mothership.landing = {
    enable = lib.mkEnableOption "serve tharavad.xyz Astro landing on this host";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "tharavad.xyz";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx = {
      enable = true;
      virtualHosts."${cfg.domain}" = {
        # apex only — member subdomains stay on member-publish vhosts
        serverAliases = [ "www.${cfg.domain}" ];
        root = "${site}";
        locations."/" = {
          tryFiles = "$uri $uri/index.html $uri/ =404";
          extraConfig = ''
            index index.html;
          '';
        };
        extraConfig = ''
          add_header X-Content-Type-Options nosniff always;
          add_header Referrer-Policy no-referrer-when-downgrade always;
        '';
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 ];

    environment.etc."mothership/landing.txt".text = ''
      landing: https://${cfg.domain}/
      root:    ${site}
      source:  sites/tharavad (Astro)
    '';
  };
}
