# Deployment model — booklore

Produced by `stack-analysis` (stack-init Phase 0) against upstream
`booklore-app/booklore` @ `01b3407428…` (`01b3407`, master tip, latest
release `v2.4.0`), published image `ghcr.io/booklore-app/booklore`
(amd64/arm64 single image; Angular UI built into the Spring Boot JAR).

## Product parts

| part | purpose | image source |
|------|---------|--------------|
| `booklore` | Single-part product: Spring Boot monolith serving the embedded Angular UI at `:6060` (`BOOKLORE_PORT`). Book/comic library: scanning `starter` of `/books` and `/bookdrop` auto-import, EPUB/PDF readers, metadata fetching, shelves/collections, user management + permissions, email-converted-PDF sending, optional Swagger UI. Bundles the whole UI — no separate frontend part. | published `ghcr.io/booklore-app/booklore` |

Other upstream dirs (`example-docker/`, `example-chart/`,
`example-podman/`, `docs/`, `scripts/`) are packaging/doc material —
not deployable server parts.

## Interaction map

- Browser → `booklore` (HTTP `:6060`): web UI + REST API. App-native
  auth; OIDC is configurable **in the UI** (issuer URL + client id/
  secret persisted in MariaDB via migration `V127__Add_oidc_schema.sql`
  — there is NO issuer/client env surface; only `FORCE_DISABLE_OIDC`).
- `booklore` → `booklore-db` (JDBC): the single mandatory external
  infra. Flyway migrations under `booklore-api/.../db/migration/` are
  MariaDB-specific; default URL `jdbc:mariadb://mariadb:3306/booklore`
  (host/port/name/credentials override via
  `DATABASE_URL` / `DATABASE_USERNAME` / `DATABASE_PASSWORD`).
- `booklore` → local filesystem: `/app/data`, `/books` (library),
  `/bookdrop` (drop-folder ingestion).
- Optional outbound: OIDC provider (UI-configured), SMTP (in-app
  settings, not infra), metadata providers (web).

A missing optional outbound breaks nothing; missing MariaDB = app
cannot boot.

## Functional base

- **Core group (tier `core`)**: `booklore` — the only product part; it
  does all the main work and carries its primary UI.
- **Mandatory infra**:
  - **Database — product-mandated MariaDB**, base service
    `booklore-db`, image `lscr.io/linuxserver/mariadb` (upstream pins
    `11.4.8`). The §8 postgresql+pgrust pair **cannot** attach: the
    upstream Flyway migrations are MySQL/MariaDB DDL only and there is
    no Postgres JDBC path in `application.yaml`. Recorded per the §8
    single-non-postgres-DB exception in the base.
  - **OIDC**: supported but UI-configured (no issuer/client env) →
    catalog extension `oidc` under the §10 UI-only-OIDC pattern, not
    base infra through env; wiring happens in-app after deploy.
  - **S3: REFUSED as mandatory infra.** No S3 object storage in the
    code — `disk-type` support is LOCAL vs a remote disk mount; there
    is no S3 backend. s3fs-fuse on library volumes remains an optional
    catalog extension (never on `/app/data` or the DB volume).

## Base stage plan

- **Stage A (core group gate)**: `booklore` + `booklore-db` (MariaDB,
  volume `booklore-db`), volumes `booklore-data`, `booklore-books`,
  `booklore-bookdrop`, port `${BOOKLORE_PORT:-6060}`. Gate scenario:
  boot → Flyway migration to green UI → first-run account create/login
  → import a PDF or EPUB into a shelf → open it in the reader → verify
  metadata/detail page render. No outer groups, no cross-host links →
  no `step-ca-trust` requirement.

## Extension catalog

| extension | type | status | dependencies |
|-----------|------|--------|--------------|
| oidc (§10 UI-configured) | infra | **implemented** | Provider configured **in-app** (Settings → OIDC): issuer `https://kanidm.af/oauth2/openid/booklore`, client `booklore`, scopes `openid profile email groups`, claims `preferred_username`/`email`/`given_name`/`groups` — stored in MariaDB `app_settings` (V127), so the fragment only asserts `FORCE_DISABLE_OIDC=false`. Provider side (kanidm): redirects `http://localhost:6060/oauth2-callback` + `https://booklore.af/oauth2-callback`, group `booklore_users`. Gate PASSED (browser SSO login as `booklore_test@kanidm.af`, auto-provisioned user, dashboard reached); app-side "auto-provision" must be switched ON in the same settings form before JIT users can log in. |
| Remote-auth reverse proxy (`REMOTE_AUTH_*` headers) | product | available | forward-auth-capable proxy; upstream doc `docs/forward-auth-with-proxy.md` |
| SMTP (email→PDF delivery) | product | available | SMTP server; configured in app settings UI (not compose env) |
| s3fs-fuse on `/books` `/bookdrop` | infra | available | RustFS/S3 bucket; never on `/app/data` or DB volume |
| TLS reverse proxy / step-ca-trust (public origin + secure-cookie overlay) | infra | **implemented** | `step-ca` environment (nginx + acme-companion behind step-ca-proxy) + companion extension `step-ca-trust`: mounts `step-ca-data` subpath `certs` read-only at `/step-ca-root` and an entrypoint wrapper imports the root CA into the **Java `cacerts` truststore** (keytool, as root before `entrypoint.sh` drops privileges via su-exec) on every start — the JVM does not read `/usr/local/share/ca-certificates`, and recreates never lose the trust. Required for the OIDC back-channel (PKIX) when kanidm.af sits behind step-ca TLS. |

**Maintenance-status note**: upstream HEAD commit (`01b3407`) announces
**BookOrbit** as the successor of BookLore — overlap risk with the
collection's existing successor stack; re-verify upstream activity
before major rework cycles here.

## Open hypotheses

- **MariaDB version pin** (high): upstream example pins
  `lscr.io/linuxserver/mariadb:11.4.8`; base stage mirrors that pin
  unless the gate invalidates it. → Stage A observes migration import
  completeness. **VALIDATED** (Stage A: 131 Flyway migrations applied
  cleanly on 11.4.8; app boots green).
- **First-run bootstrap shape** (medium): assumed "first visiting user
  creates the admin account via the UI"; the gate observes the actual
  flow (registration form vs invite vs env-seeded credentials).
  **VALIDATED** (Stage A: first-run wizard creates the admin account in
  the UI, then normal login).
- **Port/healthcheck semantics** (medium): `:6060` is the documented
  single port; gate observes whether a Spring Actuator health endpoint
  exists for compose healthchecks or only the UI root answers.
  **VALIDATED** — `/api/v1/healthcheck` on :6060 answers UP (compose
  healthcheck green).
- **Named-volume ownership** (observed at gate): fresh `booklore-books`
  volume is root-owned → bookdrop finalize fails ("Failed to move
  file"). Fixed with a one-shot `booklore-vol-init` chown service
  (validated live: init exit 0, `/books` owned by booklore).
- **OIDC UI-config confidence** (high): provider config is DB-stored
  (V127) and no env surface exists — the §10 UI-only OIDC pattern
  applies as recorded; gate confirms post-deploy in-app configuration
  flow if/when the `oidc` extension is implemented.
  **VALIDATED** (Stage B extension gate: UI-entered Kanidm provider →
  browser SSO login → JIT auto-provisioned user, after enabling the
  app's auto-provision switch in the same UI form). Journey caveats:
  the JVM needs the step-ca root CA in its `cacerts` (companion's
  `/usr/local/share/ca-certificates` path is invisible to Java), and
  container **recreate** wipes that import (restart preserves it).
