# headscale — coordination server (control plane).
# lives on mothership; public clients reach it via edge front door (WG + nginx).
{
  config,
  lib,
  ...
}:
let
  cfg = config.mothership.mesh;
  hs = config.services.headscale;
in
{
  options.mothership.mesh = {
    enable = lib.mkEnableOption "mesh stack options (headscale and/or tailscale)";

    # true on mothership; false on edge (edge is proxy-only front door)
    controlPlane = lib.mkEnableOption "run Headscale on this host";

    baseDomain = lib.mkOption {
      type = lib.types.str;
      # → ssh alvin@alvin.mothership  (and short name: ssh alvin@alvin via search domain)
      default = "mothership";
      description = "MagicDNS base. Nodes become <hostname>.<baseDomain> (e.g. alvin.mothership).";
    };

    mothershipIPv4 = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.1";
      description = "Preferred mesh IPv4 for DNS records (usually first joined node / mothership).";
    };

    prefixV4 = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.0/10";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
    };

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://178.105.120.5:8080";
      description = "Public Headscale URL clients use as --login-server (edge front door).";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.controlPlane) {
    services.headscale = {
      enable = true;
      # all interfaces; public exposure blocked by firewall (only wg-front allows 8080)
      address = "0.0.0.0";
      port = cfg.listenPort;

      settings = {
        server_url = cfg.serverUrl;

        prefixes = {
          v4 = cfg.prefixV4;
          v6 = "fd7a:115c:a1e0::/48";
          allocation = "sequential";
        };

        dns = {
          magic_dns = true;
          base_domain = cfg.baseDomain;
          override_local_dns = true;
          nameservers.global = [
            "1.1.1.1"
            "9.9.9.9"
          ];
          search_domains = [ cfg.baseDomain ];
          extra_records = [
            {
              name = "headscale.${cfg.baseDomain}";
              type = "A";
              value = cfg.mothershipIPv4;
            }
          ];
        };

        log.level = "info";

        policy = {
          mode = "file";
          path = ./policy.hujson;
        };
      };
    };

    # do NOT open listenPort on the public firewall — only via wg-front (front-door.nix)
    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [ config.services.tailscale.port ];
      checkReversePath = "loose";
    };

    environment.systemPackages = [ hs.package ];
  };
}
