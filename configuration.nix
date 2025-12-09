{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./disk-config.nix
    ./proxmox.nix
  ];

  #sops = {
  #  defaultSopsFile = ./secrets.yaml;
  #  #age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  #  #age.keyFile = "/var/lib/sops-nix/key.txt";
  #  #age.generateKey = true;

  #  # Declare the secrets here
  #  secrets.hello = {};
  #  secrets.tailscale-pre-auth-key = {};
  #  #secrets."myservice/my_subdir/my_secret" = {};
  #};

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

  users.users = {
    root = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFmUpFV6Aa7SrDryunARrpcOM3spgYwRZQantYB6gPYZ will@thebeastmanjaro"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKYSwODOrerKkBNuitwqjNioFXLDRBKqSJTayFoo1Ude willy@steamdeck"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIyPkfTI0io9dZsJstcf29tddyrsHr9bnM8UXKtaVJwm will@thenixbeast"
      ];
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
      settings = {
        #PermitRootLogin = "no"; # disable root login
        PasswordAuthentication = false; # disable password login, require keys
      };
      openFirewall = true;
    };
    #tailscale = {
    #  enable = true;
    #  #openFirewall = true;
    #  authKeyFile = config.sops.secrets.tailscale-pre-auth-key.path;
    #  extraUpFlags = [
    #    "--login-server=https://tailscale.immortalkeep.com/auth"
    #    #"--accept-dns=false"
    #  ];
    #};
  };

  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
  };

  system.stateVersion = "25.05";

  time.timeZone = "America/New_York";
}
