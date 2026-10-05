{
  config,
  lib,
  pkgs,
  ...
}:
let
  queued-build-hook = pkgs.callPackage ../../pkgs/queued-build-hook/package.nix { };

  # Over the local socket, where Postgres knows atticd by its Unix user.
  postgresUrl = "postgresql:///atticd?host=/run/postgresql&user=atticd";

  # Copies the SQLite database into Postgres; see the script for when to run it.
  migrateToPostgres = pkgs.writeShellApplication {
    name = "attic-migrate-to-postgres";
    runtimeInputs = [
      config.services.postgresql.package
      pkgs.sqlite
      pkgs.util-linux
    ];
    runtimeEnv = {
      ATTICD = lib.getExe config.services.atticd.package;
      ATTICD_CONFIG = (pkgs.formats.toml { }).generate "server.toml" (
        lib.recursiveUpdate config.services.atticd.settings { database.url = postgresUrl; }
      );
      ATTICD_ENV = config.services.atticd.environmentFile;
    };
    text = builtins.readFile ./migrate-to-postgres.sh;
  };

  sockPath = "/run/post-build-hook.sock";

  # The same server config atticd runs with, for minting the push token.
  serverConfig = (pkgs.formats.toml { }).generate "server.toml" config.services.atticd.settings;

  # Points attic at the token systemd hands the daemon, so no `attic login` is needed.
  atticConfig = pkgs.writeTextDir "attic/config.toml" ''
    [servers.local]
    endpoint = "http://localhost:8770"
    token-file = "/run/credentials/queued-build-hook.service/attic-push-token"
  '';

  # Run by the queued-build-hook daemon, which retries it on failure.
  pushHook = pkgs.writeShellScript "attic-push" ''
    exec ${pkgs.attic-client}/bin/attic push local:public $OUT_PATHS
  '';

  # Nix runs the post-build-hook synchronously, while still holding the build's output
  # locks, so it only hands the paths to the daemon.
  enqueueHook = pkgs.writeShellScript "enqueue-post-build-hook" ''
    exec ${queued-build-hook}/bin/queued-build-hook queue --socket ${sockPath}
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

  environment.systemPackages = [ migrateToPostgres ];

  services = {
    atticd = {
      enable = true;
      environmentFile = config.sops.secrets.attic_environment_file.path;
      settings = {
        # TODO: set up a reverse-proxy, use HTTPS & nice names
        listen = "[::]:8770";
        database.url = postgresUrl;
        garbage-collection = {
          interval = "12 hours";
          default-retention-period = "6 months";
        };
      };
    };

    # atticd's database. On SQLite, sea-orm gives atticd a single connection, which one
    # large upload holds long enough to time out every other request.
    postgresql = {
      enable = true;
      package = pkgs.postgresql_18;
      ensureDatabases = [ "atticd" ];
      ensureUsers = [
        {
          name = "atticd";
          ensureDBOwnership = true;
        }
      ];
      settings = {
        # Its own dataset, rpool/postgresql, has 16K records to suit Postgres's 8K pages.
        # ZFS never writes a record in part, so Postgres needn't guard against torn pages.
        full_page_writes = false;
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
        # Retries cover atticd restarting.
        # Concurrency is capped because each finished derivation queues its own push, and
        # a large build otherwise starts hundreds at once against atticd's database.
        ExecStart = "${queued-build-hook}/bin/queued-build-hook daemon --hook ${pushHook} --retry-interval 30 --retries 20 --concurrency 2";
        DynamicUser = true;
        LoadCredential = "attic-push-token:/run/attic-push-token/token";
        Restart = "on-failure";
      };
    };
  };

  nix.settings.post-build-hook = enqueueHook;
}
