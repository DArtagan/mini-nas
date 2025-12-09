_: {
  # Make vmbr0 bridge visible in Proxmox web interface
  services.proxmox-ve.bridges = [ "vmbr0" ];

  # Actually set up the vmbr0 bridge
  systemd.network = {
    networks."10-lan" = {
      matchConfig.Name = [ "ens18" ]; # TODO: double check this
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

    networks."10-lan-bridge" = {
      matchConfig.Name = "vmbr0";
      networkConfig = {
        IPv6AcceptRA = true;
        DHCP = "ipv4";
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };
}
