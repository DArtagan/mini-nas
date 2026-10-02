{ config, ... }:
{
  sops.secrets = {
    "distributed_builders/ssh_private_key" = {
      sopsFile = ./secrets.yaml;
    };
    "distributed_builders/ssh_public_key" = {
      sopsFile = ./secrets.yaml;
    };
  };

  nix = {
    distributedBuilds = true;
    buildMachines =
      let
        protocol = "ssh-ng";
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
      in
      [
        # speedFactor calculation: CPU GHz * CPU threads
        #   mini-nas: 4.4 * 8 = 35, normalized to mini-nas: 1
        #   thenixbeast: 5.6 * 24 = 134, normalized to mini-nas: 3.8 -> ~4
        #   steamdeck: 3.5 * 8 = 28, normalized to mini-nas: 0.8 -> ~1
        {
          inherit
            protocol
            sshKey
            sshUser
            supportedFeatures
            systems
            ;
          hostName = "thenixbeast.forge.local";
          maxJobs = 12;
          speedFactor = 4;
        }
        #{
        #  inherit
        #    protocol
        #    sshKey
        #    sshUser
        #    supportedFeatures
        #    systems
        #    ;
        #  hostName = "steamdeck.forge.local";
        #  maxJobs = 4;
        #  speedFactor = 1;
        #}
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
      # TODO: lock this down further using something like: https://discourse.nixos.org/t/wrapper-to-restrict-builder-access-through-ssh-worth-upstreaming/25834/17
      openssh.authorizedKeys.keys = [
        "no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEufEieU/OuOiSA3jfmUo4ro9UQFC2tMkzL/NdRuP3Qh"
      ];
      useDefaultShell = true;
    };

    groups.nix = { };
  };

  programs.ssh = {
    # Without this, a builder that's switched off stalls every build for the full TCP
    # connect timeout before Nix moves on.
    extraConfig = ''
      Match user nix host thenixbeast.forge.local,steamdeck.forge.local
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
