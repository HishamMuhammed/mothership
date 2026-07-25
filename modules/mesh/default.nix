# mesh — Headscale on mothership; edge is WG reverse + nginx front door.
# cloudflare tunnel optional (legacy). not the IdP (git is).
{
  imports = [
    ./headscale.nix
    ./tailscale.nix
    ./front-door.nix
    ./cloudflare.nix
  ];
}
