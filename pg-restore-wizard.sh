#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo ""; echo "❌ Error happened on line $LINENO"; echo "Check the output above."; exit 1' ERR

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

msg() {
  echo -e "${GREEN}$1${NC}"
}

warn() {
  echo -e "${YELLOW}$1${NC}"
}

fail() {
  echo -e "${RED}$1${NC}"
  exit 1
}

set_env() {
  local KEY="$1"
  local VALUE="$2"

  if grep -qE "^[#[:space:]]*${KEY}[[:space:]]*=" /opt/pasarguard/.env; then
    sed -i -E "s|^[#[:space:]]*${KEY}[[:space:]]*=.*|${KEY}=${VALUE}|" /opt/pasarguard/.env
  else
    echo "${KEY}=${VALUE}" >> /opt/pasarguard/.env
  fi
}

get_env() {
  local KEY="$1"
  grep -E "^${KEY}=" /opt/pasarguard/.env | tail -n1 | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r'
}

echo "=========================================="
echo "      PasarGuard Easy Restore Wizard"
echo "=========================================="
echo

if [ "$(id -u)" != "0" ]; then
  fail "Please run this script as root."
fi

if ! command -v apt >/dev/null 2>&1; then
  fail "This script supports Ubuntu/Debian only."
fi

msg "Installing required packages..."
apt update -y
apt install -y curl unzip rsync zip ca-certificates gnupg lsb-release net-tools iproute2

if ! command -v docker >/dev/null 2>&1; then
  msg "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
else
  msg "Docker already installed."
fi

if ! docker compose version >/dev/null 2>&1; then
  fail "Docker Compose plugin not found. Please check Docker installation."
fi

echo
warn "Backup ZIP must be uploaded to this server, usually inside /root"
echo
echo "Available ZIP files in /root:"
ls -lh /root/*.zip 2>/dev/null || echo "No ZIP file found in /root"
echo

read -rp "Enter backup ZIP path or URL, or press ENTER to use latest ZIP in /root: " BACKUP_INPUT

if [ -z "$BACKUP_INPUT" ]; then
  BACKUP_ZIP="$(ls -t /root/*.zip 2>/dev/null | head -1 || true)"
else
  if [[ "$BACKUP_INPUT" == http://* || "$BACKUP_INPUT" == https://* ]]; then
    BACKUP_ZIP="/root/pasarguard-backup.zip"
    msg "Downloading backup..."
    curl -L "$BACKUP_INPUT" -o "$BACKUP_ZIP"
  else
    BACKUP_ZIP="$BACKUP_INPUT"
  fi
fi

if [ -z "${BACKUP_ZIP:-}" ] || [ ! -f "$BACKUP_ZIP" ]; then
  fail "Backup ZIP not found. Upload it to /root first."
fi

AUTO_IP="$(curl -s4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

echo
read -rp "Enter panel IP or domain [default: $AUTO_IP]: " PANEL_HOST
PANEL_HOST="${PANEL_HOST:-$AUTO_IP}"

read -rp "Enter panel HTTPS port [default: 443]: " PANEL_PORT
PANEL_PORT="${PANEL_PORT:-443}"

if ! [[ "$PANEL_PORT" =~ ^[0-9]+$ ]]; then
  fail "Panel port must be a number."
fi

echo
warn "This will remove current /opt/pasarguard and /var/lib/pasarguard if they exist."
read -rp "Type YES to continue: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
  fail "Cancelled."
fi

msg "Stopping old PasarGuard if exists..."
cd /opt/pasarguard 2>/dev/null && docker compose down || true

msg "Cleaning old files..."
rm -rf /root/pasarguard-restore
rm -rf /opt/pasarguard
rm -rf /var/lib/pasarguard

mkdir -p /root/pasarguard-restore
mkdir -p /opt/pasarguard
mkdir -p /var/lib/pasarguard

msg "Extracting backup..."
unzip -o "$BACKUP_ZIP" -d /root/pasarguard-restore >/dev/null

BACKUP_SRC="$(find /root/pasarguard-restore -name "db_backup.sql" -exec dirname {} \; | head -1)"

if [ -z "$BACKUP_SRC" ]; then
  fail "db_backup.sql not found inside backup."
fi

echo
msg "Backup source found:"
echo "$BACKUP_SRC"
echo

test -f "$BACKUP_SRC/.env" || fail ".env missing in backup"
test -f "$BACKUP_SRC/docker-compose.yml" || fail "docker-compose.yml missing in backup"
test -f "$BACKUP_SRC/db_backup.sql" || fail "db_backup.sql missing in backup"
test -d "$BACKUP_SRC/pasarguard_data" || fail "pasarguard_data folder missing in backup"

msg "Copying backup files..."
cp "$BACKUP_SRC/.env" /opt/pasarguard/.env
cp "$BACKUP_SRC/docker-compose.yml" /opt/pasarguard/docker-compose.yml
cp "$BACKUP_SRC/db_backup.sql" /opt/pasarguard/db_backup.sql
rsync -a "$BACKUP_SRC/pasarguard_data/" /var/lib/pasarguard/

find /var/lib/pasarguard -name "privkey.pem" -exec chmod 600 {} \; 2>/dev/null || true
find /var/lib/pasarguard -name "fullchain.pem" -exec chmod 644 {} \; 2>/dev/null || true

set_env "UVICORN_HOST" "0.0.0.0"
set_env "UVICORN_PORT" "$PANEL_PORT"

cd /opt/pasarguard

DB_NAME="$(get_env DB_NAME)"
DB_USER="$(get_env DB_USER)"

if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ]; then
  fail "DB_NAME or DB_USER not found in .env"
fi

msg "Starting database..."
docker compose up -d timescaledb

msg "Waiting for database..."
for i in {1..60}; do
  if docker compose exec -T timescaledb pg_isready -U "$DB_USER" -d postgres >/dev/null 2>&1; then
    msg "Database is ready."
    break
  fi

  if [ "$i" = "60" ]; then
    fail "Database did not become ready."
  fi

  sleep 2
done

msg "Restoring database..."
docker compose exec -T timescaledb psql -U "$DB_USER" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB_NAME}' AND pid <> pg_backend_pid();" || true
docker compose exec -T timescaledb dropdb -U "$DB_USER" --if-exists "$DB_NAME"
docker compose exec -T timescaledb createdb -U "$DB_USER" -O "$DB_USER" "$DB_NAME"
docker compose exec -T timescaledb psql -U "$DB_USER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS timescaledb;" || true
docker compose exec -T timescaledb psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT timescaledb_pre_restore();" || true
docker compose exec -T timescaledb psql -U "$DB_USER" -d "$DB_NAME" < /opt/pasarguard/db_backup.sql
docker compose exec -T timescaledb psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT timescaledb_post_restore();" || true

msg "Starting PasarGuard..."
docker compose up -d

msg "Installing pasarguard command..."
curl -fsSL https://github.com/PasarGuard/scripts/raw/main/pasarguard.sh -o /tmp/pg.sh
bash /tmp/pg.sh install-script || true

echo
read -rp "Do you want automatic Telegram backup? (y/N): " ENABLE_TG_BACKUP

if [[ "$ENABLE_TG_BACKUP" =~ ^[Yy]$ ]]; then
  echo
  read -rp "Enter Telegram Bot Token: " BOT_TOKEN
  read -rp "Enter Telegram Chat ID: " CHAT_ID
  read -rp "Backup every how many hours? [default: 1]: " BACKUP_HOURS
  BACKUP_HOURS="${BACKUP_HOURS:-1}"

  if ! [[ "$BACKUP_HOURS" =~ ^[0-9]+$ ]]; then
    fail "Backup hours must be a number."
  fi

  cat > /root/.pgbackup.env <<EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
EOF

  chmod 600 /root/.pgbackup.env

  cat > /root/auto-pasarguard-backup.sh <<'BACKUP_EOF'
#!/usr/bin/env bash
set -e

source /root/.pgbackup.env

DATE="$(date +%Y%m%d_%H%M%S)"
TMP_DIR="/root/pasarguard_backup_$DATE"
OUT_ZIP="/root/backup_$DATE.zip"

mkdir -p "$TMP_DIR"

cd /opt/pasarguard

DB_NAME="$(awk -F= '/^DB_NAME=/{gsub(/"/,"",$2); print $2}' .env)"
DB_USER="$(awk -F= '/^DB_USER=/{gsub(/"/,"",$2); print $2}' .env)"

docker compose exec -T timescaledb pg_dump -U "$DB_USER" -d "$DB_NAME" > "$TMP_DIR/db_backup.sql"

cp /opt/pasarguard/.env "$TMP_DIR/.env"
cp /opt/pasarguard/docker-compose.yml "$TMP_DIR/docker-compose.yml"
rsync -a /var/lib/pasarguard/ "$TMP_DIR/pasarguard_data/"

cd /root
zip -qr "$OUT_ZIP" "$(basename "$TMP_DIR")"

SIZE="$(stat -c%s "$OUT_ZIP")"
MAX_SIZE=$((45 * 1024 * 1024))

if [ "$SIZE" -le "$MAX_SIZE" ]; then
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
    -F chat_id="${CHAT_ID}" \
    -F document=@"${OUT_ZIP}" \
    -F caption="PasarGuard Backup $DATE"
else
  split -b 45M -d -a 3 "$OUT_ZIP" "${OUT_ZIP}.part"

  for PART in ${OUT_ZIP}.part*; do
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
      -F chat_id="${CHAT_ID}" \
      -F document=@"${PART}" \
      -F caption="PasarGuard Backup $DATE - $(basename "$PART")"
  done
fi

rm -rf "$TMP_DIR"
find /root -name "backup_*.zip" -mtime +3 -delete
find /root -name "backup_*.zip.part*" -mtime +3 -delete
BACKUP_EOF

  chmod +x /root/auto-pasarguard-backup.sh

  if [ "$BACKUP_HOURS" = "1" ]; then
    CRON_TIME="0 * * * *"
  else
    CRON_TIME="0 */$BACKUP_HOURS * * *"
  fi

  (crontab -l 2>/dev/null | grep -v auto-pasarguard-backup.sh; echo "$CRON_TIME /root/auto-pasarguard-backup.sh >> /var/log/pasarguard-backup.log 2>&1") | crontab -

  msg "Sending test backup to Telegram..."
  /root/auto-pasarguard-backup.sh || warn "Telegram backup test failed. Check token/chat id."
fi

echo
msg "Checking status..."
docker compose ps

echo
msg "Last logs:"
docker compose logs --tail=30 pasarguard || true

echo
echo "=========================================="
echo "✅ Restore finished"
echo "=========================================="
echo
echo "Panel URL:"
echo "https://${PANEL_HOST}:${PANEL_PORT}/dashboard/"
echo
echo "If dashboard shows Not Found, also try:"
echo "https://${PANEL_HOST}:${PANEL_PORT}/"
echo
echo "If browser shows SSL warning:"
echo "Advanced → Proceed"
echo
echo "Useful commands:"
echo "cd /opt/pasarguard && docker compose ps"
echo "cd /opt/pasarguard && docker compose logs --tail=100 pasarguard"
echo "pasarguard status"
echo "=========================================="
