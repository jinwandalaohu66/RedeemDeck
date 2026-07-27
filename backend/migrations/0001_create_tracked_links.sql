CREATE TABLE tracked_links (id TEXT PRIMARY KEY NOT NULL, slug TEXT NOT NULL UNIQUE, client_id TEXT NOT NULL UNIQUE, destination_ciphertext TEXT NOT NULL, destination_iv TEXT NOT NULL, destination_hash TEXT NOT NULL, created_at TEXT NOT NULL, expires_at TEXT, first_seen_at TEXT, last_seen_at TEXT, visit_count INTEGER NOT NULL DEFAULT 0 CHECK (visit_count >= 0));

CREATE INDEX tracked_links_status_index ON tracked_links(id, client_id);
