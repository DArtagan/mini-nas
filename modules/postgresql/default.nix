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
        # Its own dataset, rpool/postgresql, has 16K records to suit Postgres's 8K pages.
        # ZFS never writes a record in part, so Postgres needn't guard against torn pages.
        full_page_writes = false;
      };
    };
  };
}
