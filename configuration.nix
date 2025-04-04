{ config, lib, pkgs, ... }:

{
  imports = [
    #(modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
  ];

  boot = {
    kernelModules = [
      "coretemp"
      "nct6775"
    ];

    loader.grub = {
      efiSupport = true;
      efiInstallAsRemovable = true;
    };

    zfs.devNodes = "/dev/disk/by-uuid";
  };

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "broadcom-sta"
  ];

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
    hddfancontrol
    lm_sensors
    tmux
    vim
    wget
  ];

  networking = {
    hostId = lib.mkDefault "c25481ef";
    interfaces = {
      eth0 = {
        ipv4.addresses = [{
          address = "192.168.1.10";
          prefixLength = 24;
        }];
      };
    };
  };

  users.users = {
    root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFmUpFV6Aa7SrDryunARrpcOM3spgYwRZQantYB6gPYZ will@thebeastmanjaro"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKYSwODOrerKkBNuitwqjNioFXLDRBKqSJTayFoo1Ude willy@steamdeck"
      ];
    };
  };

  services = {
    hddfancontrol = {
      enable = true;
      disks = [
        "/dev/disk/by-id/ata-Hitachi_HDS723030ALA640_MK0331YHG5Y9WA"
        "/dev/disk/by-id/ata-ST3000DM001-1CH166_Z1F48TA8"
        "/dev/disk/by-id/ata-ST4000DM005-2DP166_ZGY0B2RP"
        "/dev/disk/by-id/ata-ST4000DM005-2DP166_ZGY0B2SR"
        "/dev/disk/by-id/ata-ST4000VN008-2DR166_ZGY8DP80"
        "/dev/disk/by-id/ata-TOSHIBA_DT01ACA200_67CVX7YAS"
        "/dev/disk/by-id/ata-TOSHIBA_DT01ACA200_67CVX8BAS"
        "/dev/disk/by-id/ata-TOSHIBA_DT01ACA300_Z2L4RUPGS"
      ];
      pwmPaths = [
        "/sys/devices/platform/nct6775.656/hwmon/hwmon1/pwm3:90:85"
      ];
      extraArgs = [
        "--min-fan-speed-prct=0"
        "--interval=1min"
        "--drive-temp-range" "40" "50"
      ];
    };
    openssh = {
      enable = true;
      settings = {
        #PermitRootLogin = "no"; # disable root login
        PasswordAuthentication = false; # disable password login, require keys
      };
      openFirewall = true;
    };
  };

  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
  };

  system.stateVersion = "25.05";

  time.timeZone = "America/New_York";
}
