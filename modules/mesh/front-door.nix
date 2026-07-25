# front door — WireGuard reverse tunnel + public reverse-proxy.
#
#   internet ──:8080──► edge (nginx) ──10.99.0.0/24 WG──► mothership Headscale
#                         ▲
#                         │ mothership initiates WG (PersistentKeepalive)
#
# edge:    role = "edge"        (WG listen + nginx)
# mothership: role = "home"     (WG client only)
#
# private keys live on disk (not in the nix store):
#   /var/lib/mothership/wg-front/private.key
# install from secrets/wg-front/*.priv via scripts/install-wg-front-keys
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mothership.mesh.frontDoor;
  mesh = config.mothership.mesh;
  isEdge = cfg.enable && cfg.role == "edge";
  isHome = cfg.enable && cfg.role == "home";
in
{
  options.mothership.mesh.frontDoor = {
    enable = lib.mkEnableOption "WireGuard reverse tunnel front door (edge ↔ mothership)";

    role = lib.mkOption {
      type = lib.types.enum [
        "edge"
        "home"
      ];
      description = "edge = public WG server + reverse proxy; home = WG client that dials out.";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "wg-front";
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 51820;
      description = "UDP port edge listens on (public).";
    };

    edgeTunnelIP = lib.mkOption {
      type = lib.types.str;
      default = "10.99.0.1";
    };

    homeTunnelIP = lib.mkOption {
      type = lib.types.str;
      default = "10.99.0.2";
    };

    # public keys are not secret — safe in git
    edgePublicKey = lib.mkOption {
      type = lib.types.str;
      description = "WireGuard public key of edge.";
    };

    homePublicKey = lib.mkOption {
      type = lib.types.str;
      description = "WireGuard public key of mothership.";
    };

    edgeEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "178.105.120.5:51820";
      description = "host:port mothership dials (edge public IP + listenPort).";
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/mothership/wg-front/private.key";
      description = "Path to this host's WireGuard private key (mode 0400). Not in git.";
    };

    proxyPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Public TCP port on edge that reverse-proxies to home Headscale.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # ── shared: interface + key path hygiene ──────────────────────────
      {
        networking.wireguard.enable = true;

        # soft-fail unit until key is installed (switch must not brick)
        systemd.tmpfiles.rules = [
          "d /var/lib/mothership/wg-front 0700 root root -"
        ];

        environment.systemPackages = with pkgs; [
          wireguard-tools
        ];

        environment.etc."mothership/wg-front.txt".text = ''
          WireGuard front door (${cfg.role})
          iface:     ${cfg.interface}
          key file:  ${cfg.privateKeyFile}
          tunnel:    edge ${cfg.edgeTunnelIP} ↔ home ${cfg.homeTunnelIP}
          endpoint:  ${cfg.edgeEndpoint}
          public:    ${mesh.serverUrl}  (edge nginx → home Headscale)

          install key (from laptop secrets/wg-front/):
            scripts/install-wg-front-keys
          then:
            sudo systemctl restart wireguard-${cfg.interface}.service
        '';
      }

      # ── edge: listen + nginx reverse proxy ────────────────────────────
      (lib.mkIf isEdge {
        networking.wireguard.interfaces.${cfg.interface} = {
          ips = [ "${cfg.edgeTunnelIP}/24" ];
          listenPort = cfg.listenPort;
          privateKeyFile = cfg.privateKeyFile;
          peers = [
            {
              name = "mothership";
              publicKey = cfg.homePublicKey;
              allowedIPs = [ "${cfg.homeTunnelIP}/32" ];
              # home dials us; no endpoint here
            }
          ];
        };

        # public: headscale clients + WG
        networking.firewall.allowedUDPPorts = [ cfg.listenPort ];
        networking.firewall.allowedTCPPorts = [ cfg.proxyPort ];
        networking.firewall.trustedInterfaces = [ cfg.interface ];
        networking.firewall.checkReversePath = "loose";

        services.nginx = {
          enable = true;
          recommendedProxySettings = true;
          recommendedOptimisation = true;
          # single purpose: front door for Headscale HTTP API
          virtualHosts."headscale-front-door" = {
            listen = [
              {
                addr = "0.0.0.0";
                port = cfg.proxyPort;
              }
            ];
            locations."/" = {
              proxyPass = "http://${cfg.homeTunnelIP}:${toString mesh.listenPort}";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_connect_timeout 10s;
                proxy_read_timeout 3600s;
                proxy_send_timeout 3600s;
                proxy_buffering off;
                proxy_request_buffering off;
              '';
            };
          };
        };

        # don't start nginx spam if tunnel peer is down — still start; 502 is ok
        systemd.services.nginx = {
          after = [ "wireguard-${cfg.interface}.service" ];
          wants = [ "wireguard-${cfg.interface}.service" ];
        };
      })

      # ── home (mothership): dial out, keepalive ────────────────────────
      (lib.mkIf isHome {
        networking.wireguard.interfaces.${cfg.interface} = {
          ips = [ "${cfg.homeTunnelIP}/24" ];
          privateKeyFile = cfg.privateKeyFile;
          peers = [
            {
              name = "edge";
              publicKey = cfg.edgePublicKey;
              allowedIPs = [ "${cfg.edgeTunnelIP}/32" ];
              endpoint = cfg.edgeEndpoint;
              persistentKeepalive = 25;
            }
          ];
        };

        networking.firewall.trustedInterfaces = [ cfg.interface ];
        networking.firewall.checkReversePath = "loose";

        # Headscale only reachable from tunnel + localhost (not public WAN)
        networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = [
          mesh.listenPort
        ];
      })
    ]
  );
}
