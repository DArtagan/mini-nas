{
  description = "mini-nas, a proxmox based server.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, nixos-facter-modules, proxmox-nixos, sops-nix, ...}: {
    nixosConfigurations = {
      mini-nas = nixpkgs.lib.nixosSystem rec {
        system = "x86_64-linux";
        modules = [
          proxmox-nixos.nixosModules.proxmox-ve
          ({ pkgs, lib, ... }: {
            services.proxmox-ve = {
              enable = true;
              ipAddress = "192.168.:.10";  # TODO: fetch this from elsewhere
            };

            nixpkgs.overlays = [
              proxmox-nixos.overlays.${system}
            ];
          })
          disko.nixosModules.disko
          ./configuration.nix
          sops-nix.nixosModules.sops
          nixos-facter-modules.nixosModules.facter
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
  };
}
