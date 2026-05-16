---
name: vps-maintenance
description: "Install or update a recurring VPS housekeeping pack on any Linux + Docker VPS \u2014 daily Postgres logical backups, weekly Docker prune, weekly DB retention cleanup, and a 5-min memory pressure alert to Slack or Telegram. Use when the user says \"set up vps maintenance\", \"/vps-maintenance\", \"install housekeeping crons\", \"add backup cron\", \"add docker cleanup cron\", \"add memory alert\", \"set up retention cleanup\", \"harden this vps\", or when a new VPS is being commissioned and needs the standard ops baseline."
---

# /vps-maintenance — VPS Housekeeping Pack

You install a proven, idempotent maintenance baseline on a Docker-based VPS. It targets the three most common failure modes on long-lived single-node Docker hosts:

1. **Postgres killed mid-write** (no swap → OOM → corrupted WAL → DB unbootable). Mitigated by the memory alert and reduced by daily logical backups that restore faster than disk-level snapshots.
2. **Silent Docker bloat** — stopped containers and unused images quietly fill the disk over months until something else can't write.
3. **Unbounded DB growth** — execution logs and message archives that grow forever until queries slow down or backups become unmanageable.

**What gets installed:**

| Script | Schedule | Purpose |
|---|---|---|
| `memory_alert.sh` | `*/5 * * * *` | Alert if `MemAvailable < threshold MB`, debounced 30 min |
| `pg_backup.sh` | `30 3 * * *` | Daily `pg_dumpall`, gzipped, N-day retention in `/var/backups/postgres/` |
| `docker_cleanup.sh` | `0 2 * * 6` (Sat) | Prune stopped containers >48h, dangling + tagged-unused images >7d, unused networks |
| `retention_cleanup.sh` | `0 4 * * 0` (Sun) | Delete DB rows older than N days from configured tables, then `VACUUM ANALYZE` |

This skill is **idempotent**: re-running updates existing scripts in place and rewrites the cron lines without duplicating them. Safe to run on a fresh VPS or one that already has some of these scripts.


## PHASE 0 — INTERVIEW

Ask the user these questions in one message, with sensible defaults shown. Skip anything they've already provided.

1. **VPS connection** — SSH host + auth (one of):
   - `root@<ip>` with password (will use `sshpass`)
   - `root@<ip>` with SSH key (specify path)
   - "this machine" (run locally, no SSH)
2. **Notification channel** for memory alerts — Slack webhook URL **or** Telegram bot token + chat ID. Default to Slack if they've used it elsewhere in the conversation.
3. **Postgres**: is there a running Postgres container? If yes, what name pattern (default: matches `postgres_postgres` or `postgres`). If no Postgres, skip `pg_backup.sh` and `retention_cleanup.sh`.
4. **Memory threshold MB** (default `200`)
5. **DB retention days** (default `60`)
6. **Backup retention days** (default `14`)
7. **Tables to clean up** — auto-detect (see Phase 2 detection) or specify.

If something is obvious from prior conversation (existing variables, a known-host shortcut the user has set up, environment), do not re-ask.


## PHASE 1 — PREFLIGHT CHECKS

Run these on the target VPS over SSH (or locally). Report any blockers before continuing.

```bash
# 1. Required binaries
for bin in docker curl gzip awk df free; do command -v $bin >/dev/null || echo "MISSING: $bin"; done

# 2. Docker daemon up
docker info >/dev/null 2>&1 && echo "docker OK" || echo "docker NOT running"

# 3. Disk and memory snapshot
df -h /
free -h
swapon --show || echo "no swap"

# 4. Existing cron (we will preserve user's other entries)
crontab -l 2>/dev/null

# 5. Postgres container detection
docker ps --filter "name=postgres" --filter "status=running" --format "{{.Names}}\t{{.Image}}"
```

**Hard blockers — stop and report:**
- Docker not installed or daemon down
- Less than 1 GB free disk (cleanup scripts need scratch space)

**Soft warnings — flag and proceed:**
- No swap configured (recommend adding 2 GB, but don't auto-add unless user agrees)
- Postgres container not found AND user said yes to Postgres earlier — re-ask


## PHASE 2 — DETECT DB CONTENTS TO CLEAN (only if Postgres present)

If the user didn't specify tables, auto-detect known schemas. Connect via `docker exec <pg> psql -U postgres -l` and look for:

| Database name pattern | Inferred app | Cleanup target |
|---|---|---|
| `n8n*`, `n8n_queue` | n8n | `execution_entity` (+ FK children) on column `startedAt` |
| `evolution` | Evolution API | `Message` (+ FK children: `MessageUpdate`, `Media`) on `to_timestamp("messageTimestamp")` |
| `chatwoot*` | Chatwoot | NOT touched by default — message archival is non-trivial. Ask if they want it. |

For each detected target, run a preview query and show the user counts before scheduling deletions:

```sql
-- example for evolution
SELECT count(*) AS total,
       count(*) FILTER (WHERE to_timestamp("messageTimestamp") < now() - interval '60 days') AS to_delete
FROM "Message";
```

If the numbers look surprising (e.g. 90% of rows would be deleted), confirm with the user before proceeding.


## PHASE 3 — INSTALL SCRIPTS

Create `/usr/local/sbin/` files via heredoc. Use the templates below, substituting:
- `{{SLACK_URL}}` or `{{TG_TOKEN}}` + `{{TG_CHAT}}`
- `{{MEM_THRESHOLD_MB}}`
- `{{BACKUP_RETENTION_DAYS}}`
- `{{DB_RETENTION_DAYS}}`
- `{{CLEANUP_SQL_EVOLUTION}}`, `{{CLEANUP_SQL_N8N}}` — leave the relevant blocks, drop the unused ones

After writing each file, run `chmod +x` and execute it once to verify.

### Script 1 — `/usr/local/sbin/memory_alert.sh`

```bash
#!/bin/bash
# Alert when available memory < THRESHOLD_MB. Debounced to once per DEBOUNCE_MIN.
set -euo pipefail

# Pick ONE of these notification blocks at install time:
SLACK_URL="{{SLACK_URL}}"
# TG_TOKEN="{{TG_TOKEN}}"; TG_CHAT="{{TG_CHAT}}"

THRESHOLD_MB={{MEM_THRESHOLD_MB}}
DEBOUNCE_MIN=30
STATE_FILE=/var/run/memory_alert.last
HOSTNAME_SHORT=$(hostname -s)

AVAIL_KB=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
AVAIL_MB=$((AVAIL_KB / 1024))
TOTAL_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
TOTAL_MB=$((TOTAL_KB / 1024))
SWAP_USED_KB=$(awk '/^SwapTotal:/ {tot=$2} /^SwapFree:/ {free=$2} END {print tot-free}' /proc/meminfo)
SWAP_USED_MB=$((SWAP_USED_KB / 1024))

[ "$AVAIL_MB" -ge "$THRESHOLD_MB" ] && exit 0

if [ -f "$STATE_FILE" ]; then
  LAST=$(cat "$STATE_FILE"); NOW=$(date +%s)
  [ $(( (NOW - LAST) / 60 )) -lt "$DEBOUNCE_MIN" ] && exit 0
fi

TOP=$(ps -eo rss,pid,comm --sort=-rss | head -6 | awk 'NR>1 {printf "  %s MB  %s\n", int($1/1024), $3}')

MSG=":rotating_light: *Low memory on ${HOSTNAME_SHORT}*
Available: *${AVAIL_MB} MB* / ${TOTAL_MB} MB (threshold: ${THRESHOLD_MB} MB)
Swap used: ${SWAP_USED_MB} MB
Top processes:
\`\`\`
${TOP}
\`\`\`"

# Slack:
PAYLOAD=$(printf '{"text":%s}' "$(printf "%s" "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")")
curl -sfX POST -H "Content-Type: application/json" -d "$PAYLOAD" "$SLACK_URL" >/dev/null || true

# Telegram (uncomment + comment Slack block):
# curl -sf -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
#   -d "chat_id=${TG_CHAT}" -d "parse_mode=Markdown" --data-urlencode "text=${MSG}" >/dev/null || true

date +%s > "$STATE_FILE"
```

**Smoke test:** temporarily lower the threshold to `current_avail + 50 MB`, run the script, then restore the real threshold. Confirm a message arrived in Slack/Telegram.

### Script 2 — `/usr/local/sbin/pg_backup.sh`

```bash
#!/bin/bash
# Daily logical backup of all Postgres databases. Retains N days.
set -euo pipefail

BACKUP_DIR=/var/backups/postgres
RETENTION_DAYS={{BACKUP_RETENTION_DAYS}}
TS=$(date -u +%Y%m%d_%H%M%S)
LOG=$BACKUP_DIR/backup.log
mkdir -p "$BACKUP_DIR"

echo "[$(date -u +%FT%TZ)] backup start ts=$TS" >> "$LOG"

PG_CID=$(docker ps --filter "name=postgres" --filter "status=running" --format "{{.ID}}" | head -1)
if [ -z "$PG_CID" ]; then
  echo "[$(date -u +%FT%TZ)] ERROR: no postgres container running" >> "$LOG"; exit 1
fi

OUT="$BACKUP_DIR/pg_dumpall_${TS}.sql.gz"
if docker exec "$PG_CID" pg_dumpall -U postgres --clean --if-exists | gzip -9 > "$OUT.tmp"; then
  mv "$OUT.tmp" "$OUT"
  echo "[$(date -u +%FT%TZ)] backup OK size=$(du -h "$OUT" | cut -f1) file=$OUT" >> "$LOG"
else
  rm -f "$OUT.tmp"
  echo "[$(date -u +%FT%TZ)] ERROR: pg_dumpall failed" >> "$LOG"; exit 2
fi

find "$BACKUP_DIR" -maxdepth 1 -name "pg_dumpall_*.sql.gz" -mtime +$RETENTION_DAYS -delete
echo "[$(date -u +%FT%TZ)] retained=$(ls -1 "$BACKUP_DIR"/pg_dumpall_*.sql.gz 2>/dev/null | wc -l)" >> "$LOG"
```

**Smoke test:** run once, confirm `/var/backups/postgres/pg_dumpall_*.sql.gz` exists, size is reasonable (typically tens to hundreds of MB).

### Script 3 — `/usr/local/sbin/docker_cleanup.sh`

```bash
#!/bin/bash
# Weekly: prune stopped containers >48h, dangling + tagged-unused images >7d, unused networks.
# Never touches volumes or running containers.
set -euo pipefail

LOG=/var/log/docker_cleanup.log
TS=$(date -u +%FT%TZ)
DISK_BEFORE=$(df / | awk 'NR==2 {print $3}')

echo "[$TS] docker cleanup start" >> "$LOG"

docker container prune -f --filter "until=48h" >> "$LOG" 2>&1 || true
docker image prune -f >> "$LOG" 2>&1 || true
docker image prune -a -f --filter "until=168h" >> "$LOG" 2>&1 || true
docker network prune -f --filter "until=168h" >> "$LOG" 2>&1 || true

DISK_AFTER=$(df / | awk 'NR==2 {print $3}')
FREED_MB=$(( (DISK_BEFORE - DISK_AFTER) / 1024 ))
DISK_PCT=$(df -h / | awk 'NR==2 {print $5}')

echo "[$TS] freed=${FREED_MB}MB disk_used=${DISK_PCT}" >> "$LOG"
echo "---" >> "$LOG"
```

**Smoke test:** run once, check `tail /var/log/docker_cleanup.log` for the `freed=` line.

### Script 4 — `/usr/local/sbin/retention_cleanup.sh`

This one is **per-app**. Include only the blocks that match what Phase 2 detected. The example below has both n8n and evolution blocks — drop whichever doesn't apply.

```bash
#!/bin/bash
# Weekly: prune app data older than RETENTION_DAYS. DELETE + VACUUM ANALYZE (no exclusive lock).
set -euo pipefail

RETENTION_DAYS={{DB_RETENTION_DAYS}}
LOG=/var/log/retention_cleanup.log
TS=$(date -u +%FT%TZ)

echo "[$TS] cleanup start (retention=$RETENTION_DAYS days)" >> "$LOG"

PG_CID=$(docker ps --filter "name=postgres" --filter "status=running" --format "{{.ID}}" | head -1)
if [ -z "$PG_CID" ]; then
  echo "[$TS] ERROR: no postgres container running" >> "$LOG"; exit 1
fi

# --- evolution block (drop if no evolution DB) ---
EV_DELETED=$(docker exec "$PG_CID" psql -U postgres -d evolution -t -A -c "
WITH doomed AS (
  SELECT id FROM \"Message\" WHERE to_timestamp(\"messageTimestamp\") < now() - interval '$RETENTION_DAYS days'
),
_u AS (DELETE FROM \"MessageUpdate\" WHERE \"messageId\" IN (SELECT id FROM doomed) RETURNING 1),
_m AS (DELETE FROM \"Media\" WHERE \"messageId\" IN (SELECT id FROM doomed) RETURNING 1),
_msg AS (DELETE FROM \"Message\" WHERE id IN (SELECT id FROM doomed) RETURNING 1)
SELECT (SELECT count(*) FROM _msg);
" 2>&1 | tr -d ' ')
echo "[$TS] evolution: deleted_messages=$EV_DELETED" >> "$LOG"
docker exec "$PG_CID" psql -U postgres -d evolution -c "VACUUM ANALYZE \"Message\", \"MessageUpdate\", \"Media\"" >/dev/null 2>&1

# --- n8n block (drop if no n8n DB) ---
N8N_DELETED=$(docker exec "$PG_CID" psql -U postgres -d n8n_queue -t -A -c "
WITH doomed AS (
  SELECT id FROM execution_entity WHERE \"startedAt\" < now() - interval '$RETENTION_DAYS days'
),
_d AS (DELETE FROM execution_data WHERE \"executionId\" IN (SELECT id FROM doomed) RETURNING 1),
_m AS (DELETE FROM execution_metadata WHERE \"executionId\" IN (SELECT id FROM doomed) RETURNING 1),
_a AS (DELETE FROM execution_annotations WHERE \"executionId\" IN (SELECT id FROM doomed) RETURNING 1),
_e AS (DELETE FROM execution_entity WHERE id IN (SELECT id FROM doomed) RETURNING 1)
SELECT (SELECT count(*) FROM _e);
" 2>&1 | tr -d ' ')
echo "[$TS] n8n: deleted_executions=$N8N_DELETED" >> "$LOG"
docker exec "$PG_CID" psql -U postgres -d n8n_queue -c "VACUUM ANALYZE execution_data, execution_entity" >/dev/null 2>&1

EV_SIZE=$(docker exec "$PG_CID" psql -U postgres -t -A -c "SELECT pg_size_pretty(pg_database_size('evolution'))")
N8N_SIZE=$(docker exec "$PG_CID" psql -U postgres -t -A -c "SELECT pg_size_pretty(pg_database_size('n8n_queue'))")
DISK=$(df -h / | awk 'NR==2 {print $5" used"}')
echo "[$TS] sizes: evolution=$EV_SIZE n8n=$N8N_SIZE disk=$DISK" >> "$LOG"
echo "---" >> "$LOG"
```

**Smoke test:** run once, check `tail /var/log/retention_cleanup.log` for non-error output.


## PHASE 4 — INSTALL CRON (IDEMPOTENT)

Always preserve existing user crons. Use this pattern to add/update each entry:

```bash
crontab -l 2>/dev/null > /tmp/cron.tmp || true
grep -v "memory_alert\|pg_backup\|docker_cleanup\|retention_cleanup" /tmp/cron.tmp > /tmp/cron.new || true
cat >> /tmp/cron.new <<'EOF'
*/5 * * * * /usr/local/sbin/memory_alert.sh
30 3 * * * /usr/local/sbin/pg_backup.sh
0 2 * * 6 /usr/local/sbin/docker_cleanup.sh
0 4 * * 0 /usr/local/sbin/retention_cleanup.sh
EOF
crontab /tmp/cron.new
crontab -l
```

**Why this schedule:**
- Memory alert every 5 min — quick reaction without spam (the script self-debounces)
- Daily backup at 03:30 UTC — low-traffic window for most use cases
- Docker cleanup Saturday 02:00 — well before Sunday's retention work
- Retention cleanup Sunday 04:00 — runs *after* a fresh daily backup, so the pre-cleanup state is preserved on disk

If the user is in a non-UTC primary timezone and these conflict with peak hours, adjust by adding or subtracting hours uniformly.


## PHASE 5 — REPORT

Print a final table:

```
Installed scripts:
  /usr/local/sbin/memory_alert.sh        (alerts to <channel>, threshold <N> MB)
  /usr/local/sbin/pg_backup.sh           (retention <N> days, ~<X> MB per run)
  /usr/local/sbin/docker_cleanup.sh      (freed <X> MB on first run)
  /usr/local/sbin/retention_cleanup.sh   (<N> day window, would have deleted <X> rows)

Cron entries:
  */5 * * * * memory_alert.sh
  30 3 * * *  pg_backup.sh
  0 2 * * 6   docker_cleanup.sh
  0 4 * * 0   retention_cleanup.sh

Logs:
  /var/backups/postgres/backup.log
  /var/log/docker_cleanup.log
  /var/log/retention_cleanup.log
  (memory_alert.sh writes nothing on success — silence = healthy)

Next time you want to inspect: `tail /var/log/*cleanup.log /var/backups/postgres/backup.log`
```


## EDGE CASES

**Multiple Postgres containers** — `pg_backup.sh` and `retention_cleanup.sh` use `--filter "name=postgres"`. If the user runs more than one (e.g. separate Chatwoot Postgres), tighten the filter to a specific name during install (e.g. `--filter "name=postgres_postgres"`).

**Postgres user/password is not `postgres`** — the scripts assume `psql -U postgres` works inside the container (peer auth or `POSTGRES_USER=postgres`). If different, add `PGUSER=` and `PGPASSWORD=` env vars to the script header.

**No swap on VPS** — recommend `fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile`, persist via `/etc/fstab`, and set `vm.swappiness=10`. Do NOT auto-apply — ask first.

**`/var/log/journal` is huge** — common on long-uptime VPSes. Suggest `journalctl --vacuum-size=500M` + persisting `SystemMaxUse=500M` in `/etc/systemd/journald.conf`. Not part of the cron pack because it's a one-shot fix.

**Skill re-run on already-installed VPS** — totally fine. Scripts get overwritten with current config (any threshold/retention changes the user wanted), cron is deduped via grep -v. The user's other cron entries (unrelated to this pack) are preserved.

**No Postgres** — skip `pg_backup.sh` and `retention_cleanup.sh` entirely. The memory alert and docker cleanup still provide most of the value.

**Non-Docker Postgres (host-installed)** — `pg_backup.sh` and `retention_cleanup.sh` won't work as written. Adapt by replacing `docker exec <PG_CID> psql ...` with direct `psql ...` and setting `PGUSER`/`PGPASSWORD`/`PGHOST` env vars in the script.

**Selinux / AppArmor** — `cron` may need an extra label to run docker commands. If `docker_cleanup.sh` works manually but silently fails from cron, check `audit.log` and add the appropriate policy.

**SystemD timers as cron alternative** — if the host disables `cron` in favor of systemd, convert each entry to a `.service` + `.timer` pair. The script bodies don't change.
