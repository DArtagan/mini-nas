{ config, ... }:
{
  sops = {
    secrets = {
      "attic_environment_file" = {
        owner = config.services.atticd.user;
        inherit (config.services.atticd) group;
        mode = "400";
      };
    };
  };

  services = {
    atticd = {
      enable = true;
      environmentFile = config.sops.secrets.attic_environment_file.path;
      settings = {
        # TODO: set up a reverse-proxy, use HTTPS & nice names
        listen = "[::]:8770";
        garbage-collection = {
          interval = "12 hours";
          default-retention-period = "6 months";
        };
      };
    };
  };

  users = {
    # TODO: submit a PR to nixpkgs to make this user self-creating, following the example of https://github.com/NixOS/nixpkgs/blob/36d230276f1561f67087abf0804e9ea9e29f0184/nixos/modules/services/backup/syncoid.nix#L343
    groups = {
      ${config.services.atticd.group} = { };
    };
    users = {
      ${config.services.atticd.user} = {
        inherit (config.services.atticd) group;
        isSystemUser = true;
      };
    };
  };
}
