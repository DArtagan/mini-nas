{ pkgs, lib, config, inputs, ... }:

{
  packages = [
    pkgs.age
    pkgs.git
    pkgs.opentofu
    pkgs.nixos-anywhere
    pkgs.sops
  ];

  difftastic.enable = true;
}
