-- OVERLAP auth session persistence (manual migration; do not run automatically).
-- Review the target database and take a backup before an operator applies this.
-- This adds one table and does not alter or delete existing user/group/record data.

CREATE TABLE auth_sessions (
    id INT NOT NULL AUTO_INCREMENT,
    session_id CHAR(36) NOT NULL,
    user_id BIGINT NOT NULL,
    access_token_hash CHAR(64) NOT NULL,
    access_expires_at DATETIME NOT NULL,
    refresh_token_hash CHAR(64) NOT NULL,
    refresh_expires_at DATETIME NOT NULL,
    session_expires_at DATETIME NOT NULL,
    issued_at DATETIME NOT NULL,
    rotated_at DATETIME NULL,
    revoked_at DATETIME NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_auth_sessions_session_id (session_id),
    UNIQUE KEY uq_auth_sessions_access_token_hash (access_token_hash),
    UNIQUE KEY uq_auth_sessions_refresh_token_hash (refresh_token_hash),
    KEY ix_auth_sessions_user_id (user_id),
    CONSTRAINT fk_auth_sessions_user_id
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
