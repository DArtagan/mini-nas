# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

NixOS + OpenTofu/Terraform configuration for `mini-nas`, a single mini-ITX home server
that runs Proxmox VE on bare metal (IP `192.168.1.11`, Tailscale/LAN name
`mini-nas.forge.local`). There is no application code here — everything is declarative
infrastructure: the NixOS system, its ZFS disk layout, secrets, and the Proxmox-level
users/groups managed out-of-band by Terraform.

The host is part of a small fleet on the `*.forge.local` network: `mini-nas` (this
machine), `thenixbeast`, `steamdeck` (Nix remote builders), and `vulcanus` (a foreign
host whose ZFS pools are pulled here as backups).

## Environment & commands

Dev tooling comes from `devenv` (auto-loaded via `direnv` from `.envrc`). The dev shell
provides `nix`, `sops`, `age`, `nixos-anywhere`, and `tofu`.

- **Format / lint:** git-hooks run on commit (`nixfmt`, `deadnix`, `statix`,
  `flake-checker`, `shellcheck`, `tflint`, whitespace fixers). Run them ad-hoc with
  `pre-commit run --all-files`. Keep Nix formatted with `nixfmt`.
- **Build the system config:** `nix build .#nixosConfigurations.mini-nas.config.system.build.toplevel`
- **Deploy an update to the running host:**
  `nh os switch .#nixosConfigurations.mini-nas --target-host "root@192.168.1.11"`
  (deploy-rs is also wired up as an alternative: `deploy .#mini-nas`).
- **First-time bare-metal install** (see `README.md` for the full sequence): zero out
  `facter.json`, then `nixos-anywhere --generate-hardware-config nixos-facter ./facter.json --flake .#nixosConfigurations.mini-nas --target-host root@192.168.1.11`, then `tofu apply`.
- **Proxmox users/groups:** `tofu apply` (state in `main.tf`, talks to the Proxmox API
  at `192.168.1.11:8006`). This is separate from the NixOS deploy.
- **Custom install ISO:** `cd bootable_image && sh build.sh`.

## Architecture

- **`flake.nix`** is the entrypoint. It assembles `nixosConfigurations.mini-nas` from
  `configuration.nix` plus flake-module inputs: `disko` (partitioning), `nixos-facter`
  (hardware detection), `proxmox-nixos` (Proxmox VE), and `sops-nix` (secrets). It also
  defines the `deploy.nodes.mini-nas` deploy-rs target.
- **`configuration.nix`** is the top-level host config and imports everything under
  `modules/`. It wires up the ZFS boot loader (mirrored `/boot1`..`/boot5` across disks),
  sanoid/syncoid ZFS snapshot + replication (pulling `vulcanus` pools into
  `rpool/foreign-backups`), `hddfancontrol`, SSH, and `system.autoUpgrade`.
- **`disk-config.nix`** is the disko declaration of the ZFS topology: two raidz1 vdevs in
  `rpool` (root/nix/var/home datasets) and one raidz1 vdev in `spool`. Disks are addressed
  by `/dev/disk/by-id/ata-...` serial paths so they surface in `zpool status`.
- **`facter.json`** is machine-generated hardware config (from `nixos-facter`). Do not
  hand-edit; it is regenerated during install.
- **`proxmox.nix`** sets up the `vmbr0` Proxmox network bridge over `systemd.network`.
- **`main.tf`** manages Proxmox-level identity (the `admin` group, the `will@pam` user) via
  the `bpg/proxmox` provider — the layer NixOS can't declare.

### modules/

Each subdirectory is an imported NixOS module, some with their own `secrets.yaml`:

- **`attic/`** — self-hosted Nix binary cache (`atticd` on `[::]:8770`). Also installs a
  `queued-build-hook` that pushes locally-built store paths to the `public` cache. The host
  substitutes from `http://localhost:8770/public` (see `nix.settings` in `configuration.nix`).
- **`distributed_builders/`** — configures `thenixbeast`/`steamdeck` as Nix remote build
  machines over `ssh-ng`, and the local `nix` build user that peers connect back through.
- **`nightly_config_builder/`** — a systemd timer (04:00 daily) that clones
  `dartagan/dotfiles`, runs `nix flake update`, and builds the `iso`/`steamdeck`/`thenixbeast`
  host configs to warm the cache.
- **`tailscale/`** — joins a self-hosted Tailscale/Headscale control server as an exit node,
  with a sops-templated autoconnect script and UDP-GRO NIC tuning.

## Secrets (sops-nix)

Secrets are `sops`-encrypted YAML, decrypted at activation by `sops-nix`. Recipients are
age keys derived from SSH keys, declared in `.sops.yaml` (`mini-nas` host key plus
`steamdeck`/`thenixbeast` admin keys). Rules there map each `secrets.yaml` path to its key
group.

- `secrets.yaml` — host-wide (root/syncoid SSH keys).
- `tofu_secrets.yaml` — Proxmox API token + user password, read by Terraform via the sops
  provider.
- `modules/*/secrets.yaml` — per-module (attic env file, tailscale login server, builder
  keys).

To add or edit a secret, edit the matching `*.yaml` through `sops`, and ensure the path is
covered by a `creation_rules` entry in `.sops.yaml`. Adding a new decrypting machine means
adding its age key to `.sops.yaml` and re-encrypting (`sops updatekeys <file>`).

## Conventions & gotchas

- **disko does not change a live system.** It only applies on the initial deploy. Changes to
  partitions or ZFS datasets must be done by hand on the host, then reflected back into
  `disk-config.nix` to keep it truthful (see the header comment there). New ZFS datasets also
  need a matching `fileSystems` entry in `configuration.nix` to mount.
- **Keep the disk lists in sync.** The drive list in `disk-config.nix` and the
  `hddfancontrol` list in `configuration.nix` describe the same physical disks.
- Nix `nixpkgs` tracks `nixos-unstable`; `system.autoUpgrade` with `allowReboot` is on, so
  the host updates itself.
