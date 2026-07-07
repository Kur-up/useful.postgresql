# PostgreSQL + PgBouncer

Production-ready PostgreSQL 18 with PgBouncer connection pooler, deployed via Docker Compose.

Both services use **Docker Hardened Images** (`dhi.io`) — minimal, read-only, non-root containers with no shell.

## Architecture

```
Client (app server / DBeaver / psql)
  │
  │  TLS (SCRAM-SHA-256)   port 6432
  ▼
┌─────────────────────────────────────────────────────┐
│  Docker internal network (bridge, no outbound)      │
│                                                     │
│  PgBouncer 1.25.2 ──────────────────► PostgreSQL 18 │
│  (connection pooler)   TCP 5432      (data store)   │
└─────────────────────────────────────────────────────┘
```

- **Clients always connect to PgBouncer** (port 6432), never directly to PostgreSQL.
- **TLS is enforced** on the client → PgBouncer leg. PgBouncer → PostgreSQL uses the Docker internal network (no TLS needed).
- The internal Docker network has `internal: true` — containers have no outbound internet access.

## Prerequisites

| Requirement | Notes |
|---|---|
| Docker Engine 24+ | with Compose v2 plugin |
| `envsubst` | part of `gettext-base` (`apt install gettext-base`) |
| `openssl` | for TLS certificate generation |
| `dhi.io` account | Docker Hardened Images registry — `docker login dhi.io` |

## Quick Start (first deploy)

```bash
# 1. Clone and enter the directory
cd /path/to/postgresql

# 2. Create your .env from the example
cp .env.example .env
# Edit .env — set POSTGRESQL_PASSWORD to a strong random value:
#   openssl rand -base64 32

# 3. Start the stack
# This script will:
#   - generate TLS certificates (prompts for server CN/IP)
#   - render pgbouncer.ini and userlist.txt from .env
#   - run docker compose up -d
./scripts/up.sh
```

After the first run you will be prompted for the **server CN** — the hostname or IP address that clients will use to connect to this server (e.g. `10.0.0.5` or `db.example.com`). The CN is embedded in the TLS certificate.

## Directory Structure

```
.
├── .env                          # secrets — git-ignored, never commit
├── .env.example                  # template — commit this
├── .gitignore
├── docker-compose.yml
├── README.md
│
├── configs/
│   ├── postgresql/
│   │   ├── postgresql.conf       # PostgreSQL server configuration
│   │   └── pg_hba.conf           # host-based authentication rules
│   │
│   └── pgbouncer/
│       ├── pgbouncer.ini.template  # template — commit this
│       ├── pgbouncer.ini           # rendered config — git-ignored
│       ├── userlist.txt            # rendered auth file — git-ignored
│       ├── hba.conf                # IP/user access rules — commit this
│       └── tls/
│           ├── ca.crt              # CA certificate — commit this
│           ├── ca.key              # CA private key — git-ignored
│           ├── server.crt          # server certificate — commit this
│           └── server.key          # server private key — git-ignored
│
├── data/
│   └── postgresql/               # PostgreSQL data directory — git-ignored
│
├── init/                         # SQL/shell scripts run once on first init
│
└── scripts/
    ├── up.sh                     # idempotent startup script
    └── gen-certs.sh              # TLS certificate generator
```

## Configuration

All configuration lives in `.env`. See `.env.example` for the full reference with descriptions.

### Key variables

| Variable | Purpose |
|---|---|
| `POSTGRESQL_DB` | Application database name |
| `POSTGRESQL_USER` | Database superuser |
| `POSTGRESQL_PASSWORD` | Superuser password (use `openssl rand -base64 32`) |
| `PGBOUNCER_PORT` | Port exposed to clients (default: 6432) |
| `PGBOUNCER_POOL_MODE` | `transaction` (recommended) / `session` / `statement` |
| `PGBOUNCER_MAX_CLIENT_CONN` | Max simultaneous client connections |
| `PGBOUNCER_DEFAULT_POOL_SIZE` | Server connections per (db, user) pair |
| `PGBOUNCER_TLS_SSLMODE` | TLS enforcement (`require` / `verify-ca` / `verify-full`) |

For PostgreSQL memory tuning, edit `configs/postgresql/postgresql.conf` directly.

## Scripts

### `./scripts/up.sh`

Idempotent startup — safe to run multiple times.

```bash
./scripts/up.sh           # normal start
./scripts/up.sh --build   # pass extra flags to docker compose up
```

What it does on each run:
1. Checks that `.env` exists
2. Generates TLS certificates if `configs/pgbouncer/tls/server.crt` is missing
3. Generates `userlist.txt` if missing
4. Renders `pgbouncer.ini` from the template if missing
5. Runs `docker compose up -d`

### `./scripts/gen-certs.sh`

Standalone certificate generator.

```bash
./scripts/gen-certs.sh                   # interactive
./scripts/gen-certs.sh 10.0.0.5         # non-interactive
./scripts/gen-certs.sh --force 10.0.0.5 # regenerate existing certs
```

Generates a 4096-bit RSA CA and server certificate with proper SAN (Subject Alternative Names). The CA is valid for 10 years; the server certificate for ~2 years.

## Connecting Clients

### psql

```bash
psql "host=<server-ip> port=6432 dbname=<POSTGRESQL_DB> user=<POSTGRESQL_USER> \
      sslmode=require sslrootcert=/path/to/ca.crt"
```

### Connection string (libpq)

```
postgresql://<user>:<password>@<server-ip>:6432/<dbname>?sslmode=require&sslrootcert=/path/to/ca.crt
```

The `ca.crt` file (`configs/pgbouncer/tls/ca.crt`) must be distributed to clients for certificate verification.

### DBeaver / DataGrip

- Host: `<server-ip>`, Port: `6432`
- Database: value of `POSTGRESQL_DB`
- SSL mode: **Require** (or **Verify CA** if you import `ca.crt`)

## Day-2 Operations

### Update PostgreSQL password

```bash
# 1. Change POSTGRESQL_PASSWORD in .env
# 2. Update the password inside PostgreSQL
docker compose exec postgresql psql -U <POSTGRESQL_USER> -c \
  "ALTER USER <POSTGRESQL_USER> PASSWORD '<new_password>';"
# 3. Re-generate the PgBouncer auth file
rm configs/pgbouncer/userlist.txt
./scripts/up.sh
```

### Update PgBouncer settings

```bash
# 1. Edit .env or configs/pgbouncer/pgbouncer.ini.template
# 2. Re-generate pgbouncer.ini and restart PgBouncer
rm configs/pgbouncer/pgbouncer.ini
./scripts/up.sh
docker compose restart pgbouncer
```

### Restrict access by IP (whitelist)

Edit `configs/pgbouncer/hba.conf` — replace the allow-all rules with specific subnets:

```
# Allow only specific hosts
host    all     all     10.0.0.1/32     scram-sha-256
host    all     all     10.0.0.2/32     scram-sha-256
```

Then apply:

```bash
docker compose restart pgbouncer
```

No need to regenerate `pgbouncer.ini` — `hba.conf` is mounted directly and re-read on restart.

### Renew TLS certificates

```bash
# Regenerate with --force (specify the server CN again)
./scripts/gen-certs.sh --force <server-cn-or-ip>
docker compose restart pgbouncer
```

### View logs

```bash
docker compose logs -f postgresql
docker compose logs -f pgbouncer
```

### Stop the stack

```bash
docker compose down
```

### Stop and remove all data (destructive)

```bash
docker compose down
sudo rm -rf data/postgresql && mkdir data/postgresql
```

## Security Notes

- Both containers run as non-root users (PostgreSQL: UID 70, PgBouncer: UID 65532).
- Both containers have `cap_drop: ALL` and `read_only: true`.
- The internal Docker network has no outbound internet access (`internal: true`).
- Only PgBouncer port (`PGBOUNCER_PORT`) is published to the host. PostgreSQL is not reachable from outside the container network.
- `ca.key` is never mounted inside any container. `server.key` is mounted read-only into PgBouncer only (required for TLS), owned by UID 65532 with mode `600`.
- `userlist.txt` and `pgbouncer.ini` are owned by UID 65532 with mode `600`.
- `.env` and all private keys are git-ignored.
