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
    opentofu.enable = true;
  };

  git-hooks.hooks = {
    end-of-file-fixer.enable = true;
    deadnix.enable = true;
    flake-checker.enable = true;
    nixfmt-rfc-style.enable = true;
    shellcheck.enable = true;
    statix.enable = true;
    tflint.enable = true;
    trim-trailing-whitespace.enable = true;
  };

  difftastic.enable = true;
}
