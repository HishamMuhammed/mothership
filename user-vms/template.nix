# copy to user-vms/<name>.nix — name must match ^[a-z][a-z0-9-]{1,15}$
# this file is NOT loaded (template.nix is ignored).
#
# after merge:
#   ssh you@you.tharavad.xyz
#   http://you.tharavad.xyz  (if publish set — run a server on that port)
#
# mesh/Headscale is internal only — you do not join a VPN.
{
  # github = "yourhandle";
  tier = "small"; # small | medium | large
  enabled = true;

  # paste from https://github.com/<you>.keys — must be non-empty
  keys = [
    # "ssh-ed25519 AAAA… comment"
  ];

  # optional public HTTP (DNS wildcard already points at edge)
  # publish = [
  #   { port = 3000; }                          # → http://you.tharavad.xyz
  #   { subdomain = "blog"; port = 8080; }      # → http://blog.tharavad.xyz
  # ];
}

