CREATE TABLE IF NOT EXISTS import_registry (
    content_hash VARCHAR(64) PRIMARY KEY,
    file_id INTEGER NOT NULL UNIQUE REFERENCES imported_log_files(id),
    accepted_rows INTEGER NOT NULL CHECK (accepted_rows > 0),
    rejected_rows INTEGER NOT NULL DEFAULT 0 CHECK (rejected_rows >= 0)
);
CREATE INDEX IF NOT EXISTS idx_requests_file_id ON requests(file_id);
