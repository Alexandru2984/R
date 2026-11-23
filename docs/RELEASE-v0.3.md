# Version 0.3 — investigations and accountability

Deployed on 2026-11-23 at **https://r.micutu.com/**. The previous release was `59d17ec`; implementation commits are `0a69872`, `368f42f` and `bd55db7`.

## Delivered

- Private audit trail for successful sign-in, explicit sign-out, detected session expiry and completed imports. Import/audit writes are one transaction. Runtime grants are SELECT/INSERT and sequence USAGE; no audit UPDATE/DELETE or schema CREATE privileges were added.
- Equal-length previous UTC calendar-period comparisons with identical filters, independent row caps, explicit zero-baseline handling and a notice when today is incomplete. Live windows share a read-only repeatable-read transaction.
- Weekday/hour activity map, reported-country distribution and HTTP method distribution. No country geolocation or bot identity is inferred from these views.
- Ten named filter views per session, with restore, replace-by-name and delete. Reloading the page or changing between demo/admin clears views; no filters are stored in browser storage or shared URLs.
- Public detection lab with examples, actual scoring rules and complete per-rule point accounting. Inputs are bounded strings and never create database requests or perform network probes.
- Source changes clear private filters, sample fields, upload controls and hidden private widgets. Empty tables disable lazy rendering so hidden DOM contents are cleared at logout.
- Malformed preset shapes are rejected without terminating the session. Combined scoring explanations now account for every matched signal.

## Verification

- **150 assertions passed; zero failures, warnings or skipped tests.** Real PostgreSQL tests cover atomic import/audit rollback, exact-file duplicate protection, summary consistency, previous-window reads and restoring ordinary transaction state in pooled connections.
- Browser flows passed comparison/report export, activity-map rendering, saved-view restore/delete, lab examples, hostile text escaping, auth source isolation, import preview, successful import, duplicate rejection, private audit display, logout clearing and mobile saved views/lab navigation.
- Layouts checked at **360, 390 and 768 px**. No page overflow or JavaScript/console errors were observed in these flows. Actual mobile lab and dashboard screenshots were inspected.
- Real-domain HTTPS/WebSocket checks passed comparison, activity map, lab, mobile navigation/layout under the existing production CSP. Normal HTTPS returned 200; a foreign Origin returned 403.
- Production still contains **190,714 requests**. Tests imported only into `rtraffic_qa_v03`, not production. Real admin passwords were not changed or used in browser tests.
- Service is active with no automatic restart loop. No proxy, shared Cloudflare Tunnel or runtime-credential change was required.
- The existing [GitHub Actions workflow](https://github.com/Alexandru2984/R/actions/workflows/checks.yml) verifies the release after its final push; local results are not a substitute for checking its hosted result.

## Operational record

- Rollback source/config backup: `/var/backups/rtraffic-v03-20261123T203016Z`, root-only.
- Added migration: `002_admin_audit.sql`. It adds the audit table/index; no historical request rows were deleted or rewritten.
- Migration applied through the local PostgreSQL administration role. Runtime audit permissions were checked explicitly: read/append/sequence usage true, update/delete/schema creation false.
- Work was prepared in an isolated checkout and merged with fast-forward commits. Only `r-traffic-intel.service` was restarted for deployment.

## Remaining scope

Audit records cover authenticated actions, not failed sign-ins or abrupt client disconnects. Failed attempts remain protected by process-local limits. Audit retention needs an explicit operational policy; this release does not delete audit records automatically.

Named views are session-scoped rather than durable account bookmarks. Comparison deltas describe capped snapshots when limits apply, and incomplete days are labelled rather than silently extrapolated. The synthetic demo spans fourteen days.

The previously documented Shiny CSP exceptions and shared-tunnel origin-TLS setting remain unchanged. Shared authentication limits, MFA/team roles, verified crawler ownership, incremental/overlap-aware ingestion, multi-source tenancy and retention enforcement remain follow-ups in the roadmap.
