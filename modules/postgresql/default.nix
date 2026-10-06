# This host's Postgres server, shared by the services that declare a database under
# my.postgresql.databases. The server runs only while at least one does.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.postgresql;
in
{
  options.my.postgresql.databases = lib.mkOption {
    description = ''
      Databases to create, each owned by a role of the same name. A service connects
      over the local socket as the Unix user of that name, which Postgres trusts
      without a password.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options.url = lib.mkOption {
            description = "Connection URL for the service that owns the database.";
            type = lib.types.str;
            readOnly = true;
            default = "postgresql:///${name}?host=/run/postgresql&user=${name}";
          };
        }
      )
    );
    default = { };
    example = {
      atticd = { };
    };
  };

  config = lib.mkIf (cfg.databases != { }) {
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_18;
      ensureDatabases = lib.attrNames cfg.databases;
      ensureUsers = map (name: {
        inherit name;
        ensureDBOwnership = true;
      }) (lib.attrNames cfg.databases);
      settings = {
        # On ZFS (rpool/postgresql, 32K records), which never writes a record in part, an
        # 8K page can't be torn, so Postgres needn't guard against it.
        full_page_writes = false;
      };
    };
  };
}
