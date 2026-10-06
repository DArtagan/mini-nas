# Outstanding work

Transient work specs. Each is self-contained: enough verified context to start a
session cold, plus a prompt to open with.

These are **not** documentation of the running system; see [`docs/`](../docs/)
for that. When a piece of work lands, whatever it leaves behind that is
permanently true gets written into `docs/` (or `CLAUDE.md`), and the spec here
is deleted. A file sitting in this directory means the work has not been done.

## Open

**[attic-rollback-cleanup.md](attic-rollback-cleanup.md) — delete the SQLite rollback point**
The Postgres move kept atticd's old SQLite database and a snapshot of `/var` as
a way back. The snapshot also pins every chunk file attic's GC deletes, so the
~44 GB that GC is reclaiming is not actually freed until it goes. Waiting on a
week of atticd running cleanly on Postgres.

## Writing a spec

What makes these useful when opened cold, months later:

- **State what was verified and when.** "Verified 2026-10-06" beats an assertion
  with no provenance. Anything not checked should say so.
- **Record why, not just what.** A future session that knows why an approach was
  rejected will not re-propose it.
- **Include the prompt.** Ending with the literal text to open a session with
  removes the work of reconstructing intent.
- **Note decisions already made, and by whom.** Where the user has expressed a
  preference, record it verbatim so it is not relitigated.
- **Be honest about wrong turns.** Inheriting bad reasoning is worse than
  inheriting no reasoning.
