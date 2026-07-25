# load user-vms/*.nix → attrset name → raw member
# used by microvms, bastion, member-publish
{ lib }:
let
  memberDir = ../user-vms;
  dirEntries = if builtins.pathExists memberDir then builtins.readDir memberDir else { };
  memberFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "template.nix"
  ) dirEntries;
in
lib.mapAttrs' (
  file: _:
  let
    name = lib.removeSuffix ".nix" file;
  in
  {
    inherit name;
    value = import (memberDir + "/${file}");
  }
) memberFiles
