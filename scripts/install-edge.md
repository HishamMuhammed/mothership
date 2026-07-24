# install edge via Ubuntu + nixos-anywhere

**Destructive:** wipes the VPS system disk. IP `178.105.120.5` should stay if you rebuild in-place.

## 1. Rebuild VPS as Ubuntu

Provider console (Hetzner etc.):

- Rebuild / reimage → **Ubuntu 24.04** (or 22.04)
- Add **your SSH key** at create time (cloud-init)
- Note: user is often `root` or `ubuntu`

Test:

```bash
ssh root@178.105.120.5   # or ubuntu@…
```

## 2. On Ubuntu — enable root SSH key (if you only have ubuntu user)

```bash
# as ubuntu with sudo:
sudo mkdir -p /root/.ssh
sudo cp ~/.ssh/authorized_keys /root/.ssh/authorized_keys
sudo chmod 700 /root/.ssh
sudo chmod 600 /root/.ssh/authorized_keys
# optional: permit root login with keys
```

Check disk name:

```bash
lsblk
# usually sda on Hetzner Cloud — if nvme0n1, edit hosts/edge/default.nix:
#   mothership.edge.diskDevice = "/dev/nvme0n1";
```

## 3. From your Mac (this repo)

```bash
cd ~/Documents/tinkerhub0/mothership   # or wherever the flake is
git pull

# install NixOS from Ubuntu over SSH (wipes disk)
nix run github:nix-community/nixos-anywhere -- \
  --flake .#edge \
  --build-on remote \
  root@178.105.120.5
```

If build-on remote is slow/fails, drop `--build-on remote` (builds on Mac → needs linux builder or linux-builder).

On pure Mac without linux builder, use:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#edge \
  --build-on remote \
  root@178.105.120.5
```

## 4. After reboot

```bash
ssh root@178.105.120.5
# or
ssh nixos@178.105.120.5   # if you use nixos user from admins.nix

hostname   # edge
systemctl is-active headscale sshd
curl -sS -m 3 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/
```

## 5. Mesh bootstrap on edge

```bash
sudo -u headscale headscale users create tinkerhub
KEY=$(sudo -u headscale headscale preauthkeys create -u 1 --reusable --expiration 168h)
echo "$KEY"
sudo tailscale up \
  --login-server=http://127.0.0.1:8080 \
  --authkey="$KEY" \
  --hostname=edge \
  --reset
tailscale ip -4   # expect 100.64.0.1
```

## 6. Point mothership + laptop at the VPS

```bash
# mothership / mac
sudo tailscale up \
  --login-server=http://178.105.120.5:8080 \
  --authkey="$KEY" \
  --hostname=mothership \
  --reset
```

Optional Hetzner DNS:

```yaml
# A headscale.example  →  178.105.120.5
```

then set `serverUrl = "http://headscale.example:8080"` (or https later).
