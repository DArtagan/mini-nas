# PBS #2, the offsite copy of vulcanus's guest images, which it pulls over the
# tailnet. Its whole system is built in vulcanus-proxmox's nixos/ flake; this
# host only runs it. A NixOS container rather than a Proxmox one because
# proxmox-nixos cannot start an LXC.
{ inputs, ... }:
let
  datastore = "/rpool/pbs";
  pbsOffsite = inputs.vulcanus-proxmox.nixosConfigurations.pbs-offsite.config;
in
{
  # Declared in disk-config.nix, which disko applies only on a fresh install, so
  # the dataset itself is created by hand on a live host; see the header there.
  fileSystems.${datastore} = {
    device = "rpool/pbs";
    fsType = "zfs";
    options = [ "zfsutil" ];
  };

  # The datastore is owned by PBS's uid inside the container, which the idmap
  # bind passes through unshifted; owned by anything else, PBS cannot write its
  # chunks. `z` rather than `d`: it adjusts what is there and never creates a
  # directory, which would otherwise mask the mount if the dataset were missing.
  systemd.tmpfiles.rules =
    let
      inherit (pbsOffsite.users.users.proxmox-backup-server) uid;
      inherit (pbsOffsite.users.groups.proxmox-backup-server) gid;
    in
    [ "z ${datastore} 0750 ${toString uid} ${toString gid} -" ];

  containers.pbs-offsite = {
    path = inputs.vulcanus-proxmox.nixosConfigurations.pbs-offsite.config.system.build.toplevel;
    autoStart = true;

    # On the LAN by DHCP, and on the tailnet as its own tagged node.
    privateNetwork = true;
    hostBridge = "vmbr0";
    enableTun = true;

    privateUsers = "pick";
    extraFlags = [
      # idmap, so the datastore keeps host uid 350 rather than the container's
      # shifted range; bindMounts has no way to ask for it.
      "--bind=${datastore}:/mnt/pbs:idmap"
      # nspawn's default, auto, mounts this host's America/New_York over the
      # container's /etc/localtime, silently overriding its UTC: PBS's job
      # schedules then run four or five hours late, moving with DST.
      "--timezone=off"
    ];
  };

  systemd.services."container@pbs-offsite" = {
    unitConfig.RequiresMountsFor = [ datastore ];
    # A limit, not an allocation; VM 107's figure until measured.
    serviceConfig.MemoryMax = "2G";
  };
}
