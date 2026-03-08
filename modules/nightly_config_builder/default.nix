# Taken from: https://github.com/basnijholt/dotfiles/blob/main/configs/nixos/hosts/nix-cache/auto-build.nix
{ pkgs, ... }:
let
  repository = "https://github.com/dartagan/dotfiles.git";
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

        DOTFILES="/var/lib/nightly_config_builder/dotfiles"

        # Clone or update dotfiles
        if [ ! -d "$DOTFILES" ]; then
          git clone ${repository} "$DOTFILES"
        else
          cd "$DOTFILES"
          git fetch origin
          git reset --hard origin/main
        fi

        # Update flake inputs
        nix flake update

        # Get the commit ID of the nixpkgs input (locked in flake.lock)
        COMMIT_ID=$(jq -r .nodes.nixpkgs.locked.rev flake.lock)

        # Build all host configurations (--cores 1 to limit memory usage)
        for host in iso steamdeck thenixbeast; do
          echo "Building $host..."
          if nix build .#nixosConfigurations.$host.config.system.build.toplevel \
            --out-link "/var/lib/nightly_config_builder/result-$host" \
            --print-out-paths \
            --max-jobs 1; then
              echo "$COMMIT_ID" > "/var/lib/nightly_config_builder/$host.rev"
          else
              echo "Warning: $host build failed, continuing..."
          fi
        done

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
      "d /var/lib/nightly_config_builder 0755 root root -"
    ];
  };
}
