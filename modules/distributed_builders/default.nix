{ config, ... }:
{
  sops.secrets."distributed_builders/ssh_private_key".sopsFile = ./secrets.yaml;

  nix = {
    distributedBuilds = true;
    buildMachines = [
      # speedFactor calculation: CPU boost GHz * CPU threads, normalized to mini-nas (the
      # dotfiles repo uses the same numbers):
      #   mini-nas     Intel Haswell          4.4 GHz *  8 =  35  -> 1
      #   thenixbeast  Ryzen 9 9900X (Zen 5)  5.6 GHz * 24 = 134  -> 3.8 -> 4
      #   steamdeck    Zen 2 APU              3.5 GHz *  8 =  28  -> 0.8 (not a builder)
      # Every host sets max-jobs * cores to twice its threads. A remote build runs with
      # this host's `cores` (8), so maxJobs gives it the same budget: 2 * 24 / 8.
      {
        protocol = "ssh-ng";
        hostName = "thenixbeast.forge.local";
        maxJobs = 6;
        speedFactor = 4;
        sshKey = config.sops.secrets."distributed_builders/ssh_private_key".path;
        sshUser = "nix";
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
        systems = [
          "x86_64-linux"
          "i686-linux"
        ];
      }
    ];
    settings = {
      # Read the machine list from a file only this host has. A builder adopts the
      # `builders` value of a trusted client, so a build that steamdeck sends here reads
      # /etc/nix/machines.steamdeck, finds nothing, and runs here rather than being
      # forwarded again. Forwarding is what let builds loop back to the host that sent
      # them, and deadlock on its locks (NixOS/nix#2029).
      builders = "@/etc/nix/machines.${config.networking.hostName}";
      builders-use-substitutes = true;
      trusted-users = [ "nix" ];
    };
  };

  environment.etc."nix/machines.${config.networking.hostName}".source =
    config.environment.etc."nix/machines".source;

  users = {
    users.nix = {
      isSystemUser = true;
      group = "nix";
      # The key can only talk to the Nix daemon, which is all `ssh-ng` builds need (Lix
      # would need a wrapper: it runs a shell on the remote end). It stays a trusted user:
      # builders must accept unsigned build inputs, and adopt the sender's `builders`
      # setting (see above). That also lets it plant any store path, so whoever holds
      # the key is effectively root here.
      openssh.authorizedKeys.keys = [
        "restrict,command=\"${config.nix.package}/bin/nix-daemon --stdio\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEufEieU/OuOiSA3jfmUo4ro9UQFC2tMkzL/NdRuP3Qh"
      ];
      useDefaultShell = true;
    };

    groups.nix = { };
  };

  programs.ssh = {
    # Without this, a builder that's switched off stalls every build for the full TCP
    # connect timeout before Nix moves on.
    extraConfig = ''
      Match user nix host thenixbeast.forge.local
        ConnectTimeout 5
      Match all
    '';
    knownHosts = {
      steamdeck = {
        extraHostNames = [
          "192.168.1.12"
          "steamdeck.forge.local"
        ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC3g7cDUbFypZlqSxWfblUe8E+I7lGxkJTmAw5VaWK89";
      };
      thenixbeast = {
        extraHostNames = [
          "192.168.1.10"
          "thenixbeast.forge.local"
        ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEB74qOTioDeqED1VPlfAHWsQuh5x5TQs7kji2S8QiEM";
      };
    };
  };

  services.openssh = {
    enable = true;
  };
}
