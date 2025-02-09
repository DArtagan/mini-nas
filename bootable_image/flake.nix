{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations.machineIso = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        #./machine.nix
        (nixpkgs
          + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
        (nixpkgs + "/nixos/modules/installer/cd-dvd/channel.nix")
        ({ pkgs, ... }: {
          # Enable SSH in the boot process.
          systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFmUpFV6Aa7SrDryunARrpcOM3spgYwRZQantYB6gPYZ"
          ];
          isoImage.squashfsCompression = "gzip -Xcompression-level 1";
          networking = {
            usePredictableInterfaceNames = false;
            useDHCP = true;
            nameservers = [ "1.1.1.1" ];
          };
        })
      ];
    };
  };
}
