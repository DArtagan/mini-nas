# Taken from: https://github.com/basnijholt/dotfiles/blob/main/configs/nixos/hosts/nix-cache/auto-build.nix
{ pkgs, ... }:
let
  stateDir = "/var/lib/nightly_config_builder";
in
{
  systemd = {
    services.nightly_config_builder = {
      description = "Build and cache NixOS configurations";
      path = with pkgs; [
        git
        nix
        openssh
        jq
      ];
      script = ''
        set -euo pipefail
        export NIX_REMOTE=daemon

        # Updates a repo's flake inputs, then builds the given hosts, so they're cached
        # and the out-links keep the builds from being garbage collected.
        build() {
          local repo=$1
          shift
          local checkout="${stateDir}/$repo"

          if [ ! -d "$checkout" ]; then
            git clone "https://github.com/dartagan/$repo.git" "$checkout"
            cd "$checkout"
          else
            cd "$checkout"
            git fetch origin
            git reset --hard origin/main
          fi

          nix flake update

          # Get the commit ID of the nixpkgs input (locked in flake.lock)
          local commit_id
          commit_id=$(jq -r .nodes.nixpkgs.locked.rev flake.lock)

          for host in "$@"; do
            echo "Building $host..."
            if nix build ".#nixosConfigurations.$host.config.system.build.toplevel" \
              --out-link "${stateDir}/result-$host" \
              --print-out-paths; then
                echo "$commit_id" > "${stateDir}/$host.rev"
            else
                echo "Warning: $host build failed, continuing..."
            fi
          done
        }

        # This host first: it's quick, and doesn't wait behind the CUDA builds.
        build mini-nas mini-nas
        build dotfiles iso steamdeck thenixbeast

        echo "All builds completed at $(date)"
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        TimeoutStartSec = "3d"; # Generous timeout for CUDA builds
      };
    };

    # --- Daily Timer ---
    timers.nightly_config_builder = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
      };
    };

    # Ensure build directory exists
    tmpfiles.rules = [
      "d ${stateDir} 0755 root root -"
    ];
  };
}
