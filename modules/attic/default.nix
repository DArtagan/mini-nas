{
  config,
  inputs,
  pkgs,
  ...
}:
let
  queued-build-hook = inputs.queued-build-hook.packages.${pkgs.stdenv.hostPlatform.system}.default;

  sockPath = "/run/post-build-hook.sock";

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
      # Mint with: atticd-atticadm make-token --sub mini-nas --validity 99y --pull public --push public
      "attic/push_token" = { };
    };
  };

  environment.systemPackages = [ pkgs.attic-client ];

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

  # A queue rather than `attic watch-store`: watch-store never retries a failed upload
  # (atticd is briefly unavailable after every restart, see the dotfiles README) and
  # skips every `-source` path.
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
      "atticd.service"
    ];
    requires = [ "queued-build-hook.socket" ];
    environment.XDG_CONFIG_HOME = "${atticConfig}";
    serviceConfig = {
      # Retries cover atticd's startup GC, which holds the database lock for minutes.
      # Concurrency is capped because each finished derivation queues its own push, and
      # a large build otherwise starts hundreds at once against atticd's SQLite.
      ExecStart = "${queued-build-hook}/bin/queued-build-hook daemon --hook ${pushHook} --retry-interval 30 --retries 20 --concurrency 2";
      DynamicUser = true;
      LoadCredential = "attic-push-token:${config.sops.secrets."attic/push_token".path}";
      Restart = "on-failure";
    };
  };

  nix.settings.post-build-hook = enqueueHook;
}
