#!/usr/bin/env bash
set -euo pipefail

# Drops the repro schema so reproduce.sh can be run again from a clean state.
#
# Usage:
#   VERTICA_HOST=mylab VERTICA_DB=mydb ./cleanup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="${SCRIPT_DIR}/ext"

VERTICA_HOST="${VERTICA_HOST:-localhost}"
VERTICA_PORT="${VERTICA_PORT:-5433}"
VERTICA_DB="${VERTICA_DB:-VMart}"
VERTICA_USER="${VERTICA_USER:-dbadmin}"
VERTICA_PASSWORD="${VERTICA_PASSWORD:-}"
VERTICA_JDBC_VERSION="${VERTICA_JDBC_VERSION:-12.0.0-0}"
SCHEMA="${SCHEMA:-testschema}"

echo "Dropping schema '${SCHEMA}' from ${VERTICA_HOST}:${VERTICA_PORT}/${VERTICA_DB}..."

docker run --rm \
  --network host \
  -v "${EXT_DIR}/vertica-jdbc-${VERTICA_JDBC_VERSION}.jar:/liquibase/lib/vertica-jdbc.jar:ro" \
  -v "${EXT_DIR}/liquibase-vertica-4.23.1.jar:/liquibase/lib/liquibase-vertica.jar:ro" \
  liquibase/liquibase:4.23.1 \
    --url="jdbc:vertica://${VERTICA_HOST}:${VERTICA_PORT}/${VERTICA_DB}" \
    --username="${VERTICA_USER}" \
    --password="${VERTICA_PASSWORD}" \
    --show-banner=false \
    execute-sql --sql="DROP SCHEMA IF EXISTS ${SCHEMA} CASCADE"

echo "Done. Run ./reproduce.sh to start fresh."
