# mini-nas has no way to tell Will something failed

## Opening prompt

> mini-nas has no failure notifications, so a broken unit goes unnoticed until
> its absence is. Read `todos/pushover-notifications.md`, then add Pushover
> notifications, starting with `claude-warmup`, and retire the spec.

Written **2026-10-16**. Nothing below about Pushover or zed was verified on the
host; it is the plan, not a survey.

## Decided

- **Pushover** is the channel (Will, 2026-10-16).
- **`claude-warmup` failing is one of the things to notify on.** Its
  `claude setup-token` token lasts about a year, and the notification is how
  its expiry gets caught. Will chose this over a separate reminder
  to renew it. Its script exits non-zero on an auth failure but zero on a
  rate-limit refusal (which still anchors the window), so a failure means the
  ping did not land.

## Candidates, not yet agreed

Other units whose silent failure would hurt: `nightly_config_builder`,
`nixos-upgrade` (`system.autoUpgrade`), the syncoid pulls from `vulcanus`,
`attic-push-token`, and ZFS events from zed.

## Likely approach

- A template unit, `notify-failure@.service`, that posts the failed unit's name
  and the tail of its journal to `https://api.pushover.net/1/messages.json`,
  with the app token and user key from sops. Each watched unit gets
  `onFailure = [ "notify-failure@%n.service" ];`.
- zed has its own Pushover support (`ZED_PUSHOVER_TOKEN`, `ZED_PUSHOVER_USER` in
  `services.zfs.zed.settings`); check before wiring zed through the template.

When this lands, note the notifications in `CLAUDE.md`, drop the pointer to
this spec from `modules/claude_warmup/default.nix`, and delete this file and its
entry in `todos/README.md`.
