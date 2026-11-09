#!/usr/bin/env bash
# Záloha databáze a nahraných obrázků. Spouští se z cronu (viz README), jde i ručně: ./backup.sh
#
# Vytvoří ve složce BACKUP_DIR (výchozí ./backups):
#   dobrotrh_db_<datum>.dump          databáze (pg_dump, vlastní formát pro pg_restore)
#   dobrotrh_uploads_<datum>.tar.gz   volume s nahranými obrázky
# a smaže zálohy starší než KEEP_DAYS dní (výchozí 14).
set -euo pipefail

cd "$(dirname "$0")"
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

BACKUP_DIR="${BACKUP_DIR:-./backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"
STAMP="$(date +%Y-%m-%d_%H%M)"

# Zálohy obsahují osobní údaje a hesla (hashe), čte je jen vlastník.
umask 077
mkdir -p "$BACKUP_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

db_file="$BACKUP_DIR/dobrotrh_db_$STAMP.dump"
uploads_file="$BACKUP_DIR/dobrotrh_uploads_$STAMP.tar.gz"

cleanup() { rm -f "$db_file.part" "$uploads_file.part"; }
trap cleanup EXIT

log "Záloha databáze -> $db_file"
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > "$db_file.part"
# Kontrola, že dump je čitelný (jinak by se poškozená záloha tiše uložila).
docker compose exec -T db pg_restore --list < "$db_file.part" > /dev/null
mv "$db_file.part" "$db_file"

log "Záloha obrázků -> $uploads_file"
docker compose exec -T backend tar -C /app/static -czf - uploads > "$uploads_file.part"
gzip -t "$uploads_file.part"
mv "$uploads_file.part" "$uploads_file"

log "Mažu zálohy starší než $KEEP_DAYS dní"
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'dobrotrh_*' -mtime "+$KEEP_DAYS" -print -delete

log "Hotovo ($(du -h "$db_file" | cut -f1) databáze, $(du -h "$uploads_file" | cut -f1) obrázky)"
