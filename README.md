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

## Užitečné příkazy

```bash
docker compose ps                                  # stav kontejnerů
docker compose logs -f backend                     # logy backendu
docker compose logs -f reverse-proxy               # logy nginx
docker compose exec db pg_dump -U <POSTGRES_USER> <POSTGRES_DB> > zaloha.sql   # záloha DB
```
