{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs }:
    {
      nixosConfigurations.machineIso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          #./machine.nix
          (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
          (nixpkgs + "/nixos/modules/installer/cd-dvd/channel.nix")
          (
            { pkgs, ... }:
            {
              environment.systemPackages =
                with pkgs;
                map lib.lowPrio [
                  nixos-facter
                  tmux
                ];
              nix = {
                # Enable flakes support
                settings.experimental-features = [
                  "nix-command"
                  "flakes"
                ];
              };
              systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];
              # Enable SSH in the boot process.
              users.users.root.openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFmUpFV6Aa7SrDryunARrpcOM3spgYwRZQantYB6gPYZ"
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIyPkfTI0io9dZsJstcf29tddyrsHr9bnM8UXKtaVJwm"
              ];
              isoImage.squashfsCompression = "gzip -Xcompression-level 1";
              networking = {
                usePredictableInterfaceNames = false;
                useDHCP = nixpkgs.lib.mkDefault true;
                nameservers = [ "1.1.1.1" ];
              };
            }
          )
        ];
      };
    };
}
