# member: sreeragh — provisioned only after merge to main
{
  github = "sreeragh-s";
  tier = "large";
  enabled = true;
  keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEUiQDds4zFjVPUAAVPNOXVPtkP1nt57ZyfV2E9SnaCe"
  ];
  publish = [
    {
      port = 3000;
    }
  ];
}
