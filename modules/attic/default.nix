{ config, pkgs, ... }:
let
  postBuildHook = pkgs.writeScript "post-build-hook.sh" ''
    #!${pkgs.runtimeShell}
    export PATH=$PATH:${pkgs.nix}/bin
    exec ${pkgs.attic-client}/bin/attic push public $OUT_PATHS
  '';

  sockPath = "/run/post-build-hook.sock";

  queueBuildHook = pkgs.writeScript "post-build-hook.sh" ''
    ${pkgs.queued-build-hook}/bin/queued-build-hook queue --socket ${sockPath}
  '';
in
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

  environment.systemPackages = [ pkgs.attic-client ]; # TODO: remove this line once configuration is automated

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

  # TODO: move attic-client configuration into a sops file, that's placed in the config spot (copy/paste into my dotfiles repo too).
  # TODO: I'm doing something slightly shady in the root flake.nix - adding queued-build-hook as an overlay to nixpkgs.  Something I'd rather be doing here.

  systemd.sockets.queued-build-hook = {
    description = "Post-build-hook socket";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = sockPath;
      SocketUser = "root";
      SocketMode = "0600";
    };
  };

  systemd.services.queued-build-hook = {
    description = "Post-build-hook service";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "queued-build-hook.socket"
    ];
    requires = [ "queued-build-hook.socket" ];
    serviceConfig.ExecStart = "${pkgs.queued-build-hook}/bin/queued-build-hook daemon --retry-interval 30 --hook ${postBuildHook}";
  };

  nix.extraOptions = ''
    post-build-hook = ${queueBuildHook}
  '';
}
