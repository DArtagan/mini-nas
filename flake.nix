{
  description = "mini-nas, a proxmox based server.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      deploy-rs,
      disko,
      nixos-facter-modules,
      proxmox-nixos,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        mini-nas = nixpkgs.lib.nixosSystem rec {
          modules = [
            disko.nixosModules.disko
            nixos-facter-modules.nixosModules.facter
            proxmox-nixos.nixosModules.proxmox-ve
            sops-nix.nixosModules.sops
            ./configuration.nix
            {
              imports = [ self.inputs.disko.nixosModules.disko ]; # The line `disko.nixosModules.disko` above should be enough, but it wasn't finding diskoScript until I added this import as well
            }
            (_: {
              services.proxmox-ve = {
                enable = true;
                ipAddress = "192.168.1.11";
              };

              nixpkgs.overlays = [
                proxmox-nixos.overlays.${system}
              ];
            })
            {
              config.facter.reportPath =
                if builtins.pathExists ./facter.json then
                  ./facter.json
                else
                  throw "Have you forgotten to run nixos-anywhere with `--generate-hardware-config nixos-facter ./facter.json`?";
            }
          ];
        };
      };

      deploy.nodes.mini-nas = {
        hostname = "mini-nas.forge.local";
        profiles.system = {
          sshUser = "root";
          path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.mini-nas;
        };
      };

      checks = builtins.mapAttrs (_: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
