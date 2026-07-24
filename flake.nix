{
  description = "mothership — git is the IdP; Nix is the compiler; if you know you know";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    srvos.url = "github:nix-community/srvos";
    srvos.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";

    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      srvos,
      disko,
      nixos-facter-modules,
      microvm,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      nixosConfigurations.mothership = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit self; };
        modules = [
          srvos.nixosModules.server
          disko.nixosModules.disko
          nixos-facter-modules.nixosModules.facter
          microvm.nixosModules.host
          ./hosts/mothership
        ];
      };

      # public control plane (VPS) — Headscale + static public IP
      # install: nixos-anywhere --flake .#edge root@178.105.120.5
      nixosConfigurations.edge = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit self; };
        modules = [
          srvos.nixosModules.server
          disko.nixosModules.disko
          ./hosts/edge
        ];
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lib = nixpkgs.lib;
          isLinux = pkgs.stdenv.isLinux;
        in
        {
          default = pkgs.mkShell {
            packages =
              with pkgs;
              [
                git
                jq
                nixfmt
              ]
              ++ lib.optionals isLinux [
                headscale
                tailscale
              ];

            shellHook = ''
              cat <<'EOF'
              mothership // operator shell
              read why-this-exist first.

              nix eval .#nixosConfigurations.mothership.config.networking.hostName
              nix eval .#nixosConfigurations.mothership.config.mothership.mesh.mothershipIPv4
              nix flake check
              scripts/signup --help

              full rebuild / microvms / headscale: linux box only
              EOF
            '';
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          host = self.nixosConfigurations.mothership.config;
        in
        {
          hostname = pkgs.runCommand "check-hostname" { } ''
            test "${host.networking.hostName}" = "mothership"
            touch $out
          '';
          mesh-ip = pkgs.runCommand "check-mesh-ip" { } ''
            test "${host.mothership.mesh.mothershipIPv4}" = "100.64.0.1"
            touch $out
          '';
          # control plane is edge; mothership is a node only
          mothership-not-control = pkgs.runCommand "check-mothership-node" { } ''
            test "${if host.mothership.mesh.controlPlane then "true" else "false"}" = "false"
            touch $out
          '';
          microvms-disabled = pkgs.runCommand "check-microvms-disabled" { } ''
            test "${if host.mothership.microvms.enable then "true" else "false"}" = "false"
            touch $out
          '';
          edge-hostname = pkgs.runCommand "check-edge-hostname" { } ''
            test "${self.nixosConfigurations.edge.config.networking.hostName}" = "edge"
            touch $out
          '';
          edge-control = pkgs.runCommand "check-edge-control" { } ''
            test "${
              if self.nixosConfigurations.edge.config.mothership.mesh.controlPlane then "true" else "false"
            }" = "true"
            touch $out
          '';
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
