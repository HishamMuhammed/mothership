# user-vms/binuchambayil.nix
{
  tier = "small";  # Options: "small" | "medium" | "large"
  enabled = true;
  keys = [
    "ssh-ed25519 AAAA... binuchambayil@host"
  ];
  # optional:
  # publish = [ { port = 3000; } ];
}
