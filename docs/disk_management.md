# Disk replacement

How to replace a disk in `mini-nas`'s ZFS pools.
disk-management runbook, but this host is **NixOS + disko + GRUB**, not stock Proxmox, so a
few things differ (no `proxmox-boot-tool`; boot lives in mirrored GRUB ESPs; and there is
Nix bookkeeping to do afterwards).

## Important note

disko does not touch a live system. The `disk-config.nix` declaration only runs on the
initial bare-metal install. Replacing a disk is a **manual ZFS operation on the host**, and
then you edit the Nix files so they still describe reality. The Nix edit is bookkeeping — it
is not what performs the replacement.

## Layout recap

Disks are addressed by `/dev/disk/by-id/ata-...` serial paths everywhere (pool members, the
`hddfancontrol` list, disko) so `zpool status` and cabling shuffles stay legible. Kernel
`sdX` letters are **not** stable — they had already shuffled the last time this was touched
(`sdh` got reused) — so never key off them.

- **`rpool`** — two `raidz1` vdevs (`raidz1-0`, `raidz1-1`), three disks each. Every rpool
  disk is partitioned:
  - `part1` = **5 G EF00 ESP** (vfat), one of the mirrored GRUB boot copies, mounted at
    `/boot`, `/boot1` … `/boot5`.
  - `part2` = **ZFS**, the pool member.
- **`spool`** — one `raidz1` vdev, two disks. Every spool disk:
  - `part1` = **16 G swap**.
  - `part2` = **ZFS**, the pool member.
- Boot loader is GRUB with `boot.loader.grub.mirroredBoots` writing to `/boot1`…`/boot5`
  (plus the primary `/boot`). Each rpool disk carries an independent, redundant boot copy, so
  losing one disk loses one boot copy, not bootability.
- `autoexpand = on` is already set on both pools (see `disk-config.nix` pool `options`), so a
  vdev grows automatically once **every** member in it is large enough.

### The `/bootN` slot

An rpool disk's ESP mountpoint is determined by its **position** in the flattened `rpoolDisks`
list in `disk-config.nix` (`imap0`: index 0 → `/boot`, 1 → `/boot1`, … 5 → `/boot5`). When
you swap a serial, **keep it in the same list position** so its `/bootN` slot — and the
`mirroredBoots` mapping — don't move.

Current mapping (flattened order in `disk-config.nix`):

| idx | mount   | vdev       | disk serial |
|-----|---------|------------|-------------|
| 0   | /boot   | raidz1-0   | ZGY0B2SR    |
| 1   | /boot1  | raidz1-0   | ZGY8DP80    |
| 2   | /boot2  | raidz1-0   | ZGY0B2RP    |
| 3   | /boot3  | raidz1-1   | Z1F48TA8    |
| 4   | /boot4  | raidz1-1   | YHHT74WA    |
| 5   | /boot5  | raidz1-1   | Z2L4RUPGS   |

## Three lists to keep in sync afterwards

When the physical disks change, update all three or things drift:

1. **`disk-config.nix`** — the serial in `rpoolDisks` / `spoolDisks`. Keep list position for
   rpool disks (see `/bootN` above).
2. **`configuration.nix`** — `services.hddfancontrol.settings.harddrives.disks`.
3. **`configuration.nix`** — `boot.loader.grub.mirroredBoots`, but only if the `/bootN`↔disk
   mapping actually changed (it won't if you kept list position).

## List the drives

```bash
lsblk -o name,size,model,serial,uuid | grep -i sd
ls -l /dev/disk/by-id/ | grep -i ata-        # serial → sdX mapping
zpool status -L rpool spool                  # -L resolves members to sdX; drop -L for GUIDs
```

## Test a new drive before trusting it

## Replacement procedure

Both pools are `raidz1` → a vdev survives **one** missing disk. Replace one disk at a time,
and if you can, do it **in place** (new disk connected alongside, resilvering from the still-
present members) so you keep redundancy throughout. Watch progress in a tmux pane running
`watch -n1 'zpool status -L'`.

### 1. Physically connect and identify the new disk

```bash
ls -l /dev/disk/by-id/ | grep -i <NEW_SERIAL>   # confirm the by-id path and sdX letter
```

### 2. Test it (see above)

`badblocks` is roughly as thorough as a SMART long test. A destructive pass **erases the
disk** — only run it on the incoming blank drive, never a pool member.

```bash
# Destructive (blank drive only). ~a day+ for a 3 TB disk; run under tmux.
badblocks -wsv -b 4096 /dev/sdX

# Non-destructive alternative:
badblocks -nsv -b 4096 /dev/sdX
```

Optional throughput sanity check:

```bash
fio --name=random-write --ioengine=posixaio --rw=randwrite --bs=1m \
    --size=16g --numjobs=1 --iodepth=1 --runtime=60 --time_based --end_fsync=1 /dev/sdX
```

### 3. Partition to match disko's layout

Easiest and least error-prone: **clone the partition table from a healthy sibling** in the
same pool, then regenerate GUIDs and grow the ZFS partition to fill the disk. `sgdisk` isn't
in the system PATH — get it with `nix shell nixpkgs#gptfdisk --command sgdisk ...` (wrap the
whole sequence in one `nix shell ... --command sh -c "..."`).

```bash
GOOD=/dev/disk/by-id/ata-<any-healthy-disk-in-the-same-pool>
NEW=/dev/disk/by-id/ata-<NEW_SERIAL>

sgdisk "$GOOD" -R "$NEW"     # copy the partition TABLE (sizes/types) — not the contents
sgdisk -G "$NEW"            # fresh partition GUIDs on the new disk
sgdisk -e "$NEW"            # move backup GPT header to the true end (if new disk is bigger)
sgdisk -d 2 "$NEW"          # delete the ZFS partition record (part2)…
sgdisk -N 2 "$NEW"          # …and recreate it filling all remaining space
# partprobe is unavailable; the kernel keeps the old table until reboot, but udev
# re-reads the on-disk GPT for the by-partlabel symlinks used below:
udevadm trigger --subsystem-match=block; udevadm settle
```

(Both rpool and spool disks have ZFS on `part2`, so `-d 2 / -N 2` is correct for either.
Cloning from a same-pool sibling reproduces the 5 G ESP / 16 G swap `part1` automatically.)

> **⚠️ CRITICAL — fix the partition names (PARTLABELs), or `/bootN` breaks.**
> `sgdisk -R` also copies the sibling's GPT **partition names**, and `sgdisk -G` only
> randomizes GUIDs, **not** names. disko mounts the ESPs **by-partlabel**, so leaving the
> cloned names duplicated makes `/dev/disk/by-partlabel/<label>` ambiguous — udev will steal
> the sibling's ESP device and its `/bootN` silently unmounts (you won't notice until the
> next deploy fails installing GRUB with `error: unknown filesystem`). You must rename the new
> disk's two partitions to the **unique labels disko expects**.
>
> disko derives those labels from the disk's by-id path, so **do the `disk-config.nix` serial
> swap first** (Step 6's edit), then read the expected labels straight from the evaluated
> config and stamp them on:
>
> ```bash
> # On the workstation (repo checked out, disk-config.nix already updated to NEW serial):
> ESP=$(nix eval --raw ".#nixosConfigurations.mini-nas.config.fileSystems.\"/bootN\".device")
> ESP=${ESP#/dev/disk/by-partlabel/}                                  # -> part1 label
> Z=$(nix eval --raw ".#nixosConfigurations.mini-nas.config.disko.devices.disk.\"$NEW\".content.partitions.zfs.label")
>
> # On the host, stamp the disko labels onto the new disk:
> sgdisk -c 1:"$ESP" "$NEW"      # part1 (ESP) name
> sgdisk -c 2:"$Z"   "$NEW"      # part2 (zfs) name
> udevadm trigger --subsystem-match=block; udevadm settle
>
> # verify: the sibling's label points back at the sibling, new labels at the new disk:
> ls -l /dev/disk/by-partlabel/ | grep -E "part1-or-part2 labels of interest"
> ```
>
> (For a **spool** disk the swap partition is `part1`; check
> `...partitions.swap.label` / the relevant `fileSystems` entry instead.)

### 4. Swap it into the ZFS pool

Always operate on **`-part2`**. Reference the outgoing disk by its **by-id path if it still
resolves**, or by the **GUID from `zpool status`** if the label is gone (a hard-failed disk
shows as a bare number, e.g. `3358304228250452939  FAULTED  ... was /dev/sdh2`).

```bash
zpool replace <pool> <old-by-id>-part2   /dev/disk/by-id/ata-<NEW_SERIAL>-part2
#           …or…
zpool replace <pool> <OLD_GUID>          /dev/disk/by-id/ata-<NEW_SERIAL>-part2

watch -n1 'zpool status -L'      # wait for resilver to finish, 0 errors
```

### 5. rpool only — restore the boot ESP

spool disks have swap on `part1` (nothing to do; it gets picked up on next boot / after the
deploy). rpool disks carry a GRUB boot copy on `part1` that must be recreated on the new disk
and mounted at the **same `/bootN` slot** the old disk used.

```bash
SLOT=/bootN                                   # the slot for this disk's list index
umount "$SLOT" 2>/dev/null || true            # unmount the dead disk's ESP if still mounted
mkfs.vfat -F 32 /dev/disk/by-id/ata-<NEW_SERIAL>-part1
mount /dev/disk/by-id/ata-<NEW_SERIAL>-part1 "$SLOT"
```

The GRUB copy itself is written by the **Step 6 deploy** (`switch-to-configuration` installs
into every `/bootN`). It does **not** auto-mount changed/new ESPs, so **every one of the six
`/bootN` must be mounted before you deploy** — otherwise GRUB installs into a bare ZFS
directory and fails with `error: unknown filesystem`. Confirm first:

```bash
findmnt -no TARGET,SOURCE /boot /boot1 /boot2 /boot3 /boot4 /boot5   # expect all six
```

### 6. Update the Nix files (bookkeeping) and deploy

Edit the three lists above (swap the serial in `disk-config.nix` keeping list position, and
in the `hddfancontrol` list), then deploy so the config permanently reflects reality:

```bash
nh os switch .#nixosConfigurations.mini-nas --target-host "root@192.168.1.11"
# or: deploy .#mini-nas
```

### 7. Reassemble / verify

If you opened the case, note the order in `zpool status` and arrange disks so the serial
stickers match that order — it makes finding a faulted drive in future trivial. Use locking
SATA cables. Then:

```bash
zpool status -L        # all vdevs ONLINE, no errors
bootctl status || efibootmgr    # sanity-check boot entries (optional)
```

### autoexpand note

`autoexpand=on` is already configured, so a vdev grows on its own once **all** of its members
are the larger size. If it doesn't pick up after replacing the last small disk in a vdev:

```bash
zpool online -e <pool> /dev/disk/by-id/ata-<SERIAL>-part2   # per member in the vdev
```

---

## Worked example — July 2026: `Z1F48TA8` → `00038E07`

The old `ST3000DM001` (`Z1F48TA8`, 3 TB) in **`raidz1-1`** hard-failed — label missing, shows
as GUID `3358304228250452939` ("was /dev/sdh2"). Its list index is **3 → `/boot3`**. The
replacement is `ata-OOS3000G_00038E07` (3 TB, same size, `/dev/sdc` when queried). This was
resolved with the actual labels below — note the partlabel-rename step, whose omission the
first time caused the sibling's `/boot4` to unmount and the deploy to fail on GRUB install.

```bash
NEW=/dev/disk/by-id/ata-OOS3000G_00038E07
GOOD=/dev/disk/by-id/ata-Hitachi_HUA723030ALA641_YHHT74WA   # healthy sibling in raidz1-1

# 1. (done manually here) test the new disk — destructive, blank disk only
badblocks -wsv -b 4096 /dev/sdc

# 2. clone partition layout onto the new disk (sgdisk via nix shell)
nix shell nixpkgs#gptfdisk --command sh -c '
  sgdisk "'"$GOOD"'" -R "'"$NEW"'"; sgdisk -G "'"$NEW"'"; sgdisk -e "'"$NEW"'"
  sgdisk -d 2 "'"$NEW"'"; sgdisk -N 2 "'"$NEW"'"'
udevadm trigger --subsystem-match=block; udevadm settle

# 3. bookkeeping FIRST (so disko can compute this disk's labels): in disk-config.nix
#    swap ...ST3000DM001-1CH166_Z1F48TA8 (index 3, keep position) -> ...OOS3000G_00038E07,
#    and the same in the hddfancontrol list. Then stamp disko's unique partlabels on:
#      /boot3 (part1) label -> f569de41a8187b7aa8770e3ae28a02a5f21e
#      part2 (zfs)   label -> 5ba847bb0a96a4e11d46547afa9d9a01f2aa
nix shell nixpkgs#gptfdisk --command sh -c '
  sgdisk -c 1:f569de41a8187b7aa8770e3ae28a02a5f21e "'"$NEW"'"
  sgdisk -c 2:5ba847bb0a96a4e11d46547afa9d9a01f2aa "'"$NEW"'"'
udevadm trigger --subsystem-match=block; udevadm settle
# sanity: fda9ead6…(sibling ESP)->sdb1, f569de41…->sdc1, both distinct
ls -l /dev/disk/by-partlabel/ | grep -E "fda9ead6|f569de41|5ba847bb|2c20f9b7"

# 4. replace the FAULTED member (by GUID — its label/by-id is gone) and resilver
zpool replace rpool 3358304228250452939 "${NEW}-part2"
watch -n1 'zpool status -L'      # wait for resilver, 0 errors (took ~3 days here)

# 5. restore the /boot3 ESP, and make sure ALL six /bootN are mounted before deploying
mkfs.vfat -F 32 "${NEW}-part1"
mount /dev/disk/by-partlabel/f569de41a8187b7aa8770e3ae28a02a5f21e /boot3
mount /dev/disk/by-partlabel/fda9ead67f544eebc5e2abb5b19bda62fe82 /boot4  # remount sibling if it dropped
findmnt -no TARGET,SOURCE /boot /boot1 /boot2 /boot3 /boot4 /boot5        # expect all six

# 6. deploy (installs GRUB to every ESP incl. the new /boot3) and verify
nh os switch .#nixosConfigurations.mini-nas --target-host "root@192.168.1.11"
zpool status -x rpool            # "pool 'rpool' is healthy"
```
