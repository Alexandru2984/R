CREATE TABLE IF NOT EXISTS admin_audit_events (
    id BIGSERIAL PRIMARY KEY,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    action VARCHAR(40) NOT NULL CHECK (action IN ('login_success','logout','session_expired','import_completed')),
    actor VARCHAR(128) NOT NULL,
    file_id INTEGER REFERENCES imported_log_files(id),
    accepted_rows INTEGER CHECK (accepted_rows >= 0),
    rejected_rows INTEGER CHECK (rejected_rows >= 0)
);
CREATE INDEX IF NOT EXISTS idx_admin_audit_time ON admin_audit_events(occurred_at DESC, id DESC);
