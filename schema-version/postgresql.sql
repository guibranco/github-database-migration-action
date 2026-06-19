DROP TABLE IF EXISTS schema_version;

CREATE TABLE schema_version (
    sequence SERIAL       PRIMARY KEY,
    filename VARCHAR(255) NOT NULL UNIQUE,
    checksum CHAR(64)     NOT NULL UNIQUE,
    date     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);
