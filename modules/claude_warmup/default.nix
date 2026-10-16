# Sends Claude a throwaway prompt on a fixed grid, so the 5-hour usage window resets
# at times picked ahead, rather than 5 hours after whenever work started. The 08:00
# ping opens the day's first window before work does, so a morning burst runs into a
# reset instead of a 3-hour wait. Same idea as github.com/vdsmon/claude-warmup.
#
# The token is from `claude setup-token`, and lasts about a year. When it expires the
# unit fails; todos/pushover-notifications.md is how that failure should get noticed.
{ config, pkgs, ... }:
let
  # A ping only anchors a window if none is open, so each lands just after the window
  # the one before it opened resets. Windows start at the exact minute of the first
  # message (since about April 2026; before, they were floored to the hour), so each
  # ping is 2 minutes later than the last, to clear the previous one's start-up delay.
  # The 08:00 ping follows a 9-hour gap, so it always finds the window closed.
  pings = [
    "08:00"
    "13:02"
    "18:04"
    "23:06"
  ];
in
{
  sops.secrets.claude_oauth_token = {
    sopsFile = ./secrets.yaml;
  };

  systemd = {
    services.claude-warmup = {
      description = "Anchor Claude's 5-hour usage window";
      path = [
        pkgs.claude-code
        pkgs.jq
      ];
      environment = {
        HOME = "/var/lib/claude-warmup";
        DISABLE_AUTOUPDATER = "1";
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
      };
      # Not --bare: it never reads OAuth, so the token would be ignored.
      script = ''
        set -uo pipefail
        CLAUDE_CODE_OAUTH_TOKEN=$(< "$CREDENTIALS_DIRECTORY/token")
        export CLAUDE_CODE_OAUTH_TOKEN

        output=$(claude -p "Reply OK" \
          --model haiku \
          --tools "" \
          --no-session-persistence \
          --output-format stream-json \
          --verbose 2>&1)
        status=$?

        # The rate-limit event carries the window's reset time. Seeing one at all means
        # the request reached Anthropic, which is what anchors the window, even if the
        # reply was a refusal because the limit is already spent. Lines that aren't JSON
        # are stderr, and skipped.
        limits=$(jq -Rr '
          fromjson? | select(.type? == "rate_limit_event") | .rate_limit_info
          | (.resetsAt // null) as $at
          | "\(.rateLimitType // "unknown") window \(.status // "unknown"), resets \(
              if $at == null then "at an unreported time"
              else (if $at > 1e12 then $at / 1000 else $at end) | floor
                | strflocaltime("%F %H:%M:%S %Z") end)"
        ' <<< "$output")

        if [ -n "$limits" ]; then
          echo "$limits"
          exit 0
        fi
        if [ "$status" -eq 0 ]; then
          echo "Pinged; Claude Code didn't report the reset time"
          exit 0
        fi
        # Most likely an expired or revoked token. Print everything, to see which.
        echo "$output"
        exit "$status"
      '';
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        StateDirectory = "claude-warmup";
        LoadCredential = "token:${config.sops.secrets.claude_oauth_token.path}";
      };
    };

    timers.claude-warmup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = map (time: "*-*-* ${time}:00") pings;
        # The default lets a timer fire up to a minute late, as much as the offsets.
        AccuracySec = "1s";
        # A ping missed while the host was down would anchor the window off the grid.
        Persistent = false;
      };
    };
  };
}
