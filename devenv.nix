{
  pkgs,
  ...
}:

{
  packages = [
    pkgs.age
    pkgs.git
    pkgs.nixos-anywhere
    pkgs.sops
  ];

  languages = {
    nix.enable = true;
  };

  git-hooks.hooks = {
    end-of-file-fixer = {
      enable = true;
      # devenv writes its lock without a final newline; adding one would fight it.
      excludes = [ "^devenv\\.lock$" ];
    };
    deadnix.enable = true;
    flake-checker.enable = true;
    nixfmt.enable = true;
    shellcheck.enable = true;
    statix.enable = true;
    trim-trailing-whitespace.enable = true;
  };

  difftastic.enable = true;
}
