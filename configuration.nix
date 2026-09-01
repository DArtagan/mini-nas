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
    ./modules/attic
    ./modules/backup_monitoring
    ./modules/distributed_builders
    ./modules/nightly_config_builder
    ./modules/tailscale
  ];

  sops =
    let
      host_ssh_private_key = "/etc/ssh/ssh_host_ed25519_key";
      user_ssh_private_key = "/root/.ssh/id_ed25519";
    in
    {
      defaultSopsFile = ./secrets.sops.yaml;
      age.sshKeyPaths = [ host_ssh_private_key ];
      environment.SOPS_AGE_SSH_PRIVATE_KEY_FILE = host_ssh_private_key;
      secrets = {
        "users/root/ssh_private_key" = {
          owner = "root";
          mode = "400";
          path = user_ssh_private_key;
        };
        "users/root/ssh_public_key" = {
          owner = "root";
          mode = "444";
          path = user_ssh_private_key + ".pub";
        };
        "users/syncoid/ssh_private_key" = {
          owner = config.services.syncoid.user;
          mode = "400";
        };
      }
      //
        lib.genAttrs
          [
            # Ping URLs for the backup layer. Root-owned: the units that use them
            # ping through an ExecStartPost with a `+` prefix, which runs as root
            # regardless of the unit's own User=.
            "healthchecks/sanoid-mini-nas"
            "healthchecks/syncoid-vulcanus-storage"
            "healthchecks/syncoid-vulcanus-root"
            "healthchecks/syncoid-vulcanus-data"
            "healthchecks/pool-health-mini-nas"
            "healthchecks/zfs-replication-freshness"
          ]
          (_: {
            mode = "400";
          });
    };

  boot = {
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

    kernelModules = [
      "coretemp"
      "nct6775"
    ];
    kernelParams = [ "zfs.zfs_arc_max=6442450944" ];

    supportedFilesystems = [ "zfs" ];
    tmp.useTmpfs = true;
    zfs = {
      devNodes = "/dev/";
      # Interim capacity. spool's two bays are the only expansion room an
      # 8-bay chassis has, and its 1.8 TiB disks are too small to join either
      # rpool vdev, so the pool is destroyed and the slots refilled once
      # replacement disks arrive.
      extraPools = [ "spool" ];
    };
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

      substituters = [
        "http://localhost:8770/public"
      ];
      trusted-public-keys = [
        "public:YyCDrhNMvRWl7OxoW+8ueMcmVOOc1bllsVCMRNfZWpQ="
      ];
    };
  };

  environment.variables.EDITOR = "vim";
  environment.systemPackages =
    with pkgs;
    map lib.lowPrio [
      gitMinimal # Flakes clones its dependencies through the git command, so git must be installed first
      e2fsprogs # Provides `badblocks` for disk testing
      gptfdisk # Provides `sgdisk` for partitioning during disk replacement
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
    hostName = "mini-nas";
  };

  programs = {
    nh.enable = true;
  };

  users = {
    groups = {
      #foreign-backups = { };
    };
    users = {
      root = {
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFmUpFV6Aa7SrDryunARrpcOM3spgYwRZQantYB6gPYZ will@thebeastmanjaro"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKYSwODOrerKkBNuitwqjNioFXLDRBKqSJTayFoo1Ude willy@steamdeck"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIyPkfTI0io9dZsJstcf29tddyrsHr9bnM8UXKtaVJwm will@thenixbeast"
        ];
      };
      #vulcanus = {
      #  group = "foreign-backups";
      #  isSystemUser = true;
      #  openssh.authorizedKeys.keys = [
      #    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJfQd/8CMIOVcawUS3AvgUnT+f3cL2wJtmON8pILcwwz root@vulcanus"
      #  ];
      #  # TODO: lock this down further using something like: https://discourse.nixos.org/t/wrapper-to-restrict-builder-access-through-ssh-worth-upstreaming/25834/17
      #  useDefaultShell = true;
      #};
    };
  };

  services = {
    hddfancontrol = {
      enable = true;
      settings = {
        harddrives = {
          disks = [
            "/dev/disk/by-id/ata-Hitachi_HUA723030ALA641_YHHT74WA"
            "/dev/disk/by-id/ata-OOS3000G_00038E07"
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
        AcceptEnv = lib.mkForce [
          "LANG"
          "LC_*"
        ]; # Fix for: https://github.com/SaumonNet/proxmox-nixos/issues/212
        #PermitRootLogin = "no"; # disable root login
        PasswordAuthentication = false; # disable password login, require keys
      };
      openFirewall = true;
    };
    zfs.autoScrub = {
      enable = true;
      # Third Sunday, so it never coincides with vulcanus's second-Sunday
      # scrub -- both would otherwise compete for the same replication window.
      # 03:20 rather than the hour, to miss the hourly sanoid and syncoid runs
      # at :00 and :15.
      interval = "Sun *-*-15..21 03:20:00";
      # The 6h default assumes a fleet, or several pools on shared spindles.
      # Neither holds here: one host, one zfs-scrub.service covering both
      # pools, and a scrub that runs for days -- so six hours of jitter cannot
      # decorrelate anything the runtime does not already overlap, and only
      # makes the start time unattributable. What the jitter is still for is
      # Persistent=yes: this host reboots itself via system.autoUpgrade, and
      # every missed timer fires at once on the way back up.
      randomizedDelaySec = "15m";
    };

    sanoid = {
      enable = true;

      # Datasets are not optional here: `enable = true` with none declared
      # generates an empty config, sanoid fatals on an empty config, and
      # nothing prunes the replication target.
      #
      # autosnap is off everywhere: snapshots arrive by replication, and taking
      # local ones would leave the target ahead of the source, which makes the
      # next incremental receive fail without -F.
      templates = {
        # Mass files. Deeper daily history than the source keeps, because
        # syncoid runs --no-sync-snap: a target that retains more than the
        # source is what makes a deletion discovered late still recoverable.
        # Fewer hourlies than the source, because "I just deleted that" is
        # served by the copy on vulcanus, not by this one.
        replica-deep = {
          autosnap = false;
          autoprune = true;
          hourly = 24;
          daily = 60;
          monthly = 24;
          yearly = 0;
        };
        # Guest zvols and the PVE root. High churn, and rpool/data stops being
        # replicated once PBS sync covers the guests, so depth here would be
        # paid for and then thrown away.
        replica-shallow = {
          autosnap = false;
          autoprune = true;
          hourly = 0;
          daily = 30;
          monthly = 0;
          yearly = 0;
        };
      };

      datasets = {
        "rpool/foreign-backups/vulcanus/storage" = {
          useTemplate = [ "replica-deep" ];
          recursive = true;
        };
        "rpool/foreign-backups/vulcanus/ROOT" = {
          useTemplate = [ "replica-shallow" ];
          recursive = true;
        };
        "rpool/foreign-backups/vulcanus/data" = {
          useTemplate = [ "replica-shallow" ];
          recursive = true;
        };
      };
    };

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
