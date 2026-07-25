# member HTTP publish — Railway-style public ports from user-vms/*.nix
#
#   user-vms/alvin.nix:
#     publish = [ { port = 3000; } ];                    # https? → alvin.tharavad.xyz
#     publish = [ { subdomain = "blog"; port = 8080; } ]; # blog.tharavad.xyz
#
# path:
#   internet :80 → edge nginx → WG 10.99.0.2:9080 → mothership nginx
#     → http://<member>.mothership:<port>  (mesh MagicDNS)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mothership.memberPublish;
  rawMembers = import ../lib/loadMembers.nix { inherit lib; };

  enabledMembers = lib.filterAttrs (_n: m: (m.enabled or true)) rawMembers;

  # expand publish entries → list of { member, subdomain, fqdn, port }
  routes = lib.flatten (
    lib.mapAttrsToList (
      name: m:
      map (
        p:
        let
          subdomain = p.subdomain or name;
        in
        {
          member = name;
          inherit subdomain;
          port = p.port;
          fqdn = "${subdomain}.${cfg.publicDomain}";
        }
      ) (m.publish or [ ])
    ) enabledMembers
  );

  reservedSubs = [
    "www"
    "mail"
    "smtp"
    "ftp"
    "headscale"
    "edge"
    "api"
    "admin"
  ];

  meshDomain = config.mothership.mesh.baseDomain or "mothership";
  jumpHost = cfg.mothershipTunnelIP;
  routerPort = cfg.routerPort;
in
{
  options.mothership.memberPublish = {
    enable = lib.mkEnableOption "public HTTP publish from user-vms publish = [ … ]";

    role = lib.mkOption {
      type = lib.types.enum [
        "edge"
        "home"
      ];
      description = "edge = public :80; home = mesh router on WG IP";
    };

    publicDomain = lib.mkOption {
      type = lib.types.str;
      default = "tharavad.xyz";
    };

    mothershipTunnelIP = lib.mkOption {
      type = lib.types.str;
      default = "10.99.0.2";
      description = "mothership address on wg-front (edge proxies here)";
    };

    routerPort = lib.mkOption {
      type = lib.types.port;
      default = 9080;
      description = "HTTP router port on mothership (WG-facing)";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = lib.all (
              r: builtins.match "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$" r.subdomain != null
            ) routes;
            message = "memberPublish: invalid subdomain label in user-vms publish";
          }
          {
            assertion = lib.all (r: !(lib.elem r.subdomain reservedSubs)) routes;
            message = "memberPublish: subdomain collides with reserved name (${lib.concatStringsSep ", " reservedSubs})";
          }
          {
            assertion = lib.all (r: r.port >= 1 && r.port <= 65535) routes;
            message = "memberPublish: port out of range";
          }
        ];

        environment.etc."mothership/member-publish.txt".text =
          if routes == [ ] then
            "member publish: (none)\n"
          else
            lib.concatMapStrings (r: "${r.fqdn} → ${r.member}.mothership:${toString r.port}\n") routes
            + "\nmember: run a server on that port inside the VM\n"
            + "  python3 -m http.server ${
              toString (if routes != [ ] then (builtins.head routes).port else 3000)
            }\n";
      }

      # ── mothership: Host → mesh VM:port ────────────────────────────────
      (lib.mkIf (cfg.role == "home") {
        services.nginx = {
          enable = true;
          recommendedProxySettings = true;
          recommendedOptimisation = true;
          virtualHosts = lib.listToAttrs (
            map (r: {
              name = "publish-${r.subdomain}";
              value = {
                serverName = r.fqdn;
                listen = [
                  {
                    addr = jumpHost;
                    port = routerPort;
                  }
                  {
                    addr = "127.0.0.1";
                    port = routerPort;
                  }
                ];
                locations."/" = {
                  extraConfig = ''
                    resolver 100.100.100.100 valid=30s ipv6=off;
                    set $member_upstream http://${r.member}.${meshDomain}:${toString r.port};
                    proxy_pass $member_upstream;
                    proxy_http_version 1.1;
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection $connection_upgrade;
                    proxy_connect_timeout 5s;
                    proxy_read_timeout 3600s;
                  '';
                };
              };
            }) routes
          );
        };

        # only reachable from edge via WG (not public WAN)
        networking.firewall.interfaces."wg-front".allowedTCPPorts = [ routerPort ];
        networking.firewall.allowedTCPPorts = lib.mkAfter [ ]; # don't open routerPort globally
      })

      # ── edge: public :80 → mothership router ───────────────────────────
      (lib.mkIf (cfg.role == "edge") {
        services.nginx = {
          enable = true;
          recommendedProxySettings = true;
          recommendedOptimisation = true;
          virtualHosts = lib.listToAttrs (
            map (r: {
              name = "pub-${r.subdomain}";
              value = {
                serverName = r.fqdn;
                listen = [
                  {
                    addr = "0.0.0.0";
                    port = 80;
                  }
                ];
                locations."/" = {
                  # keep headers minimal — avoid Connection/Upgrade map issues → 400
                  proxyPass = "http://${jumpHost}:${toString routerPort}";
                  recommendedProxySettings = false;
                  extraConfig = ''
                    proxy_http_version 1.1;
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header Connection "";
                    proxy_connect_timeout 5s;
                    proxy_read_timeout 3600s;
                  '';
                };
              };
            }) routes
          );
        };

        networking.firewall.allowedTCPPorts = [ 80 ];
      })
    ]
  );
}
