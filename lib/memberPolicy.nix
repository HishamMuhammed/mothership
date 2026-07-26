# shared member identity rules — one name, one seat
{ lib }:
rec {
  nameRegex = "^[a-z][a-z0-9-]{1,15}$";

  # unix / dns / house reserved — cannot be a member hostname
  reserved = [
    "root"
    "admin"
    "administrator"
    "ubuntu"
    "nixos"
    "git"
    "www"
    "api"
    "mail"
    "ftp"
    "ssh"
    "host"
    "gateway"
    "router"
    "edge"
    "mothership"
    "headscale"
    "bastion"
    "proxy"
    "nginx"
    "deck"
    "template"
    "localhost"
  ];

  validName = name: builtins.match nameRegex name != null;

  isReserved = name: lib.elem name reserved;

  # github handles present on members (lowercased), ignore null/empty
  githubByMember =
    members:
    lib.filterAttrs (_: g: g != null && g != "") (
      lib.mapAttrs (
        _: m:
        let
          g = m.github or null;
        in
        if g == null then null else lib.toLower (toString g)
      ) members
    );

  # true if every github is claimed by at most one member
  githubsUnique =
    members:
    let
      pairs = lib.mapAttrsToList (name: g: { inherit name g; }) (githubByMember members);
      byGithub = lib.groupBy (p: p.g) pairs;
      dups = lib.filterAttrs (_: xs: lib.length xs > 1) byGithub;
    in
    dups == { };

  duplicateGithubs =
    members:
    let
      pairs = lib.mapAttrsToList (name: g: { inherit name g; }) (githubByMember members);
      byGithub = lib.groupBy (p: p.g) pairs;
      dups = lib.filterAttrs (_: xs: lib.length xs > 1) byGithub;
    in
    lib.mapAttrsToList (
      g: xs: "${g} → ${lib.concatMapStringsSep ", " (p: p.name) xs}"
    ) dups;
}
