#!/bin/bash
set -e  # (no -u, because /root/.bashrc can reference unset vars)

LOG_FILE="$(mktemp -t horizon-backup.XXXXXX.log)"

post_webhook_json() {
  local text="$1"
  [ -z "${BACKUP_WEBHOOK:-}" ] && return 0

  local payload
  payload="$(python3 - <<'PY'
import json, sys
print(json.dumps({"content": sys.stdin.read()}))
PY
<<<"$text")"

  curl -fsS -X POST -H "Content-Type: application/json" \
    --data-binary "$payload" \
    "$BACKUP_WEBHOOK" >/dev/null
}


send_webhook() {
  local exit_code=$?
  local status="SUCCESS"
  [ "$exit_code" -ne 0 ] && status="FAIL (exit $exit_code)"

  # No webhook? Nothing to do.
  if [ -z "${BACKUP_WEBHOOK:-}" ]; then
    echo "[webhook] BACKUP_WEBHOOK not set; skipping."
    return $exit_code
  fi

  echo "[webhook] Sending logs to webhook ($status)..."

  # 1) Try sending the log as a file (multipart). This avoids JSON escaping entirely.
  if curl -fsS -X POST \
      -F "file=@${LOG_FILE};type=text/plain" \
      -F "content=horizon-database-backup run: ${status} (host: $(hostname), time: $(date -Is))" \
      "$BACKUP_WEBHOOK" >/dev/null; then
    echo "[webhook] Sent log file successfully."
    return $exit_code
  fi

  # 2) If file upload failed, try sending truncated plain text as JSON, with safe escaping (python).
  #    This works for Discord-style webhooks that accept {"content": "..."}.
  local tail_text
  tail_text="$(tail -n 1800 "$LOG_FILE")"

  local json
  json="$(python3 - <<'PY'
import json, os, sys
content = sys.stdin.read()
print(json.dumps({"content": content}))
PY
  <<<"horizon-database-backup run: ${status} (host: $(hostname), time: $(date -Is))\n\n----- LOG (tail) -----\n${tail_text}"
  )"

  curl -fsS -X POST \
    -H "Content-Type: application/json" \
    --data-binary "$json" \
    "$BACKUP_WEBHOOK" >/dev/null && \
    echo "[webhook] Sent truncated log text successfully." || \
    echo "[webhook] Failed to send logs (webhook returned an error)."

  return $exit_code
}

trap send_webhook EXIT

# log everything (stdout+stderr) to file and console
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Starting backup: $(date -Is) ==="
echo "Host: $(hostname)"
echo "PWD:  $(pwd)"
echo "===================================="

# Prefer a dedicated env file over .bashrc (safer for scripts).
# If you MUST use .bashrc, do it in a way that won't explode if it references unset vars.
if [ -f /root/.bashrc ]; then
  # Temporarily disable nounset just for sourcing, in case caller enabled it.
  set +u
  source /root/.bashrc
  set -u 2>/dev/null || true
fi

cd /root/horizon-uya-prod/horizon-database-backup

docker build . -t horizon-database-backup

docker run --rm \
  -e SERVER_NAME="$HORIZON_DB_SERVER" \
  -e DATABASE_NAME="$HORIZON_DB_NAME" \
  -e SQLCMD_USER="$HORIZON_DB_USER" \
  -e SQLCMD_PASSWORD="$HORIZON_MSSQL_SA_PASSWORD" \
  -e BACKUP_PATH=/ \
  -e MODE=backup \
  horizon-database-backup

AWS_ACCESS_KEY_ID="$BACKUP_AWS_ACCESS_KEY_ID" \
AWS_SECRET_ACCESS_KEY="$BACKUP_AWS_SECRET_ACCESS_KEY" \
AWS_DEFAULT_REGION="$BACKUP_AWS_REGION" \
aws s3 sync "$DATABASE_BACKUP_LOC" "$DATABASE_BACKUP_S3_DEST" \
  --exact-timestamps \
  --no-progress

echo "=== Finished: $(date -Is) ==="
# --- S3 stats + second webhook call ---
echo "=== S3 stats ==="

# Compute UTC cutoff epoch for 48 hours ago (GNU date on Ubuntu)
CUTOFF_EPOCH="$(date -u -d '48 hours ago' +%s)"

# Use a temp file to avoid pipe/subshell gotchas
S3_LS_FILE="$(mktemp -t horizon-s3ls.XXXXXX.txt)"

# Do not let stats failure kill the whole script
set +e
AWS_ACCESS_KEY_ID="$BACKUP_AWS_ACCESS_KEY_ID" \
AWS_SECRET_ACCESS_KEY="$BACKUP_AWS_SECRET_ACCESS_KEY" \
AWS_DEFAULT_REGION="$BACKUP_AWS_REGION" \
aws s3 ls "$DATABASE_BACKUP_S3_DEST" --recursive >"$S3_LS_FILE" 2>>"$LOG_FILE"
LS_RC=$?
set -e

if [ "$LS_RC" -ne 0 ]; then
  echo "[s3-stats] aws s3 ls failed (rc=$LS_RC). Skipping stats."
else
  # Total files = count lines that look like: YYYY-MM-DD HH:MM:SS <size> <key>
  TOTAL_COUNT="$(awk 'NF >= 4 && $1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ && $2 ~ /^[0-9]{2}:[0-9]{2}:[0-9]{2}$/ {c++} END{print c+0}' "$S3_LS_FILE")"

  # Recent 48h count by converting each line’s date+time to epoch
  RECENT_48H_COUNT="$(
    awk -v cutoff="$CUTOFF_EPOCH" '
      NF >= 4 && $1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ && $2 ~ /^[0-9]{2}:[0-9]{2}:[0-9]{2}$/ {
        cmd = "date -u -d \"" $1 " " $2 "\" +%s"
        cmd | getline t
        close(cmd)
        if (t >= cutoff) r++
      }
      END { print r+0 }
    ' "$S3_LS_FILE"
  )"

  echo "S3 location: $DATABASE_BACKUP_S3_DEST"
  echo "Total files: $TOTAL_COUNT"
  echo "Files modified in last 48h: $RECENT_48H_COUNT"

  # Post stats as a NEW webhook message
  if [ -n "${BACKUP_WEBHOOK:-}" ]; then
    STATS_TEXT=$(
      cat <<EOF
Backup S3 stats (host: $(hostname), time: $(date -Is))
S3 location: $DATABASE_BACKUP_S3_DEST
Total files: $TOTAL_COUNT
Files modified in last 48h: $RECENT_48H_COUNT
EOF
    )

# Post stats as a NEW webhook message (multipart, same as the working log upload)
curl -fsS -X POST \
  -F "content=$STATS_TEXT" \
  "$BACKUP_WEBHOOK" >/dev/null || true

  fi
fi
