{
  description = "mini-nas, a proxmox based server.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      nixos-facter-modules,
      proxmox-nixos,
      sops-nix,
      ...
    }:
    {
      nixosConfigurations = {
        mini-nas = nixpkgs.lib.nixosSystem rec {
          system = "x86_64-linux";
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
    };
}
