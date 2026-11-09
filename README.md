# mendelu_auction_infrastructure

Produkční nasazení aplikace přes Docker Compose na serveru `dobrotrhonline.mendelu.cz`.

```
internet ──80/443──> Apache (hostitel: doména, HTTPS certifikát od CESNETu)
                         │  http://127.0.0.1:8080
                         ▼
                     nginx (Docker) ──/api, /static, /ws──> backend
                                    └─ ostatní ───────────> frontend
```

| Služba          | Co dělá                                                         |
|-----------------|-----------------------------------------------------------------|
| `reverse-proxy` | nginx, poslouchá jen na `127.0.0.1:8080`, rozděluje provoz mezi backend a frontend |
| `frontend`      | build Reactu (image z ghcr.io)                                  |
| `migrate`       | při startu spustí `alembic upgrade head` a skončí               |
| `backend`       | FastAPI (image z ghcr.io)                                       |
| `db`            | PostgreSQL 15                                                   |

Data jsou v Docker volumes: `postgres_data` (databáze) a `uploads` (nahrané obrázky).

## Apache (jednorázově)

Konfigurace pro Apache je v [apache/dobrotrh.conf](apache/dobrotrh.conf), postup instalace je
v hlavičce souboru. Používá certifikát od CESNETu, který admini nahráli do `/root/certs/cesnet/2026/`
(`server.pem` certifikát, `chain.pem` mezilehlé certifikáty, `serverkey.pem` klíč).
Při obnově certifikátu stačí v konfiguraci změnit cesty a `sudo systemctl reload apache2`.

Apache:
- přeposílá celou doménu na `http://127.0.0.1:8080/` s `ProxyPreserveHost On`,
- propouští websockety (`upgrade=websocket`, živé příhozy na `/ws/`),
- posílá `X-Forwarded-Proto: https` (jinak backend nenastaví přihlašovací cookie jako Secure).

Skutečnou IP návštěvníka bere nginx z hlavičky `X-Forwarded-For`, kterou Apache doplňuje sám
(rate limiting přihlášení a registrace na backendu).

## První nasazení

1. **Port 8080** na serveru musí být volný (`sudo ss -tlnp | grep :8080`). Pokud ne, změňte port
   v `compose.yml` i v konfiguraci Apache.
2. **Konfigurace:**
   ```bash
   cp .env.example .env
   nano .env
   ```
   Hlavně `FRONTEND_URL` (`https://dobrotrhonline.mendelu.cz`), hesla, `SECRET_KEY` a SMTP.
3. **Přístup k images:** pokud jsou balíčky na ghcr.io soukromé, přihlaste se jednou
   tokenem s oprávněním `read:packages`:
   ```bash
   docker login ghcr.io -u <github-uživatel>
   ```
4. **Spuštění:**
   ```bash
   docker compose pull
   docker compose up -d
   ```
5. **Kontrola na serveru** (ještě bez Apache): `curl -I http://127.0.0.1:8080/` musí vrátit `200`.

## Aktualizace

Po pushi do `main` GitHub Actions jen sestaví a nahraje nové images na ghcr.io.
Na server se nasazují ručně:

```bash
docker compose pull
docker compose up -d
```

Migrace databáze proběhnou automaticky (služba `migrate`) před startem backendu.
Po změně `nginx.conf` stačí `docker compose restart reverse-proxy`.

## Zálohy

[backup.sh](backup.sh) zazálohuje databázi (`pg_dump`) a nahrané obrázky (volume `uploads`)
do `backups/` a smaže zálohy starší než 14 dní. Dump před uložením ověří přes `pg_restore --list`;
když něco selže, skončí chybou a poslední platnou zálohu nepřepíše. Soubory čte jen vlastník
(obsahují osobní údaje). Složka `backups/` je v `.gitignore`.

Ruční záloha:

```bash
./backup.sh
```

**Automaticky každou noc** (`crontab -e` pod uživatelem, který spouští `docker compose`):

```
15 3 * * * /home/xfarlik/dobrotrh/backup.sh >> /home/xfarlik/dobrotrh/backups/backup.log 2>&1
```

Počet dní a složku jde změnit proměnnými, např. `KEEP_DAYS=30 BACKUP_DIR=/srv/zalohy ./backup.sh`.

**Kopie mimo server:** zálohy na stejném serveru nepomůžou, když o server přijdete.
Občas je stáhněte jinam, např. ze svého počítače:

```bash
rsync -av xfarlik@dobrotrhonline.mendelu.cz:dobrotrh/backups/ ~/dobrotrh-zalohy/
```

### Obnova ze zálohy

Přepíše současná data, proto nejdřív udělejte čerstvou zálohu (`./backup.sh`).

```bash
docker compose stop backend
docker compose exec -T db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner' < backups/dobrotrh_db_<datum>.dump
docker compose run --rm --no-deps -T backend tar -C /app/static -xzf - < backups/dobrotrh_uploads_<datum>.tar.gz
docker compose start backend
```

## Užitečné příkazy

```bash
docker compose ps                                  # stav kontejnerů
docker compose logs -f backend                     # logy backendu
docker compose logs -f reverse-proxy               # logy nginx
./backup.sh                                        # záloha DB a obrázků
```
