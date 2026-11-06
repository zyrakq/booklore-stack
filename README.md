# 📚 BookLore Stack

Dockerized [BookLore](https://github.com/booklore-app/booklore) — a self-hosted
book and comic library (EPUB/PDF reading, metadata fetching, shelves, user
management) backed by MariaDB, with optional OIDC single sign-on, S3-backed
library storage, forward-auth, and step-ca TLS.

> **Upstream note**: BookLore's HEAD
> ([`01b3407`](https://github.com/booklore-app/booklore), `v2.4.0`) announces
> **BookOrbit** as its successor — re-verify upstream activity before major
> rework cycles (see [`DEPLOYMENT.md`](DEPLOYMENT.md)).

## 🧩 Components

### 📖 [BookLore App](app/)

Modular Docker Compose configuration generated with
[`sb`](https://github.com/zyrakq/docker-stack-collection) (stackbuilder).
Functional base per [`DEPLOYMENT.md`](DEPLOYMENT.md): the single-part
`booklore` service (port `6060`) plus the product-mandated MariaDB base
service `booklore-db` (upstream Flyway migrations are MariaDB-only — no
Postgres path).

Extension statuses from the extension catalog:

- **oidc** (`implemented`) — UI-configured OIDC (kanidm); provider data is
  entered in the app's Settings → OIDC form and stored in MariaDB. The
  fragment only keeps `FORCE_DISABLE_OIDC=false` and is part of the default
  `entire` combo.
- **step-ca-trust** (`implemented`) — imports the step-ca root CA into the
  JVM `cacerts` truststore on every start (Java ignores
  `/usr/local/share/ca-certificates`); used by the `entire-trust` combo /
  `step-ca` environment for OIDC back-channel TLS.
- **s3fs-fuse** (`implemented`) — mounts RustFS-backed buckets on `/books`
  and `/bookdrop` (gate combo `entire-s3fs`, forwarding environment).
- **remote-auth** (`implemented`) — bundled nginx forward-auth proxy
  `booklore-remoteauth-proxy` on port `6061` (gate combo
  `entire-remoteauth`); header names must be all-lowercase.
- **SMTP** (`available`) — configured in the app settings UI, no compose
  wiring.

## 🚀 Quick Start

```bash
cd app/
sb build
cp .env.example .env   # set DATABASE_PASSWORD + MYSQL_ROOT_PASSWORD first
```

Pick a generated variant under `app/build/`:

```bash
# Local, plain port forwarding (also hosts entire-s3fs / entire-remoteauth)
cd build/forwarding/entire/

# Public TLS via the letsencrypt stack
cd build/letsencrypt/entire/

# Internal TLS via the step-ca stack (adds JVM CA trust)
cd build/step-ca/entire-trust/
```

```bash
cp .env.example .env
docker compose up -d
```

Access (forwarding): <http://localhost:6060> — the first-run wizard creates
the admin account. Health endpoint: `/api/v1/healthcheck`.

## 📋 Requirements

- Docker & Docker Compose (with the [collection hooks
  installed](../../../../../README.md) for clone automation — optional)
- `sb` binary for `sb build` (regenerating `app/build/`)
- MariaDB credentials in `.env` before first start (app cannot boot without
  the database)
- Domain name + TLS stack only for the `letsencrypt`/`step-ca` variants

## 📄 License

This project is dual-licensed under:

- [Apache License 2.0](LICENSE-APACHE)
- [MIT License](LICENSE-MIT)
