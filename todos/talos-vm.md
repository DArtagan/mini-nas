# A single-node Talos VM for home services

## Opening prompt

> mini-nas has no Kubernetes yet. Will chose a single-node Talos VM on Proxmox,
> running Cilium, Flux and a few home services. Three things are in scope
> alongside it:
> - replacing the host's `system.autoUpgrade`, which has never worked, with a
>   nightly pipeline that builds, verifies, commits and switches
> - backups for the cluster
> - an off-host copy of the backups, pushed to vulcanus
>
> Read `todos/talos-vm.md`. It carries the decisions, the measured disk latency,
> the etcd write budget, and the Cilium tuning that keeps it small. Work through
> its plan in order, in a worktree. The host-upgrade pipeline can go first, as its
> own PR.

Written **2026-10-21**, and revised **2026-10-22**, **2026-10-26** and
**2026-10-27** with Will's answers. Host facts were read from mini-nas over SSH on those days. The fsync
figures were measured on the evening of 2026-10-21 (21:38–21:52 EDT, between
the hourly syncoid runs). Cilium's behaviour was read from its v1.20.1 source and
docs on 2026-10-25. Nothing Talos-related has run on this host yet, so everything
under [Plan](#plan) is plan.

## Decided

Will's calls, 2026-10-21 to 2026-10-26.

**Platform**

- **Talos in a Proxmox VM**, not native k3s with or without gVisor. The reason
  is the threat model. On native k3s, anything that can create a privileged or
  `hostPath: /` pod is root on mini-nas. That could be a chart, an operator, a
  leaked service-account token or a mistake. mini-nas holds:
  - the sops host key, which decrypts every secret in this repo
  - the syncoid key into vulcanus
  - attic's signing key, which can poison every host substituting from the cache
  - the backups in `rpool/foreign-backups` and `rpool/pbs`
  - an exit node's place on the tailnet

  In the VM, cluster-admin is root on the VM.
- **It runs real home services**, not a lab. They're listed under
  [Workloads](#the-first-workloads).
- **No SSD**, now or soon. The board's only M.2 slot holds the ASM1166 SATA card
  that four of rpool's disks hang off.
- **Not `sync=disabled`.** vulcanus rejected it too (`todos/etcd-disk-latency.md`
  there).
- **VT-x can be turned on at the next reboot.**
- **16 GB is the board's physical limit.**
- **No OpenTofu.** It was removed from this repo in #6 (`7432134`). Everything
  that had been tofu here becomes Nix, `talosctl`, Flux, or a documented
  command; see [Without tofu](#without-tofu).

**Storage and backups**

- **Spool now, rpool later.** The VM's disks go on spool, and move to rpool
  before spool is retired. That will probably come with rpool growing to two
  4-disk raidz1 vdevs.
- **When the vdevs are reworked, the new disks need swap partitions.** All the
  host's swap is on spool's disks; see [The move to rpool](#the-move-to-rpool).
- **A boot disk and a separate data disk.** The boot disk holds Talos's
  EPHEMERAL partition, which carries etcd and container images. The data disk
  holds volumes.
- **Volumes are OpenEBS LocalPV hostpath on the data disk, backed up by K8up
  (restic), as on vulcanus.** The data disk carries `backup=0`, and vzdump images
  only the boot disk.
- **The off-host copy is pushed to vulcanus, not pulled by it.** If vulcanus
  pulled, it would hold a credential into mini-nas, which is vulcanus's own
  offsite copy, so a compromised vulcanus could reach its own backups. Only the
  restic repository goes off-host; see [Backups](#backups).

**Cluster**

- **Cilium as the CNI, tuned for etcd's write budget**; see
  [Cilium](#cilium-and-the-etcd-write-budget). Will preferred it over Flannel
  with kube-network-policies.
- **gVisor for the agent pods**, enforced by admission.
- **GitOps with Flux, with the manifests in this repo.**
- **Monitoring stays light:** metrics-server plus a few targeted checks that
  alert through Pushover (`pushover-notifications.md`). No time-series database.
- **The tailnet is reached through the Tailscale Kubernetes operator**, once
  Headscale 0.30 allows it; see [Reach](#reach).
- **The VM may reach nothing on the host**, except ports opened one by one when
  something needs them.
- **Leader election is off wherever it can be**; see
  [the etcd write budget](#cilium-and-the-etcd-write-budget).
- **Addresses:** the node gets `192.168.1.190`, and LoadBalancer services get
  `192.168.1.201–210`. Adding the router reservation, against a made-up MAC, is
  part of bringing each service up; see [Addresses](#addresses).
- **Mosquitto is cluster-internal** unless a device outside the cluster needs
  MQTT; see [the first workloads](#the-first-workloads).
- **The agents get the open internet and nothing private**, because research
  takes them to domains nobody can list in advance; see
  [the first workloads](#the-first-workloads).
- **Host upgrades:** build, verify, then commit, with a hold-back watchlist and
  a Sunday 01:30 reboot window (Will, 2026-10-27); see
  [Host upgrades](#host-upgrades).
- **The web stack is hypothetical and out of scope.** It is budgeted as Flask
  plus Postgres.

**In scope alongside the VM**

- **Unattended host upgrades** that land as commits, replacing
  `system.autoUpgrade`; see [Host upgrades](#host-upgrades).
- **Backups for the cluster**, with the off-host push.

## Considered and set aside

- **Native k3s on its SQLite datastore.** It uses about 0.5 GB less memory and
  avoids etcd. Rejected on the threat model.
- **Native k3s with gVisor.** Rejected on the same grounds. gVisor does return,
  inside the VM, for the agent pods.
- **A NixOS VM running k3s.** It isolates as well as Talos does, has no etcd and
  uses about 0.5 GB less. Talos was preferred for its immutable, API-driven OS.
  **This is the fallback if the [memory budget](#memory-budget) fails.**
- **k3s in LXC or systemd-nspawn.** It shares the host's kernel, and
  proxmox-nixos can't start an LXC (`modules/pbs_offsite`).
- **RKE2, kubeadm, `services.kubernetes`.** All of them run etcd plus more moving
  parts, for no gain here.
- **Flannel plus kube-network-policies, with an allowlisting egress proxy for
  the agents.** It was lighter and writes nothing to etcd. Will chose Cilium for
  its domain-aware policy, Gateway API and flow visibility, on condition that its
  write load could be tuned down, which is what
  [Cilium](#cilium-and-the-etcd-write-budget) does.
- **A domain allowlist for the agents.** Researching on the internet takes them to
  domains nobody can list in advance (Will, 2026-10-27). The isolation comes
  from denying everything private instead.
- **MetalLB.** Its L2 mode coordinates over memberlist and writes no Leases.
  Cilium's L2 announcements do the same job without another component, at one
  tuned Lease per announced service.
- **vulcanus pulling the off-host copy.** See the push decision above.
- **Sending the PBS images off-host as well.** The boot disk can be rebuilt from
  this repo, `talosctl` and a restic restore. A PBS-to-PBS link would be a second
  credential into vulcanus to buy something that can be rebuilt.
- **"Build and switch to the latest" for host upgrades.** Then the host would run
  a lock that isn't in git; see [Host upgrades](#host-upgrades).
- **A subnet route through mini-nas, for the tailnet.** It would keep tailnet
  credentials out of the cluster. Will chose the operator's per-service
  identities. It is still the stopgap if a service needs the tailnet before
  Headscale 0.30.
- **vzdump for the volume data as well.** A host reboot drops QEMU's dirty
  bitmap, so the next vzdump reads the whole disk, and the data disk is the
  large one.
- **`primarycache=metadata` on the boot disk.** The guest writes 4K blocks into
  16K volblocks, and a partial write to a block that isn't in the ARC has to read
  the rest of the block first. That puts a platter read in front of every fsync.
  It's a candidate only for the data disk, after measuring.
- **Cilium's `disableEndpointCRD`.** On one node with stable pods,
  CiliumEndpoints write only when pods start and stop. The operator's identity GC
  also judges liveness from CiliumEndpoints, and skips the GC only when the CRD is
  absent (`operator/identitygc/crd_gc.go`), so turning them off risks churning
  identities. Not worth that without a measurement saying they matter.

## The host, verified 2026-10-21 to 26

| | |
|---|---|
| CPU | i7-4790K: Haswell, 4 cores, 8 threads. Supports x86-64-v3 (AVX2, BMI2, FMA, MOVBE). |
| VT-x | **Off.** `/proc/cpuinfo` has no `vmx` flag and there is no `/dev/kvm`. The BIOS can be reached through the JetKVM attached over USB. |
| KVM module | Not loaded. nixos-facter adds `kvm-intel` to `boot.kernelModules` only when `facter.json` lists `vmx` (`modules/nixos/virtualisation.nix:63` in nixos-facter-modules), and it doesn't. |
| Board | ASUS Maximus VII Impact: two DDR3 slots, each with 8 GB. DMI claims four slots and 32 GB, but that is the chipset's template. |
| Memory | 15 GiB visible. On 2026-10-21, 7.2 GiB was available, with the ARC at its 6 GiB cap (`configuration.nix:101`) and a 99.4% hit ratio since boot. **On 2026-10-26 one build had taken all of it**; see [the memory incident](#the-memory-incident-2026-10-26). |
| Swap | Two 16 GiB partitions, `part1` of each spool disk. |
| spool | raidz1 of two TOSHIBA DT01ACA200 (7200 rpm). 1.74 TiB available, holds nothing. ashift 12, lz4, `sync=standard`. Interim capacity: see `configuration.nix:107`. |
| rpool | 83% full, 37% fragmented, 1.93 TiB available. |
| Proxmox | proxmox-ve 9.2.10, which has never had a guest. `qm list` is empty, `pvesm status` shows only `local` (dir), and `/etc/pve/storage.cfg` doesn't exist. `pct` fails with a Perl `@INC` error; `qm` runs. `pve-guests.service` runs `startall` at boot and `pve-guests-stop` on shutdown. `/etc/pve/vzdump.cron` holds no jobs. |
| PBS #2 | A NixOS container from the vulcanus-proxmox flake (`modules/pbs_offsite`), on the LAN by DHCP and on the tailnet as its own node. Its datastore `rpool/pbs` holds vulcanus's guest images. `MemoryMax=1G`. |
| Network | `vmbr0` holds `192.168.1.11` statically (`proxmox.nix`). The gateway and DNS are `192.168.1.1`. The router keeps `.11` out of its pool and leases from at least the low `.30`s: PBS #2 got `.35`, and `.31` is in use. thenixbeast and steamdeck are `.10` and `.12`. |
| Kernel | Booted 6.18.45. The current system has 6.18.55. |
| autoUpgrade | Fails every night; see [Host upgrades](#host-upgrades). |
| ZFS | 2.4.4, with `zfs_immediate_write_sz` at 32768 and `zfs_txg_timeout` at 5. |
| Open on all interfaces | sshd 22, rpcbind 111, spiceproxy 3128, hddtemp 7634, pveproxy 8006, atticd 8770. |
| Tooling | devenv provides `age`, `git`, `nixos-anywhere` and `sops`. It provides neither `talosctl`, `kubectl`, `flux`, `helm` nor `cilium`. |

### The memory incident, 2026-10-26

At midnight the host had 710 MiB available and 19 GiB of swap in use, and the
ARC had been squeezed to 500 MiB. Load was about 5. The cause was **a single
`rustc` at 12.4 GiB RSS, compiling `qbz-2.0.2`.** `nightly_config_builder` had
started it at 05:07 on 2026-10-25 while building the `steamdeck` config, and it
had been running for 18 hours, thrashing swap. It built on mini-nas, even though
the same run sent other derivations to `ssh-ng://nix@thenixbeast.forge.local`.
**Why it didn't go to thenixbeast is unverified.** nix-daemon has no memory
limit (`MemoryMax=infinity`).

With Will's go-ahead, the builder unit was stopped and its nix-daemon worker
(pid 1464116) sent SIGTERM. Within two minutes, 12 GiB was available and swap
was down to 1.9 GiB.

What it means here:
- **With the VM running, that build would have pushed guest RAM out to swap on
  spool**, the disks etcd fsyncs to.
- **The VM's memory has to be protected from host builds**, and host builds have
  to be capped, before the VM exists. That is plan step 3.

The next night's run (2026-10-26, 04:00) finished in 31 minutes without
rebuilding `qbz`, so it didn't come back.

## Sync-write latency, measured

This is etcd's documented disk check: fio writing 2,300-byte blocks
sequentially, with an `fdatasync` after each one, 22 MiB in all. It ran on a
temporary dataset on each pool and on a 1 GiB zvol on spool with
`volblocksize=16K`. All three were destroyed afterwards.

```sh
fio --name=etcd --rw=write --ioengine=sync --fdatasync=1 --size=22m --bs=2300 \
  --directory=<dataset mountpoint>     # or --filename=/dev/zvol/<zvol>
```

| 10,029 fsyncs each | p50 | p90 | p99 | p99.9 | max |
|---|---|---|---|---|---|
| spool dataset | 8.29 ms | 8.36 ms | 35.4 ms | 62.7 ms | 147 ms |
| spool zvol, 16K | 8.29 ms | 8.45 ms | 40.6 ms | 60.6 ms | 147 ms |
| rpool dataset | 10.2 ms | 15.8 ms | 97.0 ms | 265 ms | 402 ms |

What the numbers say:

- **The 8.3 ms median is one revolution of a 7200 rpm disk** (60/7200 s). Every
  fsync waits for the ZIL block to come round under the head. No tuning inside
  etcd moves that floor. What tuning can do is **cut how many fsyncs etcd is
  asked for**, which is the point of the write budget below.
- **Both pools miss etcd's target**, which is p99 under 10 ms. spool is about 4×
  over. rpool is about 10× over, and its tail is about four times worse again.
- **The zvol performs like the dataset.** Writes this small fall under
  `zfs_immediate_write_sz`, so their data is copied into the ZIL record.
- **These are host-side figures, taken at a quiet moment.** The number that
  matters is `etcd_disk_wal_fsync_duration_seconds` from inside the VM; see
  [Verifying](#verifying).
- **Several things will compete for spool's two disks:** the workloads on the
  data disk, host swap on `sda1`, the monthly scrub (`zfs-scrub.service` scrubs
  both pools), and vzdump reading the boot disk. vulcanus's stalls came from this
  kind of contention, not from etcd's own load.

## Cilium and the etcd write budget

On vulcanus, about 3.9 of etcd's roughly 4.1 writes per second were Lease
renewals: coordination between components that, on one node, have nothing to
coordinate with (`todos/etcd-disk-latency.md` and `docs/talos.md` there). Every
one of them is a synchronous WAL fsync on spinning disks. Here, the same writes
are the thing to remove.

**How a Lease costs writes.** Every component here uses client-go's
leaderelection:
- **The holder renews once per `retryPeriod`.** That alone sets the write rate.
  vulcanus measured the same thing.
- **`renewDeadline`** is how long a failing renewal keeps retrying before the
  holder gives up (the component exits).
- **`leaseDuration`** is how long another candidate waits before taking over an
  unreleased lease.
- client-go requires `renewDeadline` > 1.2 × `retryPeriod`, and `leaseDuration`
  > `renewDeadline`. Cilium's code enforces the same (`pkg/l2announcer/l2announcer.go`).

Cilium's docs describe `l2announcements.leaseRenewDeadline` as "the interval at
which the leader will renew the lease". **That is wrong:** the code hands all
three values straight to `leaderelection.RunOrDie`, so `leaseRetryPeriod` is the
interval.

**Both of Cilium's leases set `ReleaseOnCancel: true`** (`l2announcer.go`,
`operator/cmd/root.go`). A graceful restart releases the lease at once, so a long
`leaseDuration` delays only recovery from a crash.

### The writers, and what each gets

| Writer | Default | Here | Writes/s, default → here |
|---|---|---|---|
| kube-controller-manager lease | 15/10/2 s | election off: `cluster.controllerManager.extraArgs.leader-elect: "false"` | 0.5 → 0 |
| kube-scheduler lease | 15/10/2 s | election off: `cluster.scheduler.config.leaderElection.leaderElect: false`. Talos ignores `--leader-elect` in `scheduler.extraArgs`. | 0.5 → 0 |
| cilium-operator lease | 15/10/2 s, and **2 replicas** | `operator.replicas: 1`; `--leader-election-lease-duration=60s`, `--leader-election-renew-deadline=45s` and `--leader-election-retry-period=15s` through `operator.extraArgs`. It has no flag to turn election off. | 0.5 → 0.07 |
| Cilium L2 announcement, one Lease per announced service | 15/5/2 s | `l2announcements.leaseDuration: 60s`, `leaseRenewDeadline: 45s`, `leaseRetryPeriod: 15s` | 0.5 → 0.07 each |
| Flux controllers (source, kustomize, helm, notification) | election on (vulcanus doesn't record their timings) | `--enable-leader-election=false` on each, through a kustomize patch in `flux-system` | several × 0.2–0.5 → 0 |
| OpenEBS LocalPV provisioner | election on, with the legacy endpointsleases lock (2 objects per renewal, every ~2 s on vulcanus) | `enableLeaderElection: false`, as on vulcanus | ~1.2 → 0 |
| K8up operator | election on | `k8up.enableLeaderElection: false`, as on vulcanus | → 0 |
| Tailscale operator, metrics-server, the agents' own controllers | unknown | find each one with the `renewTime` sampler below, and turn it off or widen it | — |
| kubelet node lease | renewed every 10 s (a quarter of `nodeLeaseDurationSeconds`, 40 s) | **leave.** Lengthening it needs `node-monitor-grace-period` raised in step, or the node flaps NotReady. | 0.1 |
| kube-apiserver identity lease | renewed every 10 s | leave | 0.1 |

**What the table leaves:** about 0.2 lease writes per second from kubelet and
the apiserver, plus about 0.07 per announced service and for the Cilium
operator. That's roughly 0.4 writes/s with three announced services, against
vulcanus's 4.1. Status updates, Events and pod churn come on top. These figures
are arithmetic from the settings, not a measurement. **Measure the real figure
before calling it done** (see [Verifying](#verifying)). vulcanus's lesson was
that the demand, not the disk, was the lever.

**The cost of the slow leases:** if the Cilium agent crashes rather than
restarting gracefully, announced IPs stay dark for up to 60 s. If the operator
crashes, its successor waits up to 60 s. A failed renewal is retried every 15 s
for 45 s. One attempt times out after `renewDeadline`/2 (`operator/cmd/root.go`),
so a stall of up to about 22 s is survived. vulcanus's worst recorded fsync stalls
reached about 8 s.

**If a second control-plane node ever joins**, election has to come back on for
the components above.

### The rest of Cilium's configuration

- **Talos's requirements** (docs.siderolabs.com, "Deploying Cilium", read
  2026-10-25):
  - `ipam.mode: kubernetes`
  - `kubeProxyReplacement: true`, with Talos's `cluster.proxy.disabled: true`
  - `k8sServiceHost: localhost` and `k8sServicePort: 7445` (KubePrism)
  - `cgroup.autoMount.enabled: false` and `cgroup.hostRoot: /sys/fs/cgroup`
  - the agent's capability list without `SYS_MODULE`
  - CNI set to none before bootstrap. The patch syntax changed at Talos v1.14,
    so follow the docs for the version in use.

  `ipam.mode: kubernetes` also avoids cluster-pool's CiliumNode allocation
  updates.
- **Identities are CRD-backed** (the default). They're written only when a new
  set of identity-relevant labels appears, so steady state is near zero.
- **Gateway API through Cilium's Envoy** is the ingress. That replaces a separate
  ingress controller; ingress-nginx is retired upstream (vulcanus's
  `todos/ingress-nginx-migration-prompt.md`). Envoy also serves any L7 policy.
  Domain-based egress (`toFQDNs`) runs through the agent's own DNS proxy.
- **Hubble** writes nothing to etcd. Run the relay and UI on demand, not
  permanently, to save memory.
- **`k8sClientRateLimit`** caps request bursts. It doesn't reduce steady-state
  writes, so leave it.
- **Bootstrap:** nothing runs until there's a CNI, Flux included. So install
  Cilium once with `helm install`, using the values Flux will carry, and let a
  Flux HelmRelease with the same name and namespace adopt it. Not Talos
  `inlineManifests`: Talos re-applies those on `upgrade-k8s`, which would fight
  Flux.
- **gVisor with Cilium:** runsc's sandbox sits behind the pod's ordinary veth,
  where Cilium enforces policy, so the two should compose. **Unverified**; the
  [Verifying](#verifying) checks cover it.

## What else carries over from vulcanus

Sources in `~/repositories/vulcanus-proxmox`: `docs/talos.md`,
`todos/etcd-disk-latency.md` and `terraform/modules/proxmox_talos_vm/`.

1. **Size memory against the apiserver's peak, not its average.** vulcanus's
   kube-apiserver peaks around 1.33 GiB resident with 158 resource types (102
   CRDs). Talos, etcd, kubelet and containerd add about 560 MiB outside any pod.
   **Every operator adds CRDs, and Cilium adds about a dozen**, so each costs
   apiserver memory as well as its own. If memory gets tight, use `GOMEMLIMIT`
   through `cluster.apiServer.env`, never a hard `limits.memory`.
2. **Ballooning is off, so memory changes need a QEMU restart.** Judge memory by
   `MemAvailable`, not by `kubectl top node`, which counts page cache.
3. **`discard` on every virtio disk, plus a monthly fstrim CronJob**
   (`kubernetes/infrastructure/fstrim.yaml` there). Talos runs no fstrim timer.
4. **vzdump:**
   - **Use `--performance max-workers=2`.** The number of scattered reads in
     flight is what hurts etcd.
   - **A QEMU process restart drops the dirty bitmap**, and a host reboot is
     one. So every kernel update buys a full read of the boot disk at the next
     backup, which a small boot disk keeps cheap. A `talosctl reboot` from inside
     the guest keeps the bitmap.
   - **Don't try `ionice`.** Neither QEMU's backups (issued over QMP) nor ZFS's
     I/O scheduler see it.
5. **`cpu.type = host`, never a `-cpu` in `args`.** QEMU takes the last `-cpu` it
   is given, silently.
6. **K8up dumps SQLite before backing it up**, rather than copying a live
   database file (`kubernetes/apps/headscale/backups.yaml` there). Home
   Assistant, No Longer Evil and the agents all keep SQLite, and the web stack's
   Postgres gets a `pg_dump` the same way.

Also learned there: defragmenting etcd changed nothing measurable, and a single
5-minute sample of a p99 isn't a measurement, so compare averaged windows.

## The first workloads

From Will, 2026-10-22:

- **Home Assistant** wants `hostNetwork` for mDNS and SSDP discovery. Inside the
  VM, that's the VM's own network namespace, so it stays inside the isolation
  boundary. Its namespace needs a Pod Security exception for `hostNetwork`.
- **No Longer Evil** ([NoLongerEvil-SelfHosted](https://github.com/codykociemba/NoLongerEvil-SelfHosted)
  v1.0.1, read 2026-10-22) emulates Nest's cloud. It has a device API on 8000
  and a control API on 8082, and keeps SQLite. `API_ORIGIN` must be reachable
  from the thermostat, and changing it means re-pointing the thermostat, so **it
  gets a LoadBalancer address that doesn't depend on the node's**. It talks to
  Home Assistant through **an MQTT broker**, so Mosquitto joins the list. Keep
  the control API off the tailnet.
- **Mosquitto**, the MQTT broker. MQTT is a small publish/subscribe protocol:
  devices publish state to topics on a broker (`nolongerevil/<device>/...`), and
  subscribers such as Home Assistant receive it and publish commands back. Home
  Assistant also learns new devices from discovery messages on it. Here, the
  publisher (No Longer Evil) and the subscriber (Home Assistant) are both in the
  cluster, so **the broker is a ClusterIP Service with no LAN address**. It would
  need `192.168.1.205` only if a device outside the cluster spoke MQTT. Examples:
  - Zigbee2MQTT on a separate box with a Zigbee radio
  - plugs flashed with Tasmota
  - Shelly devices in MQTT mode
  - ESPHome devices set to MQTT instead of their native API
  - Frigate on another machine

  A Zigbee radio plugged into mini-nas wouldn't count, because its USB would be
  passed through to the VM and Zigbee2MQTT would run in the cluster. When a LAN
  publisher arrives, it gets `.205`, its own credentials and a topic ACL in
  Mosquitto.
- **pi agents**, each in its own pod, coordinating through Pi Durable. They run
  commands a model writes, so:
  - they run under **gVisor**: the `siderolabs/gvisor` extension and a `gvisor`
    RuntimeClass, enforced on their namespace by a ValidatingAdmissionPolicy,
    because a pod can simply leave the field off
  - no service-account tokens, and Pod Security `restricted`
  - **the public internet, and nothing private.** They need many domains to
    research solutions, so the agents' namespace is default-deny with three
    allows:
    - DNS to kube-dns, with a Cilium DNS rule `matchPattern: "*"` that allows
      every name but routes the lookups through the agent's DNS proxy, so every
      domain an agent resolves is visible
    - `toCIDRSet` `0.0.0.0/0`, except `10.0.0.0/8`, `172.16.0.0/12`,
      `192.168.0.0/16`, `100.64.0.0/10` (the tailnet), `169.254.0.0/16` and
      `127.0.0.0/8`
    - `::/0`, except `fc00::/7` (the tailnet's `fd7a:115c:a1e0::/48` is inside it)
      and `fe80::/10`

    The node, the host and other pods are Cilium identities rather than CIDRs,
    so the CIDR rule never selects them; default-deny keeps them out. Pod and
    Service ranges sit in `10.0.0.0/8` regardless.
  - **the remaining risk is what they could carry out.** An agent that is
    steered (prompt injection from a page it reads) can send whatever it holds
    to anywhere on the internet, DNS included. So:
    - **hold as little as possible**: a model API key of its own with a spend
      limit, and tokens scoped to one repository at a time
    - **don't share volumes** between agents
    - **cap egress bandwidth** per pod (`kubernetes.io/egress-bandwidth`, through
      Cilium's bandwidth manager), so a hijacked agent can't be turned against
      others at line rate
    - **keep a record**: export the agents' DNS flows to a file with Hubble's flow
      exporter, filtered to their namespace, so there's a log of every domain
      they reached

    A gateway that holds the model keys, so agents carry only a revocable token
    (LiteLLM, for instance), would shrink the first item further. It costs a
    few hundred MiB, so it waits until the agent design calls for it.

  Why gVisor inside a VM: the VM keeps the cluster away from mini-nas, but pods
  share Talos's kernel. A kernel escape from an agent would reach Flux's SOPS key,
  K8up's restic credentials, the Tailscale operator's OAuth secret, and Home
  Assistant's control of the house.
- **Pi Durable** ([README](https://github.com/badlogic/pi-mono/blob/main/packages/durable/README.md),
  read 2026-10-22) is experimental: its API changes without notice. It states
  "One process owns a storage at a time; there is no cross-process locking." So
  each agent pod gets its own SQLite on its own volume (never NFS), and agents in
  separate pods coordinate through something else. That's the agents' design, not
  this spec's.
- **The web stack** is hypothetical and out of scope. It's budgeted as Flask
  (gunicorn, 2 workers, about 100–150 MiB) plus Postgres (about 150–250 MiB).
  Postgres's commits fsync to spool, alongside etcd.

## Addresses

The LAN is `192.168.1.0/24`. The router can only reserve one address at a time,
not a block. So the scheme below is a convention, and reserving each address is
part of the SOP for bringing a service up.

It **mirrors vulcanus's last octets** (control plane `.190`, LoadBalancer pool
`.201–210`, internal ingress `.203`), so each number means the same thing at
both sites:

| Address | What |
|---|---|
| `192.168.1.190` | the Talos node (its DHCP reservation, against the VM's MAC) |
| `192.168.1.201–210` | Cilium LB-IPAM pool, announced by Cilium L2 |
| `192.168.1.203` | the Gateway, for every HTTP service |
| `192.168.1.204` | No Longer Evil's device API |
| `192.168.1.205` | Mosquitto, only if a device outside the cluster needs MQTT |

Each is pinned on its Service with `lbipam.cilium.io/ips`, so an address never
moves. None of `.190` or `.200–210` answered ARP on 2026-10-26, and the router
was leasing in the low `.30`s.

**SOP for a new LoadBalancer address:**
1. Pick the next free address in `.201–210`.
2. Check nothing answers: `ping -c1 <ip>` from the host, then `ip neigh show
   <ip>` should read FAILED.
3. Reserve it in the router.
4. Pin it on the Service.
5. Record it in the table in `docs/`.

**Reserve each LoadBalancer address against a made-up MAC.** It has no MAC of
its own, because Cilium answers ARP for it with the node's MAC, and the router
reserves against MACs. Will confirmed on 2026-10-27 that it accepts a MAC it has
never seen. Use a locally administered MAC that encodes the address:
`02:00:c0:a8:01:` plus the last octet in hex, so `.204` is `02:00:c0:a8:01:cc`.
That makes step 3 of the SOP "reserve `.N` against `02:00:c0:a8:01:<N in hex>`".
The made-up MAC never appears on the wire; it only keeps the router from leasing
the address.

## Reach

- **The Tailscale operator waits on Headscale 0.30.0.** It authenticates with
  OAuth client credentials, which 0.30.0 adds (#3334: "This lets the Tailscale
  Terraform provider and Kubernetes operator drive Headscale unchanged"). 0.30.0
  was unreleased on 2026-10-22; vulcanus runs v0.29.5 and tracks the release in
  its `todos/headscale-0-30.md`. Until then, services are LAN-only.
  **Unverified:** how the operator is pointed at a custom login server.
- **The operator's OAuth secret puts a tailnet identity in the cluster.** Keep
  its tags narrow in Headscale's ACLs.
- **Host ports:** an `nixos-fw` rule drops everything from `192.168.1.190` and
  the LoadBalancer pool, then opens specific ports. The first is the restic REST
  server.

## Backups

| What | How | Where | Off-host |
|---|---|---|---|
| Boot disk (Talos, etcd, images) | vzdump, `max-workers=2`, nightly | a PBS datastore on this host | no: it can be rebuilt |
| Volumes | K8up (restic), with pre-backup dumps of SQLite and Postgres | an append-only restic REST server on this host | pushed to vulcanus |
| Data disk as a whole | not backed up (`backup=0`) | — | — |
| Talos secrets and machine config | sops-encrypted in this repo | git, and every clone | GitHub |

**On the host:**
- Run the REST server **append-only** (`services.restic.server`,
  `appendOnly = true`) on its own rpool dataset, reachable from the VM's address
  alone. A compromised cluster can add snapshots but can't delete or rewrite them.
- Prune from the host with a systemd timer running `restic forget --prune`.
  Append-only clients can't prune, so K8up's own prune schedules would fail.
- The PBS datastore for the VM is new; PBS #2's datastore belongs to vulcanus.
  Check whether the vulcanus-proxmox module behind PBS #2 takes a second
  datastore, or whether the VM's should live elsewhere.
- Proxmox needs a PBS storage entry (`pvesm add pbs …`) and a vzdump job (in
  `/etc/pve/jobs.cfg`). With tofu gone, both are either a oneshot unit that runs
  `pvesh` idempotently, like proxmox-nixos's `pve-generate-vm-*`, or a documented
  command.

**The push to vulcanus.** The credential exists to add backups and nothing else:
- **The receiver is an append-only restic REST server** (`--append-only
  --private-repos`) in its own unprivileged container on vulcanus, separate from
  restic LXC 108. It sits on its own dataset with a **quota**, so mini-nas can't
  fill vulcanus's rpool.
- **The path is the tailnet only.** A Headscale grant from mini-nas to that
  container's port, and nothing more. That fits the tagging in vulcanus's
  `todos/mini-nas-access.md`.
- **The sender is a host timer on mini-nas** running `restic copy` from the local
  repository to vulcanus's. The cluster never sees the vulcanus credential.
- **vulcanus keeps its own backstop.** It prunes that repository itself, and
  sanoid snapshots its dataset, which nothing mini-nas holds can touch.
- **Not ZFS push.** With `zfs receive`, vulcanus's kernel would parse streams
  that mini-nas crafted. A REST server is a sandboxed userspace program.

That leaves a compromised mini-nas able to add snapshots up to the quota, read its
own repository (data it already has), and send requests to a sandboxed HTTP
server. vulcanus's side is built in vulcanus-proxmox.

Every backup gets a freshness check, extending the healthchecks.io scheme in
vulcanus's `docs/backups.md`. Nobody was checking `nixos-upgrade`, which is how it
failed 316 times unnoticed.

## Host upgrades

### What is broken

`system.autoUpgrade` (`configuration.nix`) is `enable` plus `allowReboot`, with no
`flake`. So every night at 04:40, `nixos-upgrade.service` takes the channel path
and fails:

```
error: file 'nixos-config' was not found in the Nix search path
```

It failed 316 times with no success, as far back as the journal goes
(2025-12-09). The host has never updated or rebooted itself, which contradicts
`CLAUDE.md`'s "the host updates itself". It's still booted into 6.18.45.

### Decided: verify, then commit

Will wanted most updates applied without a human waiting in the loop, and he
weighed "build and switch to whatever's latest" against "build, and if it passes,
commit, push, and switch to the commit". **He chose the second on 2026-10-27**,
in the form below, and left the initial watchlist to be written here.

Extend `nightly_config_builder`, which already runs `nix flake update` at 04:00
and builds each host, into the upgrade pipeline, and turn `system.autoUpgrade`
off. mini-nas goes first in the run, as it does now (on 2026-10-26 its part took
7 minutes, and the whole run 31). Each night:

1. **Guard.** If the running system's `configurationRevision` isn't an ancestor
   of `origin/main` (the host is on a branch ahead of `main`, or was deployed
   from a dirty tree), skip mini-nas and alert. This needs
   `system.configurationRevision = self.rev or self.dirtyRev` set first.
2. **Update the inputs, except `vulcanus-proxmox`**:
   `nix flake update nixpkgs deploy-rs disko nixos-facter-modules proxmox-nixos
   sops-nix`. Generate that list from `flake.lock` minus the exclusion, so a new
   input is included by default. `vulcanus-proxmox` is re-pinned by hand when PBS
   #2 changes; that's what the "Re-pin vulcanus-proxmox for …" commits are. Note
   the consequence: **PBS #2's container gets nixpkgs updates only when it's
   re-pinned**, because it evaluates with vulcanus-proxmox's own lock.
3. **Commit `flake.lock` locally** on top of the `main` it cloned, so the build
   carries that commit as its `configurationRevision`. Then **build**.
4. **Hold back what's risky.** Compare the new closure with the running one
   (`nix store diff-closures /run/current-system ./result`). If anything on the
   [watchlist](#the-hold-back-watchlist) changed, push the commit to a branch
   `upgrade-held/<date>`, send a Pushover notification with its compare link, and
   stop. A deploy key can push a branch but can't open a PR, so Will opens it.
5. **Activate it without touching the boot entry** (`switch-to-configuration
   test`), then **health-check**:
   - no failed units
   - the essential ones active: sshd, tailscaled, postgresql, atticd,
     `container@pbs-offsite`, pveproxy, pvedaemon, and the VM running once it
     exists
   - the tailnet up
6. **If it's healthy,** make it the boot entry (`switch`), and **push the commit
   to `main`**. If `main` has moved since the clone, the push fails
   non-fast-forward; rebase only if the new commits don't touch `flake.lock`,
   otherwise leave it for the next night. **If it isn't healthy,** activate the
   previous generation again, discard the commit, and alert.

It alerts through Pushover, so `pushover-notifications.md` comes first, or alongside
it. Every night, healthy or held or failed, it pings a healthchecks.io check, so a
pipeline that stops running at all is noticed too.

#### The hold-back watchlist

The initial list. Each entry names the closure package, the change that holds
back, and why. Check the package names against `diff-closures` output from a
real run before trusting the matcher; `zfs`, for example, appears as more than
one store path.

| Package | Holds back on | Why |
|---|---|---|
| `linux` | a new series (6.18 → 6.19) | ZFS's out-of-tree module and the board's drivers. Patch releases within a series go through. |
| `zfs` (kernel module and userland) | a new minor (2.4 → 2.5) | Every pool, including root, and the scrubs and replication. |
| `proxmox-ve`, `pve-qemu-kvm`, `pve-qemu-server` | a new minor | proxmox-nixos's packaging; the VM's QEMU. A QEMU restart also costs the next vzdump a full read. |
| `postgresql` | a new major | The data directory upgrades one way. It's pinned to `postgresql_18` (`modules/postgresql`), so this should never fire; it's here in case the pin goes. |
| `attic` (atticd) | any version change | Its schema migrations are one-way, and the whole fleet substitutes from it. |
| `systemd` | a new major | Boot, networkd, and every unit. |
| `grub` | a new minor | The bootloader on five mirrored ESPs (`mirroredBoots`). |
| `openssh` | a new major | The way in. |
| `nix` | a new minor | The daemon the pipeline itself runs through. |
| `tailscale` | a new minor | Headscale trails Tailscale's clients and supports a window of versions (0.30 sets a minimum of 1.84). The tailnet is one of the two ways into the host. |

Everything else, including every other security update, goes through
unattended. Edit the list when a held change turns out to be routine, or an
unwatched one turns out not to be.

#### The reboot window

`switch` doesn't load a new kernel. **Reboot on Sunday at 01:30, only if the booted
kernel, initrd or modules differ from the current system's** (the same test
`system.autoUpgrade`'s `allowReboot` makes).

Why 01:30 on Sunday, from the host's timers on 2026-10-27:
- **Sunday is the quietest day.** The weekly timers (`nix-gc`, `fstrim`,
  `zpool-trim` with up to 6 h of jitter) fire on Monday at 00:00.
- **The third-Sunday scrub starts at 03:20** (plus up to 15 min of jitter) and
  runs about 15.5 hours: 03:21 to 18:53 on 2026-10-18.
- **The nightly pipeline starts at 04:00**, so a reboot can't interrupt it.
- **The hourly sanoid and syncoid runs start at :00**, and usually finish within
  10 s, occasionally 9 minutes. :30 sits clear of them.
- **PBS #2 works in UTC**: syncs at 12:00 UTC, verifies on Sunday at 14:00 UTC and
  collects garbage on Saturday at 14:00 UTC. All of those are daytime here.
- **DST:** on the spring-forward Sunday, 02:00–03:00 doesn't exist, so a 02:30
  timer would misfire. On the fall-back Sunday, 01:30 happens twice, and the
  kernel test stops the second firing from rebooting again.

Before rebooting, it checks that nothing it would interrupt is running: no
`zfs-scrub`, `syncoid-*` or `nightly_config_builder` unit active, and no vzdump
or restore task. If something is, it retries every 10 minutes until 03:00, then
gives up until the next Sunday and alerts.

A reboot stops the VM through `pve-guests-stop` and starts it again through
`startall`. Confirm that the stop shuts Talos down cleanly over ACPI or the guest
agent. Each reboot costs the cluster a few minutes, and the next vzdump a full read
of the boot disk. A small boot disk keeps that cheap.

Why this over "switch to the latest":
- **The running system is always a commit.** `git log` is the record of what
  changed and when, and the way back is a revert.
- **No hidden downgrades.** If the host ran a lock that isn't in git, the next
  `nh os switch` from any clone would move nixpkgs backwards. Some of what runs
  here migrates its state one way: Postgres, atticd's schema, and PBS #2 from the
  vulcanus-proxmox input. A downgrade can break those.
- **Only verified locks reach `main`.** Every lock in `main` has been built,
  cached and run healthily on the host. That's also what any branch made from
  `main` starts from.

**What it costs:**
- **mini-nas needs push access to this repo**: a deploy key with write access,
  scoped to this repo. The host is already root on itself, so that's no new
  power over the host. It is power over the cluster, since Flux deploys
  `kubernetes/` from the same repo, but a compromised hypervisor owns the VM
  anyway.
- **Bot commits interleave with yours on `main`**, as Flux Bot's do on vulcanus.
- **Flux's own key must be read-only**, with no image automation committing here.
  Otherwise a compromised cluster could commit to the repo the host deploys.
  `flux bootstrap github` creates a read-only deploy key by default.
- **`kubernetes/**` gets its own `.sops.yaml` rule**, with a cluster age key that
  can't decrypt any host secret.

- **If `main` is protected,** the deploy key needs to bypass the rule.

Then correct `CLAUDE.md`, and point `pushover-notifications.md`'s `nixos-upgrade`
candidate at the new unit.

## Without tofu

- **The VM:** `services.proxmox-ve.vms.<name>` (`modules/proxmox-ve/vms.nix` in
  proxmox-nixos) creates it once, through `pvesh create`, from a
  `pve-generate-vm-<vmid>` unit. **Later changes to those options are ignored**
  (the README says so), so changes after creation are `qm set` commands, recorded
  in `docs/`. The options cover `cpu.cputype`, `balloon`, `bios`, `agent`, and
  `virtio` disks with `discard` and `backup`. **`onboot` isn't an option**, so
  it's set with `qm set`. proxmox-nixos's tests run `qm start` on declared VMs
  (`tests/vm.nix`).
- **Talos:**
  - `talosctl gen secrets` once, kept sops-encrypted in the repo (admin keys
    only, not the host key)
  - patches in `talos/patches/*.yaml`
  - `talosctl gen config --with-secrets`, then `apply-config` and `bootstrap`
  - talosconfig and kubeconfig regenerated from the secrets and kept out of git
  - Talos upgrades with `talosctl upgrade`, one minor version at a time, as on
    vulcanus
- **Flux:** `flux bootstrap github` from a workstation.
- **Proxmox storage, the PBS entry and the vzdump job:** see
  [Backups](#backups). The `spool/vm` dataset is made by hand and recorded under
  `spool.datasets` in `disk-config.nix`, per the disko rule in `CLAUDE.md`.
  Proxmox puts only zvols under it, so it should need no `fileSystems` entry.
  Confirm that.

## What is different from vulcanus

- **One node does everything.** That means
  `cluster.allowSchedulingOnControlPlanes: true`, and the endpoint is the node's
  own address, with no VIP.
- **This is the first guest on proxmox-nixos.** Expect gaps, and check its issues
  first. `configuration.nix` already carries one workaround (#212).
- **The CPU is shared with the nightly builds.** `max-jobs` 2 × `cores` 8 uses
  all eight threads, so start the VM on 4 vCPUs. Memory is the sharper conflict;
  see [the memory incident](#the-memory-incident-2026-10-26).

### The move to rpool

When rpool grows to two 4-disk raidz1 vdevs and spool is to be destroyed:

1. **Give the new disks swap partitions.** All of the host's swap is `part1` on
   the two spool disks (16 GiB each), so destroying spool removes all of it. Add
   the partitions to the new disks' layout in `disk-config.nix`, and create them
   by hand, since disko doesn't change a live system. Will asked for this note.
2. **Re-run the fio check on rpool before moving.** Today's figures are 97 ms p99
   and 265 ms p99.9.
3. **Add a Proxmox storage on an rpool dataset, then move both disks online**:
   `qm disk move <vmid> <disk> <storage> --delete`. Expect etcd to stall during
   the copy. Check that the next backup is incremental.
4. **Revisit the vzdump tuning,** now that the backup reads and writes the same
   pool.

## Memory budget

| Host | GiB |
|---|---|
| Host services (atticd, Postgres, PBS #2 capped at 1 GiB, PVE, tailscaled) | ~2.3–2.5 |
| ARC, its cap lowered from 6 to 4 GiB | 4 |
| Talos VM | 6 |
| Headroom | ~2.5–3 |
| **Nightly builds** | **must fit in the headroom, so they're capped** |

**Protecting the VM** (plan step 3):
- `MemoryHigh` and `MemoryMax` on `nix-daemon.service` bound every local build.
  About 3 GiB high and 4 GiB max would be a start. The 12.4 GiB `rustc` would then
  have failed rather than taken the host.
- `MemoryMin` on the slice QEMU runs in, so the kernel never reclaims or swaps
  the guest's RAM. Proxmox puts VMs in `qemu.slice/<vmid>.scope`; confirm that
  proxmox-nixos does too.
- The alternative is static hugepages for the guest. They can't be swapped, but
  they're reserved even when the VM is off, and resizing needs a reboot.
- Then find out why `qbz` built locally rather than on thenixbeast.

Inside the VM, a rough plan. Only the first row is measured, and on vulcanus,
not here:

| Talos VM, 6 GiB | GiB |
|---|---|
| Talos, etcd, kubelet, containerd (~560 MiB on vulcanus) | ~0.6 |
| kube-apiserver at peak, with far fewer CRDs than vulcanus's 102 | ~0.7–1.0 |
| controller-manager, scheduler, CoreDNS | ~0.2 |
| Cilium: agent, operator, Envoy (Hubble on demand) | ~0.3–0.45 |
| Flux, K8up, OpenEBS, metrics-server, Tailscale operator | ~0.45 |
| Home Assistant, No Longer Evil, Mosquitto | ~0.6–0.8 |
| Web stack (Flask + Postgres, budgeted) | ~0.3–0.4 |
| What's left for the agents and page cache | ~1.5–2 |

- **The agent count is the variable.** Each pod is a Node process plus gVisor's
  Sentry. Measure one before deciding how many fit. If they don't fit, the
  fallbacks are more VM memory taken from the ARC, the NixOS-k3s VM (which saves
  about 0.5 GiB), or fewer operators.
- **Lowering the ARC** costs something unmeasured. Compare `arcstats` hit and miss
  deltas over matched windows before and after. Try the cap live through
  `/sys/module/zfs/parameters/zfs_arc_max` before committing the kernel parameter.
- **Swap is the canary.** Track the daily deltas of `pswpout` and `pswpin` in
  `/proc/vmstat`. Swap I/O lands on etcd's spindles.

## Plan

In order. Pass each step's check before starting the next.

0. **Create the worktree:** `git worktree add -b talos-vm .worktrees/talos-vm
   main`. Enter devenv there before committing (see the hooks gotcha in
   `CLAUDE.md`). Add `talosctl`, `kubectl`, `flux`, `helm` and `cilium-cli` to
   `devenv.nix`.
1. **Pushover notifications** (`pushover-notifications.md`), since the upgrade
   pipeline and every backup check alert through them.
2. **Host upgrades,** since they change how the host reboots under everything
   else:
   - set `configurationRevision`
   - build the pipeline, with its guard, input exclusion, watchlist, health check
     and rollback
   - give mini-nas a write deploy key
   - add the Sunday 01:30 reboot timer
   - add the healthchecks.io ping
   - turn `system.autoUpgrade` off

   Watch real runs: one that succeeds, one that skips, one held by the watchlist,
   and one that rolls back. The first reboot moves the host from 6.18.45 to
   whatever is current then. This step doesn't depend on the VM and can land as
   its own PR.
3. **Protect memory:** caps on nix-daemon, protection for the QEMU slice, and the
   ARC at 4 GiB (`zfs.zfs_arc_max=4294967296`, tested live first).
4. **Turn on VT-x** at a planned reboot, through the JetKVM: Intel Virtualization
   Technology, under the BIOS's CPU configuration. Make sure `kvm-intel` loads:
   udev may autoload it; if not, regenerate `facter.json` (nixos-facter keys the
   module on `vmx`) and review the diff, or declare it in `boot.kernelModules`.
5. **Create the storage:** the `spool/vm` dataset with its Proxmox `zfspool`
   storage, the restic REST server's dataset, and the VM's PBS datastore. Record
   each in `disk-config.nix`.
6. **Set up the host side:** the `nixos-fw` rules, the append-only REST server,
   the prune timer, the PBS storage entry and the vzdump job.
7. **Build the Talos image** at factory.talos.dev: the current stable release,
   with `siderolabs/qemu-guest-agent` and `siderolabs/gvisor`. Put the ISO on
   `local`.
8. **Create the VM** through `services.proxmox-ve.vms`:
   - `cpu.cputype = host`, 4 cores, 6144 MiB, `balloon = 0`, the agent on, and a
     virtio NIC on `vmbr0`
   - a boot disk of about 50 GiB (`backup=1`) and a data disk sized to need
     (`backup=0`), both virtio on `spool/vm` with `discard`
   - then `qm set --onboot 1`

   Reserve `192.168.1.190` against its MAC.
9. **Configure and bootstrap Talos.** The patches cover:
   - the install disk and the hostname
   - `allowSchedulingOnControlPlanes`
   - leader election off for controller-manager and scheduler
   - CNI none and the proxy disabled
   - the data disk mount
   - etcd's metrics listener (`cluster.etcd.extraArgs.listen-metrics-urls:
     http://0.0.0.0:2381`)

   Then `helm install` Cilium with its tuned values.
10. **Take the first measurements** (see [Verifying](#verifying)), before Flux or
    any workload goes on. This gives the baseline write rate.
11. **Bootstrap Flux** with leader election off. Hand Cilium over to a
    HelmRelease. Add OpenEBS and K8up (both with election off, K8up pointed at
    the REST server), metrics-server, the fstrim CronJob, the Gateway, the LB-IPAM
    pool with L2 announcements, the gVisor RuntimeClass with its admission policy,
    the bandwidth manager, the agents' default-deny and egress policies, and
    Hubble's DNS flow export. Re-measure the write rate.
12. **Add the workloads**, measuring `MemAvailable` after each: Mosquitto, Home
    Assistant, No Longer Evil, one agent, then more. Follow the [address
    SOP](#addresses) for each LoadBalancer address.
13. **The off-host push**, with vulcanus's receiver built in vulcanus-proxmox, and
    freshness checks for every backup.
14. **The Tailscale operator**, once Headscale 0.30.0 runs on vulcanus.
15. **Write it up and retire the spec.** Whatever is now permanently true goes
    into `docs/` and `CLAUDE.md`: the VM, the address table, the upgrade
    pipeline's real behaviour, `kubernetes/`, `talos/`, and the backup layout.
    Then delete this file and its entry in `todos/README.md`.

## Verifying

- **Host upgrades:**
  - a run that succeeds and pushes
  - a run that skips because the host is ahead of `main`
  - a watchlist change that pushes an `upgrade-held/` branch and notifies
  - a forced failed health check that rolls back and alerts
  - `vulcanus-proxmox` unchanged in every pipeline commit
  - a Sunday with a pending kernel that reboots at 01:30, and one with a scrub or
    syncoid running that waits
  - a Sunday with no new kernel that doesn't reboot
- **Memory protection:** a deliberately large local build hits nix-daemon's cap,
  and the guest's RSS doesn't go to swap (`VmSwap` in the QEMU process's
  `/proc/<pid>/status` stays at zero).
- **KVM:** `/dev/kvm` exists and `lsmod | grep kvm_intel` matches.
- **The VM got its config:** `qm showcmd <vmid> --pretty | grep -E -- '-cpu|-m '`
  shows exactly one `-cpu` and the expected memory.
- **The etcd write rate**, measured rather than computed:
  - **Leases:** sample every Lease's `renewTime` for a minute (the loop is in
    vulcanus's `docs/talos.md`). Only the kubelet's, the apiserver's, the Cilium
    operator's and one per announced service should move, at the intervals in the
    table.
  - **Writes per resource:** take the difference in
    `apiserver_request_total{verb=~"POST|PUT|PATCH|DELETE"}` by `resource`
    between two samples some minutes apart, from the apiserver's `/metrics`.
  - **Total writes:** take the difference in `etcd_mvcc_put_total` and
    `etcd_mvcc_delete_total` from etcd's `:2381/metrics`.
- **etcd's fsync, from inside the VM**, at rest, during a vzdump and during a
  scrub. Take differences of `etcd_disk_wal_fsync_duration_seconds_bucket` over
  matched windows. `etcd_server_proposals_failed_total` reads zero at rest, so
  any increase means etcd couldn't commit.
- **gVisor is enforced:** an agent-namespace pod without `runtimeClassName` is
  rejected, and `dmesg` inside an agent pod shows gVisor's banner.
- **Cilium policy holds under gVisor:** from an agent pod, public sites over
  IPv4 and IPv6 connect. `192.168.1.1`, `192.168.1.11`, the node, Home
  Assistant, Mosquitto, a tailnet address and a pod in another namespace are all
  unreachable. Each lookup shows up in the DNS flow export, and a sustained
  upload is held to the bandwidth cap.
- **Announced addresses:** each LoadBalancer address answers from another LAN
  device, and comes back after a Cilium agent restart.
- **A host reboot:** the VM shuts down cleanly and comes back, and the next
  vzdump does a full read of the boot disk only.
- **Backups:** a K8up snapshot reaches the REST server, and `restic forget` with
  the cluster's credentials is refused. The push reaches vulcanus, and a
  `forget` with mini-nas's vulcanus credential is refused. Do one restore of
  each kind.
- **Memory:** the node's `MemAvailable`, and on the host `free`, the ARC size
  and the daily `pswpout` delta.

## Still open

Nothing waits on Will as of 2026-10-27. These get settled during the work:

1. **How many agents fit** in what's left of the VM's 6 GiB. Measure one under
   gVisor first; see [Memory budget](#memory-budget).
2. **Why `qbz` built on mini-nas** instead of on thenixbeast; see
   [the memory incident](#the-memory-incident-2026-10-26).
3. **The watchlist's package names** against real `diff-closures` output; see
   [the watchlist](#the-hold-back-watchlist).
