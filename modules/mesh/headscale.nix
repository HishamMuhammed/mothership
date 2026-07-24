# headscale — coordination server (control plane).
# run on edge (VPS). mothership is a node, not the control plane.
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

    # true on edge VPS; false on mothership metal
    controlPlane = lib.mkEnableOption "run Headscale on this host";

    baseDomain = lib.mkOption {
      type = lib.types.str;
      default = "mesh.tinkerhub";
      description = "MagicDNS base. Nodes become <hostname>.<baseDomain>.";
    };

    mothershipIPv4 = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.1";
      description = "Reserved mesh IPv4 for the control-plane node (edge).";
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
      description = "Public Headscale URL (VPS static IP). Clients use as --login-server.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.controlPlane) {
    services.headscale = {
      enable = true;
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

    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];
      allowedTCPPorts = [ cfg.listenPort ];
      allowedUDPPorts = [ config.services.tailscale.port ];
      checkReversePath = "loose";
    };

    environment.systemPackages = [ hs.package ];
  };
}
