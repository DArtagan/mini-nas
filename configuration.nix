{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./disk-config.nix
    ./proxmox.nix
    ./modules/tailscale
  ];

  sops =
    let
      host_ssh_private_key = "/etc/ssh/ssh_host_ed25519_key";
      user_ssh_private_key = "/root/.ssh/id_ed25519";
    in
    {
      defaultSopsFile = ./secrets.yaml;
      age.sshKeyPaths = [ host_ssh_private_key ];
      environment.SOPS_AGE_SSH_PRIVATE_KEY_FILE = host_ssh_private_key;
      secrets = {
        "users/root/ssh_private_key" = {
          owner = "root";
          mode = "600";
          path = user_ssh_private_key;
        };
        "users/root/ssh_public_key" = {
          owner = "root";
          mode = "644";
          path = user_ssh_private_key + ".pub";
        };
        "users/syncoid/ssh_private_key" = {
          owner = config.services.syncoid.user;
          mode = "600";
        };
      };
    };

  boot = {
    kernelModules = [
      "coretemp"
      "nct6775"
    ];

    loader = {
      efi.canTouchEfiVariables = true;
      grub = {
        enable = true;
        efiSupport = true;
        device = "nodev";
        memtest86.enable = true;
        mirroredBoots = [
          {
            devices = [ "nodev" ];
            path = "/boot1";
          }
          {
            devices = [ "nodev" ];
            path = "/boot2";
          }
          {
            devices = [ "nodev" ];
            path = "/boot3";
          }
          {
            devices = [ "nodev" ];
            path = "/boot4";
          }
          {
            devices = [ "nodev" ];
            path = "/boot5";
          }
        ];
      };
      timeout = 20;
    };

    supportedFilesystems = [ "zfs" ];
    tmp.useTmpfs = true;
    zfs.devNodes = "/dev/";
  };

  fileSystems = {
    # Note: zfs datasets must be manually created on the server, and then added here for proper mounting
    "/rpool/foreign-backups/vulcanus" = {
      device = "rpool/foreign-backups/vulcanus";
      fsType = "zfs";
      options = [ "zfsutil" ];
    };
  };

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "broadcom-sta"
    ];

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 365d";
    };
    settings = {
      auto-optimise-store = true;
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  };

  environment.variables.EDITOR = "vim";
  environment.systemPackages =
    with pkgs;
    map lib.lowPrio [
      gitMinimal # Flakes clones its dependencies through the git command, so git must be installed first
      bottom # resource monitoring, alternative to top
      curl
      hddfancontrol
      lm_sensors
      tmux
      vim
      wget
    ];

  networking = {
    hostId = lib.mkDefault "c25481ef";
  };

  users = {
    groups = {
      foreign-backups = { };
    };
    users = {
      root = {
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFmUpFV6Aa7SrDryunARrpcOM3spgYwRZQantYB6gPYZ will@thebeastmanjaro"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKYSwODOrerKkBNuitwqjNioFXLDRBKqSJTayFoo1Ude willy@steamdeck"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIyPkfTI0io9dZsJstcf29tddyrsHr9bnM8UXKtaVJwm will@thenixbeast"
        ];
      };
      vulcanus = {
        group = "foreign-backups";
        isSystemUser = true;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJfQd/8CMIOVcawUS3AvgUnT+f3cL2wJtmON8pILcwwz root@vulcanus"
        ];
        # TODO: lock this down further using something like: https://discourse.nixos.org/t/wrapper-to-restrict-builder-access-through-ssh-worth-upstreaming/25834/17
        useDefaultShell = true;
      };
    };
  };

  services = {
    hddfancontrol = {
      enable = true;
      settings = {
        harddrives = {
          disks = [
            "/dev/disk/by-id/ata-Hitachi_HUA723030ALA641_YHHT74WA"
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
            "--drive-temp-range"
            "40"
            "50"
          ];
        };
      };
    };
    openssh = {
      enable = true;
      knownHosts = {
        "vulcanus.forge.local".publicKey =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIfwKbvNbbcYURG80TdzbFn9vdUFNMpnUoE67ExARElv";
      };
      settings = {
        #PermitRootLogin = "no"; # disable root login
        PasswordAuthentication = false; # disable password login, require keys
      };
      openFirewall = true;
    };
    sanoid.enable = true;
    syncoid = {
      enable = true;
      commonArgs = [
        "--no-sync-snap"
        "--no-privilege-elevation"
      ];
      sshKey = config.sops.secrets."users/syncoid/ssh_private_key".path;
      commands = {
        # TODO: move to using `--exclude-datasets`
        # TODO: use compression? `--compress` ... or no because it's already compressed on disk
        # TODO: should I turn on `--use-hold`?  Kinda seems like it's already on
        vulcanus-storage = {
          recursive = true;
          source = "mini-nas@vulcanus.forge.local:rpool/storage";
          target = "rpool/foreign-backups/vulcanus/storage";
        };
        vulcanus-root = {
          recursive = true;
          source = "mini-nas@vulcanus.forge.local:rpool/ROOT";
          target = "rpool/foreign-backups/vulcanus/ROOT";
        };
        vulcanus-data = {
          recursive = true;
          source = "mini-nas@vulcanus.forge.local:rpool/data";
          target = "rpool/foreign-backups/vulcanus/data";
        };
      };
    };
  };

  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
  };

  system.stateVersion = "25.05";

  time.timeZone = "America/New_York";
}
