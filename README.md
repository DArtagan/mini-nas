# mini-nas
Configuration for mini-ITX server

# Install

1. Download the latest version of the NixOS ISO (minimal edition) and make a bootable USB of it.
2. Boot the machine from the USB and follow the steps presented by the CLI installer (https://nixos.org/manual/nixos/stable/#sec-installation-manual)
3. `cd nixos`
4. On the NAS machine `ipconfig` to get the machine's address.  Update that in `main.tf`.
5. On the NAS machine `lsblk -o name,size,model,serial,uuid | grep sd` to double-check the disk IDs.  Update those in `disk-config.nix`.
6. `echo {} > facter.json` to zero that file out, ready for terraform to freshly populate it.
7. `nix run github:nix-community/nixos-anywhere -- --generate-hardware-config nixos-facter ./facter.json --flake .#nixosConfiguration.mini-nas --target-host root@192.168.1.11`
7. `terraform apply`

# Update

Manage the Nixos configuration remotely by:
1. `cd nixos`
2. `nh os switch .#nixosConfigurations.mini-nas --target-host "root@192.168.1.11"`

# Attic Nix binary cache

## Grant access

From a mini-nas console run something like (changing all the settings accordingly):
```
atticd-atticadm make-token --sub "thenixbeast" --validity "99y" --pull "public" --push "public" --create-cache "thenixbeast-*" --push "thenixbeast-*" --pull "thenixbeast-*" --create-cache "public" --configure-cache "public" --configure-cache "thenixbeast-*" --configure-cache-retention "public" --configure-cache-retention "thenixbeast-*" --destroy-cache "thenixbeast-*"
```
