# mini-nas
Configuration for mini-ITX server

# Install

1. Download the latest version of the NixOS ISO (minimal edition) and make a bootable USB of it.
2. Boot the machine from the USB and follow the steps presented by the CLI installer (https://nixos.org/manual/nixos/stable/#sec-installation-manual)
3. `cd nixos`
4. `ipconfig` to get the machine's address.  Update that in `main.tf`.
5. `lsblk` to double-check the disk IDs.  Update those in `disk-config.nix`.
6. `echo {} > facter.json` to zero that file out, ready for terraform to freshly populate it.
7. `terraform apply`

# Update

Manage the Nixos configuration remotely by:
1. `cd nixos`
2. `nixos-rebuild switch --flake .#mini-nas --target-host "root@192.168.122.37"
`
