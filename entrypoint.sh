#!/bin/sh
set -e

OPERATION="${1}"
DRIVER="${2}"
HOST="${3}"
DB_USER="${4}"
DATABASE="${5}"
INTEGRITY_FILE="${6}"

# DATABASE_PWD is read from the environment

# --- Input validation ---

case "${OPERATION}" in
  dry-run|migrate|check|integrity) ;;
  *)
    echo "::error::Invalid OPERATION '${OPERATION}'. Must be one of: dry-run, migrate, check, integrity"
    exit 1
    ;;
esac

case "${DRIVER}" in
  mysql|mariadb|postgresql|mssql|oracle11g) ;;
  *)
    echo "::error::Invalid DRIVER '${DRIVER}'. Must be one of: mysql, mariadb, postgresql, mssql, oracle11g"
    exit 1
    ;;
esac

if [ "${DRIVER}" = "oracle11g" ]; then
  echo "::error::Oracle11g requires Oracle Instant Client which cannot be bundled due to licensing."
  echo "::error::Build a custom image FROM this action and add Oracle Instant Client and sqlplus manually."
  exit 1
fi

echo "Operation : ${OPERATION}"
echo "Driver    : ${DRIVER}"
echo "Host      : ${HOST}"
echo "User      : ${DB_USER}"
echo "Database  : ${DATABASE}"
[ -n "${INTEGRITY_FILE}" ] && echo "Integrity : ${INTEGRITY_FILE}"

# --- Driver-specific SQL execution ---

exec_sql_mysql() {
  mysql --host="${HOST}" --user="${DB_USER}" \
    ${DATABASE_PWD:+--password="${DATABASE_PWD}"} \
    --batch --skip-column-names \
    --database="${DATABASE}" \
    --execute="${1}"
}

exec_file_mysql() {
  mysql --host="${HOST}" --user="${DB_USER}" \
    ${DATABASE_PWD:+--password="${DATABASE_PWD}"} \
    --database="${DATABASE}" < "${1}"
}

exec_sql_pgsql() {
  PGPASSWORD="${DATABASE_PWD:-}" psql \
    --host="${HOST}" --username="${DB_USER}" --dbname="${DATABASE}" \
    --tuples-only --no-align \
    --command="${1}"
}

exec_file_pgsql() {
  PGPASSWORD="${DATABASE_PWD:-}" psql \
    --host="${HOST}" --username="${DB_USER}" --dbname="${DATABASE}" \
    --file="${1}"
}

exec_sql_mssql() {
  # Append GO to execute the batch; redirect stderr (freetds locale/charset noise)
  printf '%s\nGO\n' "${1}" | \
    tsql -H "${HOST}" -U "${DB_USER}" -P "${DATABASE_PWD:-}" \
    -D "${DATABASE}" 2>/dev/null | \
    grep -v "^[0-9]*>" | grep -vE "^-+$" | grep -v "^([0-9]" || true
}

exec_file_mssql() {
  { cat "${1}"; printf '\nGO\n'; } | \
    tsql -H "${HOST}" -U "${DB_USER}" -P "${DATABASE_PWD:-}" \
    -D "${DATABASE}" 2>/dev/null
}

sql_run() {
  case "${DRIVER}" in
    mysql|mariadb) exec_sql_mysql "${1}" ;;
    postgresql)    exec_sql_pgsql "${1}" ;;
    mssql)         exec_sql_mssql "${1}" ;;
  esac
}

sql_file() {
  case "${DRIVER}" in
    mysql|mariadb) exec_file_mysql "${1}" ;;
    postgresql)    exec_file_pgsql "${1}" ;;
    mssql)         exec_file_mssql "${1}" ;;
  esac
}

# --- Schema initialization (CREATE TABLE IF NOT EXISTS) ---

init_schema() {
  echo "Ensuring schema_version table exists..."
  case "${DRIVER}" in
    mysql|mariadb)
      mysql --host="${HOST}" --user="${DB_USER}" \
        ${DATABASE_PWD:+--password="${DATABASE_PWD}"} \
        --database="${DATABASE}" << 'SQL'
CREATE TABLE IF NOT EXISTS `schema_version` (
  `Sequence` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `Filename` VARCHAR(255) NOT NULL,
  `Checksum`  CHAR(64)    NOT NULL,
  `Date`      TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`Sequence`),
  UNIQUE (`Filename`),
  UNIQUE (`Checksum`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SQL
      ;;
    postgresql)
      PGPASSWORD="${DATABASE_PWD:-}" psql \
        --host="${HOST}" --username="${DB_USER}" --dbname="${DATABASE}" << 'SQL'
CREATE TABLE IF NOT EXISTS schema_version (
  sequence SERIAL       PRIMARY KEY,
  filename VARCHAR(255) NOT NULL UNIQUE,
  checksum CHAR(64)     NOT NULL UNIQUE,
  date     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);
SQL
      ;;
    mssql)
      tsql -H "${HOST}" -U "${DB_USER}" -P "${DATABASE_PWD:-}" \
        -D "${DATABASE}" 2>/dev/null << 'SQL'
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name='schema_version')
  CREATE TABLE schema_version (
    Sequence INT IDENTITY(1,1) PRIMARY KEY,
    Filename NVARCHAR(255) NOT NULL,
    Checksum CHAR(64)      NOT NULL,
    Date     DATETIME      NOT NULL DEFAULT GETDATE(),
    CONSTRAINT UQ_sv_Filename UNIQUE (Filename),
    CONSTRAINT UQ_sv_Checksum UNIQUE (Checksum)
  );
GO
SQL
      ;;
  esac
}

# --- Migration helpers ---

APPLIED_CACHE="/tmp/applied_migrations.txt"

# Loads applied migration filenames into APPLIED_CACHE.
# Uses a 'MIG:' prefix on the SELECT so we can reliably identify data rows
# in the output regardless of column headers or driver-specific noise.
load_applied() {
  case "${DRIVER}" in
    mysql|mariadb)
      exec_sql_mysql "SELECT CONCAT('MIG:', Filename) FROM schema_version ORDER BY Sequence;" \
        | grep "^MIG:" | sed 's/^MIG://' | sed 's/[[:space:]]*$//' > "${APPLIED_CACHE}"
      ;;
    postgresql)
      exec_sql_pgsql "SELECT 'MIG:' || filename FROM schema_version ORDER BY sequence;" \
        | grep "^MIG:" | sed 's/^MIG://' | sed 's/[[:space:]]*$//' > "${APPLIED_CACHE}"
      ;;
    mssql)
      exec_sql_mssql "SELECT 'MIG:' + Filename FROM schema_version ORDER BY Sequence;" \
        | grep "^MIG:" | sed 's/^MIG://' | sed 's/[[:space:]]*$//' > "${APPLIED_CACHE}"
      ;;
  esac
}

is_applied() {
  grep -qFx "${1}" "${APPLIED_CACHE}" 2>/dev/null
}

record_migration() {
  fn=$(printf '%s' "${1}" | sed "s/'/''/g")   # escape single quotes
  cs="${2}"
  case "${DRIVER}" in
    mysql|mariadb)
      exec_sql_mysql "INSERT INTO \`schema_version\` (\`Filename\`, \`Checksum\`) VALUES ('${fn}', '${cs}');" > /dev/null
      ;;
    postgresql)
      exec_sql_pgsql "INSERT INTO schema_version (filename, checksum) VALUES ('${fn}', '${cs}');" > /dev/null
      ;;
    mssql)
      exec_sql_mssql "INSERT INTO schema_version (Filename, Checksum) VALUES ('${fn}', '${cs}');" > /dev/null
      ;;
  esac
}

checksum_file() {
  sha256sum "${1}" | cut -d' ' -f1
}

# Reject filenames that could smuggle SQL injection via the INSERT.
validate_filename() {
  case "${1}" in
    *[!A-Za-z0-9._-]*)
      echo "::error::Unsafe migration filename '${1}'. Only A-Z, a-z, 0-9, dot, hyphen, underscore are allowed."
      exit 1
      ;;
  esac
}

# --- Main ---

WORKSPACE="${GITHUB_WORKSPACE:-/github/workspace}"
MIGRATIONS_DIR="${WORKSPACE}/migrations"
MIGRATION_LIST="/tmp/migration_files.txt"

echo ""
echo "Connecting to ${DRIVER} at ${HOST}..."
init_schema
echo "Schema ready."
echo ""

if [ ! -d "${MIGRATIONS_DIR}" ]; then
  echo "::error::Migrations directory not found: ${MIGRATIONS_DIR}"
  echo "::error::Create a 'migrations/' directory in your repository root and add .sql files."
  exit 1
fi

find "${MIGRATIONS_DIR}" -maxdepth 1 -name "*.sql" -type f | sort > "${MIGRATION_LIST}"
TOTAL=$(wc -l < "${MIGRATION_LIST}" | tr -d ' ')
echo "Found ${TOTAL} migration file(s) in ${MIGRATIONS_DIR}"

load_applied
APPLIED_TOTAL=$(wc -l < "${APPLIED_CACHE}" | tr -d ' ')
echo "Previously applied: ${APPLIED_TOTAL}"
echo ""

# --- Operations ---

case "${OPERATION}" in

  check)
    echo "=== Migration Status ==="
    APPLIED_COUNT=0
    PENDING_COUNT=0
    while IFS= read -r file; do
      [ -z "${file}" ] && continue
      fn=$(basename "${file}")
      validate_filename "${fn}"
      if is_applied "${fn}"; then
        printf "[APPLIED]  %s\n" "${fn}"
        APPLIED_COUNT=$((APPLIED_COUNT + 1))
      else
        printf "[PENDING]  %s\n" "${fn}"
        PENDING_COUNT=$((PENDING_COUNT + 1))
      fi
    done < "${MIGRATION_LIST}"
    echo ""
    echo "Applied: ${APPLIED_COUNT}  |  Pending: ${PENDING_COUNT}"
    ;;

  dry-run)
    echo "=== Dry Run (pending migrations only) ==="
    PENDING_COUNT=0
    while IFS= read -r file; do
      [ -z "${file}" ] && continue
      fn=$(basename "${file}")
      validate_filename "${fn}"
      if ! is_applied "${fn}"; then
        printf "[PENDING]  %s\n" "${fn}"
        PENDING_COUNT=$((PENDING_COUNT + 1))
      fi
    done < "${MIGRATION_LIST}"
    if [ "${PENDING_COUNT}" -eq 0 ]; then
      echo "No pending migrations."
    else
      echo ""
      echo "Total pending: ${PENDING_COUNT}"
    fi
    ;;

  migrate)
    echo "=== Applying Migrations ==="
    NEW_COUNT=0
    SKIP_COUNT=0
    while IFS= read -r file; do
      [ -z "${file}" ] && continue
      fn=$(basename "${file}")
      validate_filename "${fn}"
      if is_applied "${fn}"; then
        printf "[SKIP]     %s\n" "${fn}"
        SKIP_COUNT=$((SKIP_COUNT + 1))
      else
        printf "[APPLY]    %s\n" "${fn}"
        cs=$(checksum_file "${file}")
        sql_file "${file}"
        record_migration "${fn}" "${cs}"
        printf "[DONE]     %s  (sha256: %s)\n" "${fn}" "${cs}"
        NEW_COUNT=$((NEW_COUNT + 1))
      fi
    done < "${MIGRATION_LIST}"
    echo ""
    echo "Applied: ${NEW_COUNT}  |  Skipped: ${SKIP_COUNT}"
    ;;

  integrity)
    echo "=== Integrity Checks ==="
    if [ -z "${INTEGRITY_FILE}" ]; then
      echo "::error::INTEGRITY_COMMANDS_FILE must be set for the integrity operation."
      exit 1
    fi
    # Resolve relative paths against the workspace
    if [ ! -f "${INTEGRITY_FILE}" ] && [ -f "${WORKSPACE}/${INTEGRITY_FILE}" ]; then
      INTEGRITY_FILE="${WORKSPACE}/${INTEGRITY_FILE}"
    fi
    if [ ! -f "${INTEGRITY_FILE}" ]; then
      echo "::error::Integrity commands file not found: ${INTEGRITY_FILE}"
      exit 1
    fi
    PASS=0
    FAIL=0
    while IFS= read -r cmd || [ -n "${cmd}" ]; do
      cmd=$(printf '%s' "${cmd}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
      [ -z "${cmd}" ] && continue
      case "${cmd}" in '#'*) continue ;; esac
      printf "CHECK: %s\n" "${cmd}"
      result=$(sql_run "${cmd}" 2>&1 | sed '/^[[:space:]]*$/d' | head -1 || true)
      if [ -n "${result}" ]; then
        printf "  [PASS] %s\n" "${result}"
        PASS=$((PASS + 1))
      else
        printf "  [FAIL] Query returned no results\n"
        FAIL=$((FAIL + 1))
      fi
    done < "${INTEGRITY_FILE}"
    echo ""
    echo "Passed: ${PASS}  |  Failed: ${FAIL}"
    if [ "${FAIL}" -gt 0 ]; then
      echo "::error::${FAIL} integrity check(s) failed"
      exit 1
    fi
    ;;

esac

time=$(date)
echo "time=${time}" >> "${GITHUB_OUTPUT:-/dev/null}"
