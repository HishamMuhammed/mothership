# member: sreeragh — provisioned only after merge to main
{
  github = "sreeragh-s";
  tier = "large";
  enabled = true;
  keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEUiQDds4zFjVPUAAVPNOXVPtkP1nt57ZyfV2E9SnaCe"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGGOmQz5PRlntf9MGoqgHJShPQfFHscv0tLX5j5mCJ7l hey@sreeragh.me"
  ];
  publish = [
    {
      port = 3000;
    }
  ];
}
