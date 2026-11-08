#!/usr/bin/env sh
nix build .#nixosConfigurations.machineIso.config.system.build.isoImage
ls result/iso/
