{ config, lib, pkgs, ... }:

{
  imports = [
    #./hardware-configuration.nix  # Include the results of the hardware scan.
    #(modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
  ];

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.zfs.devNodes = "/dev/disk/by-uuid";

  nix = {
    # TODO: put the nix store in a separate zfs dataset
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 365d";
    };
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  environment.variables.EDITOR = "vim";
  environment.systemPackages = with pkgs; map lib.lowPrio [
    gitMinimal  # Flakes clones its dependencies through the git command, so git must be installed first
    curl
    tmux
    vim
    wget
  ];

  networking = {
    hostId = lib.mkDefault "c25481ef";
    interfaces = {
      eth0 = {
        ipv4.addresses = [{
          address = "192.168.122.37";
          prefixLength = 24;
        }];
      };
    };
  };

  users.users = {
    root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFmUpFV6Aa7SrDryunARrpcOM3spgYwRZQantYB6gPYZ will@thebeastmanjaro"
      ];
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      #PermitRootLogin = "no"; # disable root login
      PasswordAuthentication = false; # disable password login, require keys
    };
    openFirewall = true;
  };

  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
  };

  system.stateVersion = "25.05";

  time.timeZone = "America/New_York";
}
