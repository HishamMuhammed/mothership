# Let's Encrypt ACME on edge (nginx HTTP-01).
# NixOS equivalent of certbot: certs under /var/lib/acme, auto-renew.
{
  config,
  lib,
  ...
}:
let
  cfg = config.mothership.acme;
in
{
  options.mothership.acme = {
    enable = lib.mkEnableOption "Let's Encrypt certificates for public nginx vhosts";

    email = lib.mkOption {
      type = lib.types.str;
      default = "ops@tharavad.xyz";
      description = "ACME account email (expiry notices). Not a secret.";
    };
  };

  config = lib.mkIf cfg.enable {
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.email;
    };

    # challenge (HTTP-01) + HTTPS
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    # nginx needs to read certs under /var/lib/acme
    users.users.nginx.extraGroups = [ "acme" ];

    environment.etc."mothership/acme.txt".text = ''
      ACME:    on (Let's Encrypt via security.acme)
      email:   ${cfg.email}
      certs:   /var/lib/acme/<domain>/

      vhosts: enableACME + forceSSL (landing, member publish, landa)
      renew:  systemd timers acme-*.timer
      logs:   journalctl -u 'acme-*' -f

      same job as certbot; NixOS-managed (lego), not certbot CLI.
    '';
  };
}

