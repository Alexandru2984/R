# Security audit — 2026-11-23

## Scope and method

Source review, existing tests, dependency version inventory, read-only inspection of the production systemd service and Nginx vhost, and HTTP verification of https://r.micutu.com. No intrusive scans of other VPS applications. Runtime secrets are not included in this document.

Baseline: commit b72f4bd; 46 assertions pass. R/Shiny 1.10.0, bslib 0.9.0, DT 0.34.0, plotly 4.10.4, RPostgres 1.4.10. The README's “production-ready” claim overstates the original implementation.

## Confirmed findings at baseline

| ID | Severity | Evidence and impact | Planned remediation |
| --- | --- | --- | --- |
| SEC-01 | High | `pool <<- get_db_pool()` inside each session, with session-local `onStop`: a session can replace/close another session's global pool; unbounded pool creation under load. | One lazy process pool, app-level shutdown, max connections and query timeout. |
| SEC-02 | High | Import file record, request append and summary writes use separate connections with no transaction. Partial failures leave misleading data; repeated imports inflate counters. | One checked-out connection and transaction; content hash registry; accurate affected-IP summaries. |
| SEC-03 | High | Import consumes a client-supplied datapath without a temp-directory/regular-file boundary. Files have no explicit application row/line limits. | Verify uploaded temp path and file size, reject symlinks, enforce row/line/field limits. |
| SEC-04 | Medium | Invalid IPs/timestamps/statuses are accepted; Cloudflare status column alias is misspelled. CSV type inference can mutate values. | Strict typed normalization and reject invalid rows; support actual Cloudflare field names. |
| SEC-05 | Medium | Unlimited admin session lifetime; auth state and limiter have no capacity/expiry cleanup; malformed vectors/NA can throw. | Absolute/idle expiry; bounded limiter; scalar and byte-length checks; trusted-proxy boundary. |
| SEC-06 | Medium | Parser/DB error messages are displayed directly, while dashboard query errors become apparently valid zeros. | Generic notifications, server-side diagnostics and explicit unavailable states. |
| SEC-07 | Medium | Date range unbounded and many separate SQL queries per refresh; malformed filters can crash reactives. | Bounded validated filters, query limits, shared snapshot, refresh throttling. |
| SEC-08 | Medium | Public demo depends on production DB and stale mock tables. DB outage breaks even anonymous exploration. | In-memory synthetic sample from documentation IP ranges, independent of DB access. |
| SEC-09 | Medium | Detection rules treat ordinary `/login` and `/admin` as scanner evidence, miss encoded probes and imply user-agent bot identity is trustworthy. | More specific path rules, bounded decoding, explainable heuristics and explicit identity caveat. |
| SEC-10 | Medium | Migration script is a success-printing stub; no integration/rollback tests or dependency manifest. | Additive migrations, isolated DB tests, dependency inventory and CI. |
| SEC-11 | Low | Nginx security headers are present, but CSP permits inline scripts, required by this Shiny/widget setup. | Preserve functional CSP, document limitation; no untested nonce retrofit. |

## Existing protections verified

- Dedicated `rtraffic` service user; loopback-only application and database listeners.
- Systemd read-only source, restricted writable state, no capabilities, localhost-only networking, memory/task limits and core dumps disabled.
- Required runtime DB secrets and sodium password hash; credentials absent from current tracked files.
- Production tables chosen server-side from auth state; existing import observer checks login.
- Bound SQL parameters; DT default HTML escaping; local fonts.
- Public HTTPS endpoint returns HSTS, nosniff, frame denial, referrer and permissions policies, CSP. Nginx has connection/body/rate limits and a Cloudflare-origin guard.

## Residual risks / follow-up

- Application-wide limits are process-local. Multiple workers need shared auth/session rate limiting.
- Upstream R/Shiny and embedded JavaScript libraries require a tested application-specific upgrade path; do not replace global R packages used by other VPS services. No confirmed advisory is inferred from version age alone.
- Full-file hashing prevents exact reimports, not overlapping rotated-log content. Incremental cursors/request deduplication need an explicit migration design; historical rows must not be silently deleted.
- IPs, query strings and user agents are sensitive. Establish retention, backup retention, access policy and source redaction before onboarding other users.
- Request heuristics are triage indicators, not proof of maliciousness, humanity or verified crawler ownership. Do not automatically block IPs based solely on these scores.
- DNS/Cloudflare dashboard settings, edge WAF rules, remote backups and third-party account permissions are outside this source review's visibility.
- Existing legacy summary tables may contain historical inaccuracies. New views should aggregate filtered requests directly.

References checked: [Shiny upstream advisories](https://github.com/rstudio/shiny/security/advisories), [Shiny changelog](https://rstudio.github.io/shiny/news/index.html). Published advisories are not a comprehensive vulnerability guarantee.

## Verification and delivery

Implementation results, test evidence and remaining limits are recorded in `docs/RELEASE.md` when the release is completed.

## Additional runtime findings

- The actual route is Cloudflare Tunnel → Nginx HTTPS vhost → loopback Shiny on 3838. This application's fallback tunnel route inherits `noTLSVerify: true`. The origin certificate is valid through 2027-01-28 and local hostname/certificate verification succeeds. A dedicated strict-TLS ingress is prepared in `deploy/cloudflared-r-route.yml`; applying it requires restarting the shared tunnel and is left for a coordinated VPS maintenance window.
- Anonymous Shiny sessions can reach framework upload transport even when the admin UI is hidden. Application import authorization remains mandatory. A dedicated temporary-filesystem quota bounds unimported uploads as well as parsed files; body, memory, connection and rate limits remain necessary.
- The system package's datepicker has a noConflict/data-API error, DT's Bootstrap 5 CSS dependency is missing at its advertised path, and Plotly's legacy typed-array shim references an undefined `GLOBAL`. Application-scoped native date controls, supported table styling and native browser typed arrays avoid these faults without modifying global R packages.
- Current DB password and admin hash were checked against all local Git history; neither was present. This is not a comprehensive historical secret scan of the VPS or remote forks.

- End-to-end public-domain testing confirmed that the inherited CSP blocked the installed Shiny/htmlwidgets runtime's dynamic JavaScript evaluation, preventing interactive data from rendering despite HTTP 200. The release explicitly permits `unsafe-eval` alongside the existing inline-script allowance. This weakens CSP's protection against script injection and remains a medium residual risk; source restrictions, HTML escaping, Origin validation and private data authorization are still enforced. Removing these allowances requires a CSP-compatible runtime/widget redesign, not merely changing a header. See [CSP evaluation rules](https://www.w3.org/TR/CSP2/).
