_: {
  # Make vmbr0 bridge visible in Proxmox web interface
  services.proxmox-ve.bridges = [ "vmbr0" ];

  # The host's address is on the bridge, so guests and the host share eth0.
  # networkd rather than dhcpcd, which would otherwise keep eth0 for itself.
  # nixos-facter turns DHCP on for each NIC it detects, as well as globally.
  networking.useDHCP = false;
  networking.interfaces.eth0.useDHCP = false;

  systemd.network = {
    enable = true;

    networks."10-lan" = {
      matchConfig.Name = [ "eth0" ];
      networkConfig = {
        Bridge = "vmbr0";
      };
    };

    netdevs."vmbr0" = {
      netdevConfig = {
        Name = "vmbr0";
        Kind = "bridge";
      };
    };

    # Static, because the bridge has its own MAC and DHCP could lease it a new
    # address; tofu, deploy-rs and ssh all use this one. The router keeps .11 out
    # of its pool.
    networks."10-lan-bridge" = {
      matchConfig.Name = "vmbr0";
      address = [ "192.168.1.11/24" ];
      routes = [ { Gateway = "192.168.1.1"; } ];
      # Read by resolved, which networkd brings with it; Tailscale adds MagicDNS
      # on its own link.
      dns = [ "192.168.1.1" ];
      networkConfig.IPv6AcceptRA = true;
      linkConfig.RequiredForOnline = "routable";
    };
  };
}
