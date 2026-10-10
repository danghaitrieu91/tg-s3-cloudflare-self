#!/usr/bin/env bash
# Guarded D1 export used by .github/workflows/backup.yml (and the local restore rehearsal).
#
# Usage: scripts/d1-backup.sh <local|remote> <out-dir> [previous-counts.json]
# Writes <out-dir>/backup.sql (one full snapshot: schema + data incl. d1_migrations, WITHOUT
# credentials rows) and <out-dir>/counts.json. Prints counts only, never dump content
# (dumps contain chat IDs, object keys and share tokens).
#
# The dump is verified by restoring it into a scratch local D1; the counts come from that
# restore, i.e. from what was actually stored. The run is refused (exit 1) when the restored
# `objects` count dropped to 0 or below 50% of the previous good run, so a lost or wiped
# database never overwrites good backups. Without a previous counts file (first run, e.g. a
# fresh fork) any count is accepted.
#
# Restore into an EMPTY database: `wrangler d1 execute <db> --remote --file backup.sql`,
# then `wrangler d1 migrations apply <db> --remote` (applies only migrations newer than the dump).
set -euo pipefail

MODE="${1:?usage: d1-backup.sh <local|remote> <out-dir> [previous-counts.json]}"
OUT="${2:?missing out-dir}"
PREV="${3:-}"
DB="${D1_NAME:-tg-s3-self-db}"
case "$MODE" in local|remote) ;; *) echo "mode must be local or remote" >&2; exit 2 ;; esac

mkdir -p "$OUT"
VERIFY="$OUT/verify-state"
rm -rf "$VERIFY"

# One export = one consistent snapshot (schema and data cannot drift apart)
npx wrangler d1 export "$DB" "--$MODE" -y --output "$OUT/raw.sql" >/dev/null
# S3 secrets are not copied; every credentials row is a single INSERT line in the dump.
# The scratch restore below fails loudly if a filtered row ever spanned several lines.
grep -v '^INSERT INTO "credentials"' "$OUT/raw.sql" > "$OUT/backup.sql" || true
rm -f "$OUT/raw.sql"

# Verify: restore into a scratch local database and count what was stored
npx wrangler d1 execute "$DB" --local --persist-to "$VERIFY" --file "$OUT/backup.sql" >/dev/null
counts_json="$(npx wrangler d1 execute "$DB" --local --persist-to "$VERIFY" --json --command \
  "SELECT (SELECT count(*) FROM objects) AS objects, (SELECT count(*) FROM buckets) AS buckets, (SELECT count(*) FROM d1_migrations) AS migrations, (SELECT count(*) FROM credentials) AS credentials")"
rm -rf "$VERIFY"
COUNTS="$(printf '%s' "$counts_json" | node -e "
  const r = JSON.parse(require('fs').readFileSync(0, 'utf8'))[0].results[0];
  if (r.credentials !== 0) { console.error('::error::credentials rows leaked into the dump'); process.exit(1); }
  if (r.migrations < 1) { console.error('::error::dump has no d1_migrations rows: not restorable with migrations apply'); process.exit(1); }
  process.stdout.write(JSON.stringify({ objects: r.objects, buckets: r.buckets, migrations: r.migrations, at: new Date().toISOString() }));
")"
echo "Verified dump (restored into scratch D1): $COUNTS"

if [ -n "$PREV" ]; then
  if ! PREV_JSON="$(cat "$PREV")" COUNTS="$COUNTS" node -e "
    const prev = JSON.parse(process.env.PREV_JSON), cur = JSON.parse(process.env.COUNTS);
    console.log('Previous counts: ' + JSON.stringify(prev));
    if (prev.objects > 0 && (cur.objects === 0 || cur.objects < prev.objects * 0.5)) {
      console.log('::error::refusing to overwrite backups: objects ' + prev.objects + ' -> ' + cur.objects +
        ' (delete d1/last-count.json in the backup bucket to accept this deliberately)');
      process.exit(1);
    }
  "; then
    rm -f "$OUT/backup.sql"
    exit 1
  fi
else
  echo "No previous counts: first backup run, accepting current counts"
fi

printf '%s\n' "$COUNTS" > "$OUT/counts.json"
