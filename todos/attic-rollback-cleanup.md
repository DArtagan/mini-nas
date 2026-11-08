# atticd's SQLite rollback point is still on disk

## Opening prompt

> atticd moved from SQLite to Postgres on 2026-10-05, and the way back is still
> on mini-nas: the old SQLite database and the `rpool/rpool/var@pre-attic-postgres`
> snapshot. Read `todos/attic-rollback-cleanup.md`, run its checks, and if they
> pass, delete both and retire the spec.

Verified **2026-10-06**.

## What exists

The move is [PR #3](https://github.com/DArtagan/mini-nas/pull/3). atticd has run
on Postgres since 2026-10-05 19:31 EDT. Two things were kept so the move could
be undone:

| What | Where | Size |
|---|---|---|
| The SQLite database, untouched since atticd stopped for the copy | `/var/lib/private/atticd/server.db`, `-wal`, `-shm` (`/var/lib/atticd` links there) | 7.3 GB |
| A snapshot of `/var` taken just before the copy | `rpool/rpool/var@pre-attic-postgres` | 3.44 GB `USED`, and growing |

Rolling back means pointing `services.atticd.settings.database.url` at
`sqlite:///var/lib/atticd/server.db?mode=rwc` and deploying. Anything uploaded
since the cutover would be missing from that database, and would be re-pushed
only when something builds it again.

## Why it matters beyond tidiness

The move let attic's GC work again. Its first run on Postgres marked about 1.06M
chunks that no NAR references as Deleted, on top of 232k left over from SQLite,
and it deletes up to 65,535 of them per run, every 12 hours. On 2026-10-06 there
were 1,227,655 Deleted and 692,244 valid chunks, so the backlog clears around
mid-October.

**Every chunk file GC deletes stays on disk, held by the snapshot.** That is why
the snapshot's `USED` grows. The roughly 44 GB that GC is freeing (35 GB of
unreferenced chunks and 9.6 GB of Deleted ones, measured at the cutover) is only
returned once the snapshot is destroyed. The snapshot also holds its own copy of
`server.db`, so deleting the file frees nothing until the snapshot goes too.

## When it is safe

After a week on Postgres without trouble, so **on or after 2026-10-12** (agreed
with Will on 2026-10-06), and once these hold:

1. **No database errors since the cutover.** This should print nothing:
   ```sh
   ssh root@mini-nas.forge.local 'journalctl -u atticd --since "2026-10-05 19:31" --no-pager | grep -E "ERROR|WARN"'
   ```
2. **GC is making progress:** the Deleted count is falling run by run.
   ```sh
   ssh root@mini-nas.forge.local "cd / && setpriv --reuid=postgres --regid=postgres --init-groups -- psql -X -d atticd -Atc \"select state, count(*) from chunk group by state\""
   ```
3. **No branch deploys atticd onto SQLite.** A branch from before the move
   points atticd at SQLite. While `server.db` exists, that means a stale cache.
   Once it is deleted, `mode=rwc` creates an empty one, and every client
   silently misses. On 2026-10-06 the local `backups` had merged `main`
   (`9a94ea8`), but `origin/backups` had not. Check that whatever is deployed
   from contains `594f035`:
   ```sh
   git -C ~/repositories/mini-nas merge-base --is-ancestor 594f035 backups && echo ok
   ```

## Cleanup

```sh
ssh root@mini-nas.forge.local '
  rm /var/lib/private/atticd/server.db /var/lib/private/atticd/server.db-wal /var/lib/private/atticd/server.db-shm
  zfs destroy rpool/rpool/var@pre-attic-postgres
  zfs list -o name,used,avail rpool/rpool/var
'
```

Then delete this spec and its entry in `todos/README.md`. Nothing here is
permanently true, so nothing moves into `docs/`.
