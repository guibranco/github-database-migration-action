-- Oracle11g schema for schema_version tracking table.
-- Run this once to initialise (or reset) the table in your Oracle database.
-- NOTE: Oracle does not support IF EXISTS / IF NOT EXISTS in DDL prior to 23c.
--       Drop the table manually if it already exists before running this script.

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE schema_version';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE schema_version (
    sequence  NUMBER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    filename  VARCHAR2(255) NOT NULL UNIQUE,
    checksum  CHAR(64)      NOT NULL UNIQUE,
    date_col  TIMESTAMP     DEFAULT CURRENT_TIMESTAMP NOT NULL
);
/
