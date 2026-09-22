# Monitoring for the backup layer: every job reports success to
# healthchecks.io, and two timers assert the state of the *store* rather than
# the exit code of the job that wrote it.
#
# The distinction is load-bearing. A recursive replication job can exit zero
# while carrying only part of its dataset list, and a job that stops running
# emits nothing at all. Neither state is visible from the job's own result, so
# the assertions below read the target instead.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Reads a check's URL from its sops secret and pings it. The optional second
  # argument is a path suffix -- "/fail" reports failure immediately rather
  # than waiting for the check's period to lapse.
  hcPing = pkgs.writeShellApplication {
    name = "hc-ping";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      url_file="/run/secrets/healthchecks/$1"
      if [ ! -r "$url_file" ]; then
        echo "hc-ping: no URL at $url_file" >&2
        exit 1
      fi
      url="$(cat "$url_file")"
      # A secret that is not a URL is a configuration error, and curl's
      # complaint about it is unhelpful: brackets are glob syntax, so a stray
      # ENC[...] blob is reported as "bad range in position 5" rather than as
      # the wrong value it is. Say so plainly, without echoing the secret.
      case "$url" in
        https://*) ;;
        *)
          echo "hc-ping: $url_file does not contain an https:// URL" >&2
          exit 1
          ;;
      esac
      # -g because a URL is data, not a glob pattern.
      curl -fsS -g -m 10 --retry 3 -o /dev/null "$url''${2:-}"
    '';
  };

  # Reports a unit's real outcome. systemd sets $SERVICE_RESULT for ExecStopPost
  # commands, so this runs once per invocation, after the process has actually
  # exited, and knows whether it worked.
  #
  # ExecStartPost cannot do this. Under Type=simple the unit counts as started
  # about a second after fork, so a success ping fires before the job has done
  # anything -- reporting success on every run whatever the outcome, and leaving
  # a hung job's check green forever. That is the failure this module exists to
  # catch, so it must not be the way this module reports.
  hcReport = pkgs.writeShellApplication {
    name = "hc-report";
    runtimeInputs = [ hcPing ];
    text = ''
      case "''${SERVICE_RESULT:-}" in
        success) hc-ping "$1" ;;
        *) hc-ping "$1" /fail ;;
      esac
    '';
  };

  # Pool health, checked from the pool rather than from a scrub unit's exit
  # code. `zfs-scrub@` exits 0 having found errors, so OnFailure= and a success
  # ping cannot report a dirty pool. These four conditions can.
  poolHealth = pkgs.writeShellApplication {
    name = "zfs-pool-health";
    runtimeInputs = [
      pkgs.zfs
      pkgs.jq
      hcPing
    ];
    text = ''
      check="$1"
      capacity_limit="$2"
      problems=""

      note() { problems="''${problems}$1"$'\n'; }

      # Catches DEGRADED and FAULTED, which no scrub exit code reports.
      if ! zpool status -x | grep -q '^all pools are healthy$'; then
        note "zpool status -x: $(zpool status -x | head -1)"
      fi

      status_json="$(zpool status -j)"

      for pool in $(zpool list -H -o name); do
        pool_json="$(jq -r --arg p "$pool" '.pools[$p]' <<<"$status_json")"

        errors="$(jq -r '.error_count' <<<"$pool_json")"
        [ "$errors" = "0" ] || note "$pool: $errors data errors"

        # Sums read/write/checksum across every vdev, at any nesting depth.
        vdev_errors="$(
          jq -r '[.. | objects | select(has("read_errors"))
                  | (.read_errors|tonumber) + (.write_errors|tonumber)
                    + (.checksum_errors|tonumber)] | add // 0' <<<"$pool_json"
        )"
        [ "$vdev_errors" = "0" ] || note "$pool: $vdev_errors vdev errors"

        capacity="$(zpool list -H -o capacity "$pool" | tr -d '%')"
        if [ "$capacity" -ge "$capacity_limit" ]; then
          note "$pool: $capacity% full, limit $capacity_limit%"
        fi

        # A resilver is not a scrub. Until a scrub has actually finished, the
        # pool is unverified and this says so rather than passing on a
        # RESILVER record that happens to be recent.
        scan_function="$(jq -r '.scan_stats.function // "NONE"' <<<"$pool_json")"
        scan_state="$(jq -r '.scan_stats.state // "NONE"' <<<"$pool_json")"
        if [ "$scan_state" = "SCANNING" ]; then
          : # scrub or resilver in progress; judge it when it finishes
        elif [ "$scan_function" != "SCRUB" ]; then
          note "$pool: never scrubbed"
        else
          end_time="$(jq -r '.scan_stats.end_time' <<<"$pool_json")"
          if end_epoch="$(date -d "$end_time" +%s 2>/dev/null)"; then
            age_days=$(( ( $(date +%s) - end_epoch ) / 86400 ))
            [ "$age_days" -le 45 ] || note "$pool: last scrub $age_days days ago"
          else
            note "$pool: unparseable scrub end_time '$end_time'"
          fi
        fi
      done

      if [ -n "$problems" ]; then
        printf '%s' "$problems" >&2
        hc-ping "$check" /fail
        exit 1
      fi
      hc-ping "$check"
    '';
  };

  # Asserts that every replicated dataset is recent, and that the target holds
  # every dataset the source has. Per protected object, not per job.
  replicationFreshness = pkgs.writeShellApplication {
    name = "zfs-replication-freshness";
    runtimeInputs = [
      pkgs.zfs
      pkgs.openssh
      hcPing
    ];
    text = ''
      check="$1"
      target_base="rpool/foreign-backups/vulcanus"
      source_host="mini-nas@vulcanus.forge.local"
      ssh_key="${config.sops.secrets."users/syncoid/ssh_private_key".path}"
      problems=""

      note() { problems="''${problems}$1"$'\n'; }

      # Maximum age per group, derived from the *source's* sanoid schedule:
      # rpool/storage snapshots hourly; rpool/data, rpool/ROOT and
      # rpool/backups/restic daily. A dataset older than this is stale even if
      # every unit exited 0.
      max_age_for() {
        case "$1" in
          "$target_base"/storage*) echo 10800 ;;
          *) echo 93600 ;;
        esac
      }

      now="$(date +%s)"
      for dataset in $(zfs list -H -o name -r "$target_base"); do
        [ "$dataset" = "$target_base" ] && continue
        # A container holds nothing and receives nothing, so it has no snapshots
        # to age: backups/, made by hand so restic's replica has a parent. Every
        # dataset that receives keeps canmount=on, so a retired replica still
        # fails here as intended.
        [ "$(zfs get -H -o value canmount "$dataset")" = "off" ] && continue
        newest="$(zfs list -t snapshot -H -p -o creation -s creation -d1 "$dataset" 2>/dev/null | tail -1)"
        if [ -z "$newest" ]; then
          note "$dataset: no snapshots at all"
          continue
        fi
        age=$(( now - newest ))
        limit="$(max_age_for "$dataset")"
        if [ "$age" -gt "$limit" ]; then
          note "$dataset: newest snapshot $(( age / 3600 ))h old, limit $(( limit / 3600 ))h"
        fi
      done

      # A dataset that was never replicated has no stale snapshot to find, so
      # freshness alone cannot see it. Compare against the source.
      for source_root in rpool/storage rpool/ROOT rpool/data rpool/backups/restic; do
        if ! source_list="$(ssh -i "$ssh_key" -o BatchMode=yes -o ConnectTimeout=15 \
              "$source_host" "zfs list -H -o name -r $source_root" 2>&1)"; then
          note "could not list $source_root on the source: $source_list"
          continue
        fi
        for source_dataset in $source_list; do
          expected="$target_base/''${source_dataset#rpool/}"
          zfs list -H -o name "$expected" >/dev/null 2>&1 \
            || note "$source_dataset has no counterpart at $expected"
        done
      done

      if [ -n "$problems" ]; then
        printf '%s' "$problems" >&2
        hc-ping "$check" /fail
        exit 1
      fi
      hc-ping "$check"
    '';
  };

  # Units whose success should ping a check of the same name. Each also gets an
  # OnFailure= so a hard failure reports immediately instead of waiting out the
  # check's period.
  monitoredUnits = [
    "sanoid"
    "syncoid-vulcanus-storage"
    "syncoid-vulcanus-root"
    "syncoid-vulcanus-data"
  ];

  checkNameFor = unit: if unit == "sanoid" then "sanoid-mini-nas" else unit;
in
{
  systemd.services = {
    # Instantiated by OnFailure=. The instance name is the check name.
    "healthcheck-fail@" = {
      description = "Report failure of %i to healthchecks.io";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${hcPing}/bin/hc-ping %i /fail";
      };
    };

    zfs-pool-health = {
      description = "Assert pool health, errors, capacity and scrub age";
      serviceConfig = {
        Type = "oneshot";
        # 90 rather than the usual 80 while the vdev expansion to 4-disk
        # raidz1 is pending, because occupancy sits above 80 until then and a
        # warning that is always on is one nobody reads. Goes back to 80 with
        # the expansion.
        ExecStart = "${poolHealth}/bin/zfs-pool-health pool-health-mini-nas 90";
      };
    };

    # The healthchecks free tier's twenty checks are all spoken for, so this unit
    # has none of its own: a hard failure reports straight to the freshness
    # check, which would find the replica stale anyway. Its next run turns it
    # green again only if the replica is current.
    syncoid-vulcanus-backups-restic.onFailure = [
      "healthcheck-fail@zfs-replication-freshness.service"
    ];

    zfs-replication-freshness = {
      description = "Assert every replicated dataset is present and recent";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${replicationFreshness}/bin/zfs-replication-freshness zfs-replication-freshness";
      };
    };
  }
  // lib.genAttrs monitoredUnits (unit: {
    # Reported from ExecStopPost, not ExecStartPost, and without an OnFailure.
    # These units are Type=simple, so ExecStartPost runs about a second after
    # fork -- it would ping success before the job had done anything, on every
    # run whatever the outcome, and a hung job would hold the check green
    # indefinitely. ExecStopPost runs once the process has exited and carries
    # $SERVICE_RESULT, so one ping per run reports what actually happened.
    #
    # `+` runs it as root regardless of the unit's User=, so the secrets stay
    # 0400 root-owned. `-` because a backup that ran is not a backup that
    # failed: an unreachable monitor must not mark the unit failed. A ping that
    # does not arrive turns the check red on its own period.
    serviceConfig.ExecStopPost = "-+${hcReport}/bin/hc-report ${checkNameFor unit}";
  });

  systemd.timers = {
    zfs-pool-health = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "5m";
        Persistent = true;
      };
    };

    zfs-replication-freshness = {
      wantedBy = [ "timers.target" ];
      # 06:30 MDT on vulcanus is 08:30 here; late enough that the nightly
      # daily snapshots have been taken and pulled.
      timerConfig = {
        OnCalendar = "*-*-* 08:30:00";
        Persistent = true;
      };
    };
  };
}
