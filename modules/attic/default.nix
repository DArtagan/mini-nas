{ config, pkgs, ... }:
let
  queued-build-hook = pkgs.callPackage ../../pkgs/queued-build-hook/package.nix { };

  sockPath = "/run/post-build-hook.sock";

  # The same server config atticd runs with, for minting the push token.
  serverConfig = (pkgs.formats.toml { }).generate "server.toml" config.services.atticd.settings;

  # Points attic at the token systemd hands the daemon, so no `attic login` is needed.
  atticConfig = pkgs.writeTextDir "attic/config.toml" ''
    [servers.local]
    endpoint = "http://localhost:8770"
    token-file = "/run/credentials/queued-build-hook.service/attic-push-token"
  '';

  # Run by the queued-build-hook daemon. Retries itself rather than through the daemon's
  # --retries, to cap the whole push at an hour: an attempt that atticd fails can take 15
  # minutes, so a count of retries doesn't bound the time, and a successful push can
  # take 25, so neither can a timeout on each attempt.
  pushHook = pkgs.writeShellScript "attic-push" ''
    exec ${pkgs.coreutils}/bin/timeout 1h ${pkgs.bash}/bin/bash -c '
      until ${pkgs.attic-client}/bin/attic push local:public $OUT_PATHS; do
        sleep 60
      done
    '
  '';

  # Nix runs the post-build-hook synchronously, while still holding the build's output
  # locks, so it only hands the paths to the daemon.
  enqueueHook = pkgs.writeShellScript "enqueue-post-build-hook" ''
    exec ${queued-build-hook}/bin/queued-build-hook queue --socket ${sockPath}
  '';
in
{
  imports = [ ../postgresql ];

  sops = {
    secrets = {
      "attic_environment_file" = {
        owner = config.services.atticd.user;
        inherit (config.services.atticd) group;
        mode = "400";
      };
    };
  };

  forge.postgresql.databases.atticd = { };

  services = {
    atticd = {
      enable = true;
      environmentFile = config.sops.secrets.attic_environment_file.path;
      settings = {
        # TODO: set up a reverse-proxy, use HTTPS & nice names
        listen = "[::]:8770";
        database.url = config.forge.postgresql.databases.atticd.url;
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

  systemd = {
    # A queue rather than `attic watch-store`: watch-store never retries a failed upload
    # (atticd is briefly unavailable after every restart, see the dotfiles README) and
    # skips every `-source` path.
    sockets.queued-build-hook = {
      description = "Post-build-hook socket";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = sockPath;
        SocketUser = "root";
        SocketMode = "0600";
      };
    };

    # This host holds the key that signs tokens, so it mints its own push token at boot
    # rather than keeping one in sops. Minting only signs; it doesn't touch the database.
    services.attic-push-token = {
      description = "Mint the token queued-build-hook pushes to Attic with";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        DynamicUser = true;
        EnvironmentFile = config.services.atticd.environmentFile;
        RuntimeDirectory = "attic-push-token";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
      };
      script = ''
        ${config.services.atticd.package}/bin/atticadm -f ${serverConfig} make-token \
          --sub mini-nas --validity 10y --pull public --push public \
          > "$RUNTIME_DIRECTORY/token"
      '';
    };

    services.queued-build-hook = {
      description = "Post-build-hook service";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "queued-build-hook.socket"
        "atticd.service"
        "attic-push-token.service"
      ];
      requires = [
        "queued-build-hook.socket"
        "attic-push-token.service"
      ];
      environment.XDG_CONFIG_HOME = "${atticConfig}";
      serviceConfig = {
        # pushHook does the retrying, so the daemon runs it once. Pushes it gives up on, or
        # still queued when this service stops, are dropped; the queue only lives in memory.
        # Concurrency is capped because each finished derivation queues its own push, and
        # a large build otherwise starts hundreds at once against atticd's database.
        ExecStart = "${queued-build-hook}/bin/queued-build-hook daemon --hook ${pushHook} --retries 1 --concurrency 2";
        DynamicUser = true;
        LoadCredential = "attic-push-token:/run/attic-push-token/token";
        Restart = "on-failure";
      };
    };
  };

  nix.settings.post-build-hook = enqueueHook;
}
