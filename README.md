# R Traffic Intelligence

A web traffic investigation workspace built with R/Shiny and PostgreSQL, available at **https://r.micutu.com/**. Public visitors explore generated traffic; administrators sign in to inspect and import production logs.

## What it does

- Public synthetic demo works without database credentials. Documentation IP ranges keep demo identities separate from live traffic.
- UTC date presets and custom ranges, exact IP search, literal path search, HTTP method/status and signal filters.
- Hourly/daily traffic, classification composition, HTTP responses, summary metrics, top paths and contextual insights.
- Equal-length UTC calendar-period comparison with per-period coverage and explicit treatment of zero baselines and incomplete days.
- UTC weekday/hour activity map and distributions of reported country codes and HTTP methods.
- Up to ten named filter views per session, with restore/delete; source changes clear private filters, saved views and upload controls.
- Public detection lab with real rules, examples and a complete point-by-point explanation; samples are never imported.
- IP investigation, request details and transparent scoring explanations. Bot user agents are claims, not verified identity.
- CSV export with spreadsheet formula protection and a plain-text report. Both identify source and coverage.
- Admin import preview, malformed-row counts, SHA-256 duplicate detection, one transaction per import, import history and a private action audit trail.
- Responsive mobile layout, accessible native date controls, keyboard focus and reduced-motion support.
- Admin attempt limits, idle/absolute session expiration, bounded DB pool/query duration, upload and dataset limits.

A snapshot includes the latest **20,000** requests matching date/IP/path/status/method, then applies classification. Dashboard views and exports share this snapshot. When comparison is enabled, the previous period has its own independent 20,000-request limit and uses the same filters; live periods are read in one read-only, repeatable-read transaction. Today is explicitly marked incomplete. The synthetic public dataset spans fourteen days. The explorer displays up to 1,000 rows; IP investigation shows up to 1,000 addresses. Import limits are **10 MiB / 50,000 physical lines**. Identical files are deduplicated; different overlapping files can still contain the same requests.

## Run the public demo

Use R 4.5.2 and the dependencies pinned in `renv.lock`:

```r
install.packages("renv")
renv::restore()
```

```bash
Rscript run.R
```

The app listens only on `127.0.0.1:3838`; use `APP_PORT` for another loopback port. No database connection is opened for public demo sessions. The Node dependency is browser QA tooling and is not needed to run the application.

## Configure a private workspace

Set environment variables in a protected service environment file or an ignored local `.env`:

```text
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=r_traffic_intel
DB_USER=r_traffic_user
DB_PASSWORD=<unique database password>
APP_USERNAME=<admin username>
APP_PASSWORD_HASH=<sodium password_store hash>
APP_PORT=3838
```

Generate the password hash using `sodium::password_store()` outside tracked files. Plain-text admin passwords are never configured. Missing credentials fail closed. Production loads `/etc/r-traffic-intel/app.env`; this file is not part of Git.

Initialize a new database using `scripts/init_db.sql`, with a dedicated database role, then apply migrations:

```bash
Rscript scripts/migrate_db.R
```

Use a dedicated migration/owner role for schema changes. `DB_RUNTIME_ROLE` optionally grants the runtime role SELECT/INSERT on the import registry and audit table, plus USAGE on the audit sequence. Do not grant schema CREATE privileges to the application to run a migration.

Migrations are tracked and transactional. Existing request rows are retained. The audit trail records authenticated sign-in, explicit sign-out, detected session expiry and successful import events. Failed sign-ins stay covered by the process-local limiter; they are not persisted to this audit table. Import events are committed in the same transaction as their requests. Audit rows contain the configured admin name and import counts, without passwords, session tokens, client IPs or raw logs. The runtime role receives SELECT/INSERT on the audit table and USAGE on its sequence, with no UPDATE/DELETE grant. Establish an audit retention policy appropriate to your use.

Live analytics recompute signal rules from the selected requests rather than trusting historical summary counters. The **Latest available logs** button opens the latest stored period when recent days contain no imported traffic.

Nginx imports use combined format. Cloudflare CSV accepts `ClientIP`, `EdgeStartTimestamp` (UTC ISO or Unix seconds/milliseconds/nanoseconds), `ClientRequestURI`, `EdgeResponseStatus`, and optional protocol, method, bytes, user agent, referrer and country fields. Invalid rows are skipped and counted. Uploaded content is displayed with HTML escaping.

An explicit local-file import is also available:

```bash
Rscript scripts/import_local_nginx.R /path/to/access.log
```

Do not repeatedly ingest whole active/rotated logs as an incremental ingestion strategy.

## Verification

```bash
Rscript scripts/run_tests.R
```

Database integration tests run when `TEST_DB_NAME` is set, using `TEST_DB_HOST`, `TEST_DB_USER` and `TEST_DB_PASSWORD`. They create and remove an isolated schema. CI supplies a dedicated PostgreSQL service and fails on test warnings.

For browser QA, create a dedicated database whose name starts with `rtraffic_qa` or `rtraffic_test`, then start this test-only server:

```bash
TEST_DB_NAME=rtraffic_qa TEST_DB_USER=<test role> Rscript scripts/run_qa.R
npm ci --ignore-scripts
npx playwright-core install chromium
npm run test:browser
```

The test-only server uses temporary QA credentials and port 43838. Browser import tests refuse remote URLs. `BROWSER_EXECUTABLE` can select an existing Chromium binary; `TEST_ARTIFACT_DIR` selects screenshot storage. Browser tooling and R dependencies are pinned separately. Refresh the R lockfile with `renv::snapshot(type = "explicit", dev = TRUE)` so test dependencies remain included. CI runs unit/security tests, real PostgreSQL transaction tests and desktop/mobile browser flows; it does not deploy or access production secrets.

## Operations and limitations

The production service is `r-traffic-intel.service`, with the existing Cloudflare/Nginx route. See [deployment and rollback](deploy/README.md), [security audit](docs/SECURITY-AUDIT.md), [delivery plan and next features](docs/ROADMAP.md) and [release verification](docs/RELEASE-v0.3.md).

Authentication limits are process-local. A multi-worker/team product needs shared limits, durable audit events and individual identities/MFA. Define retention and redaction policies before onboarding external datasets. Request scores support investigation; they do not automatically verify bots or justify blocking visitors.
