{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.tailscale ];
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
  };

  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";
    serviceConfig.Type = "oneshot";

    # Make sure tailscale is running before trying to connect to tailscale
    after = [
      "network-pre.target"
      "tailscale.service"
    ];
    wants = [
      "network-pre.target"
      "tailscale.service"
    ];
    wantedBy = [ "multi-user.target" ];

    # Have the job run this shell script
    script = with pkgs; ''
      # Wait for tailscaled to settle
      sleep 2

      # Check if we are already authenticated to tailscale
      status="$(${tailscale}/bin/tailscale status -json | ${jq}/bin/jq -r .BackendState)"
      if [ $status = "Running" ]; then # If so, then do nothing
        exit 0
      fi

      ${tailscale}/bin/tailscale up
    '';
  };
}
