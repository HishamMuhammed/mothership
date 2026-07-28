# member: alvin
#   ssh  alvin@alvin.tharavad.xyz
#   http://alvin.tharavad.xyz  → VM:3000  (run something that listens)
{
  github = "alvinliju";
  tier = "large"; # 4 vCPU · 4G RAM · 40G disk (for landa-api + firecracker seats)
  enabled = true;
  keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMckfpjGyg3/Hx7Xu0racB/V/PlaY5TvmHQdkLC2y90G alvinliju44@gmail.com"
    # operator break-glass (same as mothership admin)
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPgJj9GEaxD16KIwrB0M9qxeaFy33iCuCo99Jm/dxbkO terminal-shop"
  ];
  # public HTTP: DNS * already → edge; edge → mothership → this VM
  publish = [
    {
      # subdomain defaults to member name → alvin.tharavad.xyz
      port = 3000;
    }
  ];
}
