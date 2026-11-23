# Traffic Intelligence — delivery plan

## Release scope

Keep R/Shiny, PostgreSQL and the current VPS domain. Public visitors explore synthetic traffic; authenticated administrators inspect and import production traffic. Live IP addresses, paths and user agents must never enter the public demo.

1. **Audit and baseline** — inspect application, service and both proxy routes; record confirmed defects and residual risks. Commit the audit and roadmap.
2. **Security and ingestion** — shared lazy pool with bounded connections/query duration; bounded authentication limiter and session lifetime; strict parser validation and file limits; transactional, content-deduplicated imports; generic client errors. Test hostile input and rollback behavior. Commit.
3. **Analytics** — parameterized bounded search; status/IP/path/classification filters; current synthetic demo; hourly/daily traffic, classification and HTTP distributions; IP investigation and scoring explanations; spreadsheet-safe CSV and text reports; import preview and history. Commit.
4. **Product interface** — accessible responsive navigation, mobile cards/tables, presets/reset, clear source/freshness/coverage states, automatic refresh, threat guidance and useful empty states. Test real desktop/mobile browser flows. Commit.
5. **Release quality** — database integration and session tests; reproducible dependency inventory; least-privilege CI; metadata and public crawl policy; deploy with backup and rollback, verify public endpoint and push once. Commit.

## Next product opportunities

Prioritized after this release, with separate acceptance criteria:

- Multi-site/source tenancy with explicit access controls and separate API credentials.
- Incremental, rotation-aware ingestion with per-source cursors and request identity design; do not repeatedly ingest entire active log files.
- Admin-managed retention/redaction policies and scheduled deletion with preview and audit trail.
- DNS-verified crawler identity and maintained bot allowlists; a user agent alone cannot establish identity.
- Alert policies and notification destinations, enabled explicitly by the administrator.
- Anomaly baselines by site/hour, comparative periods and a saved investigation workspace.
- Private team accounts, MFA/OIDC, role-based access and durable cross-worker rate limits.
- Carefully scoped public landing page and product documentation, separate from private analytics.

## Acceptance criteria

- Anonymous requests and forged client inputs cannot query production data or import files.
- Rejected uploads leave no database rows; an identical file is imported once, even on concurrent attempts.
- Closing a browser does not close another session's database connections.
- A new visitor sees meaningful demo traffic without a configured database.
- All analytics and exports identify the source and any row/date limits.
- Keyboard navigation and 360px mobile layouts remain usable; dynamic failures are explicit rather than fake zero values.
- Commits use the repository owner's established Git identity, without additional attribution. Push only after final checks.

## Delivery status — 2026-11-23

The five implementation stages are delivered and deployed. Local security/unit/database tests and real desktop/mobile/browser flows pass. See `docs/RELEASE.md` for evidence, the hosted-CI verification boundary, operational backup and remaining product/security work. Future opportunities above are proposals, not features already implemented.
