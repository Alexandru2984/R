# Existing VPS deployment

This repository serves https://r.micutu.com on loopback port 3838. Keep the existing Cloudflare route, TLS vhost, service user and runtime environment file. Do not migrate this app to another host during an application update.

`r-traffic-intel-origin-map.conf` belongs in Nginx's http context. In the existing site's HTTPS `server` block, reject an origin with `if ($rtraffic_origin_allowed = 0) { return 403; }`. Empty Origin permits normal navigations and command-line clients; it is not authentication. Set `client_max_body_size 11m` to allow a 10 MiB upload plus its transport overhead. Keep the existing WebSocket, CSP, connection and rate-limit settings.

`r-traffic-intel-hardening.conf` is a systemd drop-in. It replaces unbounded private temporary directories with isolated 128 MiB `/tmp` and 32 MiB `/var/tmp` mounts. Existing memory and task limits continue to apply. A restart is required; inspect the process mount namespace to verify the mounts.

Before deployment:

1. Run tests against an isolated PostgreSQL database and browser QA with `scripts/run_qa.R`.
2. Back up the current vhost, limit/map configuration and service unit outside Git; record the previous app commit.
3. Apply the additive migration with a migration/owner role: `Rscript scripts/migrate_db.R`. Set `DB_RUNTIME_ROLE` to grant the runtime role SELECT/INSERT on the registry/audit table and USAGE on the audit sequence; keep the runtime role's schema CREATE privilege disabled. It adds a registry and indexes without rewriting historical requests.
4. Install the narrowly scoped configuration, validate `nginx -t` and `systemd-analyze verify`, then reload Nginx and restart only `r-traffic-intel.service`.
5. Check the loopback listener, public HTTPS, WebSocket/browser flow, headers, forbidden Origin and process isolation.

Rollback: restore the backed-up Nginx/drop-in files, reload/restart the service and restore the previously recorded application revision. The additive DB tables/indexes may remain; older code ignores them. Never drop request data to roll back a UI release. Do not put runtime secrets or database dumps into Git.

The shared Cloudflare tunnel currently inherits disabled TLS verification for the fallback route. `cloudflared-r-route.yml` is a prepared, app-specific strict verification alternative. The origin certificate was verified locally; adding the entry and restarting the shared tunnel should be coordinated with the other hosted applications.

`r-traffic-intel-headers.conf` is shared by the HTTPS server and its named 429 handler so error responses retain security headers. The maps also mark session/download responses private/no-store and noindex. These headers complement authentication; robots directives do not enforce access control.

The current Shiny/htmlwidgets runtime needs the documented inline/evaluation CSP exceptions. Test the interactive public page after changes; an HTTP 200 alone does not verify a functioning dashboard. A future strict-CSP design must replace the code paths that evaluate serialized JavaScript.

Version 0.3 adds `002_admin_audit.sql`. An app-only update needs the additive migration/grants followed by a restart of `r-traffic-intel.service`; existing Nginx and Cloudflare settings can remain unchanged. See `docs/RELEASE-v0.3.md` for the recorded backup and checks.
