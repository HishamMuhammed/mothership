# mesh — options + tailscale; headscale only when controlPlane=true (edge).
# cloudflare tunnel optional. not the IdP (git is).
{
  imports = [
    ./headscale.nix
    ./tailscale.nix
    ./cloudflare.nix
  ];
}
