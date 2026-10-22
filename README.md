# mini-nas
Configuration for mini-ITX server

# Install

1. Download the latest version of the NixOS ISO (minimal edition) and make a bootable USB of it.
2. Boot the machine from the USB and follow the steps presented by the CLI installer (https://nixos.org/manual/nixos/stable/#sec-installation-manual)
3. On the NAS machine `ip address` to get the machine's address.  Update `192.168.1.11` wherever it appears (`git grep -n 192.168.1.11`).
4. On the NAS machine `lsblk -o name,size,model,serial,uuid | grep sd` to double-check the disk IDs.  Update those in `disk-config.nix`.
5. `echo {} > facter.json` to zero that file out, ready for nixos-anywhere to freshly populate it.
6. `nix run github:nix-community/nixos-anywhere -- --generate-hardware-config nixos-facter ./facter.json --flake .#nixosConfigurations.mini-nas --target-host root@192.168.1.11`

# Update

Manage the Nixos configuration remotely by:
1. `nh os switch .#nixosConfigurations.mini-nas --target-host "root@192.168.1.11"`

# Attic Nix binary cache

## Grant access

mini-nas pushes its own builds with a token it mints at boot (`attic-push-token.service`),
so it needs no setup. The dotfiles hosts share one token, kept in that repo's
`modules/attic-push/secrets.yaml`. To create or replace it, from a mini-nas console:
```
atticd-atticadm make-token --sub "workstations" --validity "99y" --pull "public" --push "public"
```
Attic can't revoke a single token. To cut one off, rotate the signing key in
`attic_environment_file`, which invalidates every token, then mint the shared one again.
