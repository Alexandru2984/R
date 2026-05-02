-- init_db.sql
CREATE TABLE IF NOT EXISTS imported_log_files (
    id SERIAL PRIMARY KEY,
    filename VARCHAR(255) NOT NULL,
    imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    file_type VARCHAR(50) -- 'nginx' or 'cloudflare'
);

CREATE TABLE IF NOT EXISTS requests (
    id SERIAL PRIMARY KEY,
    file_id INTEGER REFERENCES imported_log_files(id),
    ip_address VARCHAR(45) NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    method VARCHAR(10),
    path TEXT,
    protocol VARCHAR(20),
    status_code INTEGER,
    response_size BIGINT,
    referrer TEXT,
    user_agent TEXT,
    bot_score NUMERIC(5, 2) DEFAULT 0.0,
    classification VARCHAR(50) DEFAULT 'unknown',
    country VARCHAR(10)
);

CREATE TABLE IF NOT EXISTS ip_summary (
    id SERIAL PRIMARY KEY,
    ip_address VARCHAR(45) UNIQUE NOT NULL,
    total_requests INTEGER DEFAULT 0,
    unique_paths INTEGER DEFAULT 0,
    error_404_count INTEGER DEFAULT 0,
    risk_score NUMERIC(5, 2) DEFAULT 0.0,
    classification VARCHAR(50) DEFAULT 'unknown',
    last_seen TIMESTAMP
);

CREATE TABLE IF NOT EXISTS suspicious_events (
    id SERIAL PRIMARY KEY,
    request_id INTEGER REFERENCES requests(id),
    ip_address VARCHAR(45) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    description TEXT,
    event_time TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS parser_errors (
    id SERIAL PRIMARY KEY,
    file_id INTEGER REFERENCES imported_log_files(id),
    raw_line TEXT,
    error_message TEXT,
    error_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_requests_ip ON requests(ip_address);
CREATE INDEX IF NOT EXISTS idx_requests_timestamp ON requests(timestamp);
CREATE INDEX IF NOT EXISTS idx_requests_path ON requests(path);
