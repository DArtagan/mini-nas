# shellcheck shell=bash
# One-off: moves atticd's database from SQLite to Postgres. Installed as
# attic-migrate-to-postgres; run it as root, with atticd stopped, between deploying the
# Postgres server and pointing atticd at it.
#
# It copies only what a healthy atticd would hold, so the move is also a clean-up:
# - NARs from failed uploads (state P) stay behind, with their chunkrefs. atticd never
#   reuses or reaps them, and their chunkrefs keep GC from reaping their chunks.
# - holders_count, the number of uploads using a row, starts at 0. Decrements lost to
#   SQLite's pool timeouts left most chunks held, and GC skips held chunks.
# - Chunks from failed uploads (P) become Deleted, so GC removes them. Deleted chunks
#   whose file is already gone stay behind: GC fails to delete the file, so it retries
#   those same chunks every run and never reaches the rest.
#
# To run it again, empty the database first:
#   setpriv --reuid=postgres --regid=postgres --init-groups psql -c 'drop database atticd'
#   systemctl restart postgresql-setup

: "${ATTICD:?path to atticd}" "${ATTICD_CONFIG:?atticd config that points at Postgres}"
: "${ATTICD_ENV:?atticd environment file}"
cd / # the database roles can't read root's home
sqlite_db=${SQLITE_DB:-/var/lib/atticd/server.db}
storage=${STORAGE:-/var/lib/atticd/storage}
# Commands to run as each database role, overridable to try this against a scratch server.
# (runuser fails here, for want of a PAM service.)
as_postgres=${AS_POSTGRES-setpriv --reuid=postgres --regid=postgres --init-groups --}
as_atticd=${AS_ATTICD-setpriv --reuid=atticd --regid=atticd --init-groups --}

# shellcheck disable=SC2086 # $as_postgres is a command prefix, split on purpose
pg() { $as_postgres psql -X -d atticd -v ON_ERROR_STOP=1 -q -At "$@"; }
lite() { sqlite3 -readonly -csv -nullvalue '\N' "$sqlite_db" "$@"; }

# Loads the rows a query returns, as the superuser so that foreign keys aren't checked
# row by row. Every query below keeps them intact.
copy() {
  local table=$1 columns=$2 query=$3
  echo "Copying $table..."
  lite "$query" | pg -c 'set session_replication_role = replica' \
    -c "\\copy \"$table\" ($columns) from pstdin with (format csv, null '\\N')"
}

if systemctl is-active --quiet atticd; then
  echo "Stop atticd first." >&2
  exit 1
fi

echo "Creating the schema..."
# $as_atticd is a command prefix, split on purpose; the inner shell expands the $n.
# shellcheck disable=SC2086,SC2016
$as_atticd sh -c 'set -a; . "$1"; exec "$2" -f "$3" --mode db-migrations' _ \
  "$ATTICD_ENV" "$ATTICD" "$ATTICD_CONFIG"

if [ "$(pg -c 'select count(*) from nar')" != 0 ]; then
  echo "The Postgres database already has NARs; empty it first (see the top of this script)." >&2
  exit 1
fi

valid_nars="select id from nar where state = 'V'"
copy cache \
  'id, name, keypair, is_public, store_dir, priority, upstream_cache_key_names, created_at, deleted_at, retention_period' \
  'select id, name, keypair, is_public, store_dir, priority, upstream_cache_key_names, created_at, deleted_at, retention_period from cache'
copy nar \
  'id, state, nar_hash, nar_size, compression, num_chunks, holders_count, created_at' \
  "select id, state, nar_hash, nar_size, compression, num_chunks, 0, created_at from nar where state = 'V'"
copy object \
  'id, cache_id, nar_id, store_path_hash, store_path, "references", system, deriver, sigs, ca, created_at, last_accessed_at, created_by' \
  "select id, cache_id, nar_id, store_path_hash, store_path, \"references\", system, deriver, sigs, ca, created_at, last_accessed_at, created_by from object where nar_id in ($valid_nars)"
copy chunk \
  'id, state, chunk_hash, chunk_size, file_hash, file_size, compression, remote_file, remote_file_id, holders_count, created_at' \
  "select id, case state when 'P' then 'D' else state end, chunk_hash, chunk_size, file_hash, file_size, compression, remote_file, remote_file_id, 0, created_at from chunk"
copy chunkref 'id, nar_id, seq, chunk_id' \
  "select id, nar_id, seq, chunk_id from chunkref where nar_id in ($valid_nars)"

# A valid NAR whose chunks aren't all valid can't be served; better to learn of it now.
broken=$(pg -c "select count(*) from chunkref r left join chunk c on c.id = r.chunk_id where c.state is distinct from 'V'")
if [ "$broken" != 0 ]; then
  echo "$broken chunkrefs of valid NARs point at chunks that aren't valid. Stopping before deleting any chunks." >&2
  exit 1
fi

echo "Dropping Deleted chunks whose file is already gone..."
pg -F ' ' -c "select id, remote_file_id from chunk where state = 'D'" |
  while read -r id ref; do
    name=${ref#local:}
    [ -e "$storage/${name:0:1}/${name:0:2}/$name" ] || echo "$id"
  done |
  pg -c 'create temp table gone (id bigint)' -c '\copy gone from pstdin' \
    -c 'delete from chunk where id in (select id from gone)'

echo "Setting the id sequences..."
for table in cache nar object chunk chunkref; do
  pg -c "select setval(pg_get_serial_sequence('\"$table\"', 'id'), coalesce(max(id), 1)) from \"$table\"" >/dev/null
done
pg -c 'vacuum analyze'

echo
echo "table     sqlite  postgres"
for table in cache nar object chunk chunkref; do
  case $table in
    nar) filter="where state = 'V'" ;;
    object | chunkref) filter="where nar_id in ($valid_nars)" ;;
    *) filter="" ;;
  esac
  printf '%-9s %s  %s\n' "$table" "$(lite "select count(*) from $table $filter")" \
    "$(pg -c "select count(*) from \"$table\"")"
done
echo "(chunk: Postgres has fewer by the Deleted chunks it dropped.)"
pg -c "select 'chunks by state: ' || string_agg(state || '=' || n, ' ') from (select state, count(*) n from chunk group by state order by state) s"
