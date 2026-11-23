# Release verification — 2026-11-23

The updated application is deployed at **https://r.micutu.com/** on the existing VPS route. The original 190,714 production requests were retained. Browser import tests used only the separate `rtraffic_qa_20261123` database.

## Delivered

- Atomic, content-deduplicated ingestion; real additive migrations; safe query-result cleanup on bind failures; accurate affected-IP summary recomputation.
- Scalar/size checks, bounded authentication state, process-wide attempt protection and idle/absolute admin expiry.
- Strict Nginx/Cloudflare parsing with IP/status/time/field limits, UTC normalization, upload boundaries and encoded-probe detection.
- Lazy process-level DB pool, bounded connections/queries, generic client errors and a database-independent synthetic public demo.
- Shared filtered snapshots; date/IP/path/method/status/signal filters; current-period presets and latest available production-period selection.
- Hour/day charts, traffic composition, HTTP distribution, IP/request investigation, explanations, insights, import preview/history, safe CSV and text reports.
- Responsive layouts, mobile navigation and filters, native accessible dates, visible focus, local fonts, reduced motion and readable data tables.
- Public metadata/canonical/robots/sitemap, pinned R and browser dependencies, read-only CI without production deployment credentials.
- Same-origin enforcement, private/no-store/noindex session responses, security headers on error responses and per-service temporary filesystem quotas.

## Evidence

- **105 assertions passed, zero warnings, zero skipped tests**, including actual PostgreSQL rollback, duplicate import and IP-summary verification.
- Committed browser suite passed desktop filtering, native date presets, CSV export, IP investigation, empty results, authentication, upload preview, real import, duplicate rejection, escaped hostile markup and logout.
- Initial mobile visits at **360, 390 and 768 px** passed layout-width checks. Mobile navigation opened successfully and filters initialized collapsed below 768 px. No JavaScript/console errors were observed in these flows.
- A separate real-domain browser check passed HTTPS/WebSocket, synthetic demo, filtering, report download and mobile navigation with no browser errors under the deployed CSP.
- Public HTTP checks: normal/same-origin requests 200; foreign Origin 403; invalid session URL 404 with private/no-store and noindex headers.
- Nginx configuration and systemd unit validation succeeded. Unrelated pre-existing `CPUAccounting` deprecation messages appeared during systemd validation; no app-unit errors occurred.
- Runtime mount namespace confirms 128 MiB `/tmp` and 32 MiB `/var/tmp` tmpfs quotas. Service remains active with no automatic restart loop.
- Runtime DB role retains no schema CREATE, superuser, CREATEDB, CREATEROLE or BYPASSRLS privileges. Required import INSERT/UPDATE grants were verified; the new registry has only SELECT/INSERT grants for that role.
- Migration was applied through local PostgreSQL administration, then rerun successfully for idempotence. Runtime privileges were not broadened to permit schema creation.
- Browser tool dependency audit reported zero vulnerabilities. This does not cover all R/system/embedded JavaScript dependencies.
- Workflow YAML and action commit pins were checked locally; the local workflow-equivalent test suite passed. Hosted GitHub Actions status must be checked after the final push and is not implied by local success.

## Operational record

- Original app revision: `b72f4bd`.
- Backup: `/var/backups/rtraffic-release-20261123T082757Z` (root-only), including original source archive, vhost and unit configuration. A prior pre-migration attempt also created a backup and stopped safely on insufficient migration privileges.
- Added migration: `001_import_registry.sql`, with migration ledger and indexes. No production request rows were deleted or replaced.
- Installed Nginx app-specific Origin/private-response maps and shared headers; updated only this vhost, then reloaded Nginx.
- Installed systemd drop-in `20-upload-quota.conf` and restarted only `r-traffic-intel.service`.
- Shared Cloudflare Tunnel configuration was preserved; other application services were not restarted.

## Remaining limits

- CSP retains inline and evaluation exceptions required by the current Shiny/htmlwidgets runtime. This is a documented medium residual risk, not a strict CSP deployment.
- Shared tunnel fallback still disables origin certificate verification. The origin certificate is valid and verifies locally; a strict app-specific ingress snippet is prepared for a coordinated shared-tunnel restart.
- Process-local attempt limits need shared storage before multiple workers. Team accounts, MFA, durable audit events, retention/redaction, incremental ingestion and verified crawler identity remain follow-up product work.
- Exact-file hashes do not deduplicate overlapping content in different files. Snapshot and per-table row limits are explicit in the UI and exports.
- Public SEO describes the demo; indexing/ranking and search-engine rendering are not guaranteed. Existing Cloudflare-managed crawler policy is preserved.
- Private flows were exercised against the isolated QA database. Production admin credentials were not changed or used in the browser.
