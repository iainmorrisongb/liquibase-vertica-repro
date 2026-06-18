#!/usr/bin/env bash
set -euo pipefail

# Reproduces: NullPointerException in liquibase-vertica 5.0.3 when a DATABASECHANGELOG
# table already exists from a Liquibase 4.23.1 run.
#
# Prerequisites: docker, curl, an existing Vertica instance
#
# Usage:
#   VERTICA_HOST=mylab VERTICA_DB=mydb ./reproduce.sh
#   VERTICA_HOST=mylab VERTICA_DB=mydb VERTICA_PASSWORD=secret ./reproduce.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="${SCRIPT_DIR}/ext"

LB_VERTICA_V4="4.23.1"
LB_VERTICA_V5="5.0.3"

VERTICA_HOST="${VERTICA_HOST:-localhost}"
VERTICA_PORT="${VERTICA_PORT:-5433}"
VERTICA_DB="${VERTICA_DB:-VMart}"
VERTICA_USER="${VERTICA_USER:-dbadmin}"
VERTICA_PASSWORD="${VERTICA_PASSWORD:-}"
VERTICA_JDBC_VERSION="${VERTICA_JDBC_VERSION:-12.0.0-0}"
SCHEMA="${SCHEMA:-testschema}"

# ──────────────────────────────────────────────────────────────────────────────
step() { echo; echo "=== $* ==="; }
# ──────────────────────────────────────────────────────────────────────────────

step "Downloading extension JARs (first run only)"

mkdir -p "${EXT_DIR}"

if [ ! -f "${EXT_DIR}/vertica-jdbc-${VERTICA_JDBC_VERSION}.jar" ]; then
  echo "Fetching Vertica JDBC ${VERTICA_JDBC_VERSION} from Maven Central..."
  curl -fL -o "${EXT_DIR}/vertica-jdbc-${VERTICA_JDBC_VERSION}.jar" \
    "https://repo1.maven.org/maven2/com/vertica/jdbc/vertica-jdbc/${VERTICA_JDBC_VERSION}/vertica-jdbc-${VERTICA_JDBC_VERSION}.jar"
fi

if [ ! -f "${EXT_DIR}/liquibase-vertica-${LB_VERTICA_V4}.jar" ]; then
  echo "Fetching liquibase-vertica ${LB_VERTICA_V4}..."
  curl -fL -o "${EXT_DIR}/liquibase-vertica-${LB_VERTICA_V4}.jar" \
    "https://github.com/liquibase/liquibase-vertica/releases/download/liquibase-vertica-${LB_VERTICA_V4}/liquibase-vertica-${LB_VERTICA_V4}.jar"
fi

if [ ! -f "${EXT_DIR}/liquibase-vertica-${LB_VERTICA_V5}.jar" ]; then
  echo "Fetching liquibase-vertica ${LB_VERTICA_V5}..."
  curl -fL -o "${EXT_DIR}/liquibase-vertica-${LB_VERTICA_V5}.jar" \
    "https://github.com/liquibase/liquibase-vertica/releases/download/v${LB_VERTICA_V5}/liquibase-vertica-${LB_VERTICA_V5}.jar"
fi

# ──────────────────────────────────────────────────────────────────────────────

step "Creating schema '${SCHEMA}' if it does not exist"
docker run --rm \
  --network host \
  -v "${EXT_DIR}/vertica-jdbc-${VERTICA_JDBC_VERSION}.jar:/liquibase/lib/vertica-jdbc.jar:ro" \
  -v "${EXT_DIR}/liquibase-vertica-${LB_VERTICA_V4}.jar:/liquibase/lib/liquibase-vertica.jar:ro" \
  "liquibase/liquibase:${LB_VERTICA_V4}" \
    --url="jdbc:vertica://${VERTICA_HOST}:${VERTICA_PORT}/${VERTICA_DB}" \
    --username="${VERTICA_USER}" \
    --password="${VERTICA_PASSWORD}" \
    --show-banner=false \
    execute-sql --sql="CREATE SCHEMA IF NOT EXISTS ${SCHEMA}"

# ──────────────────────────────────────────────────────────────────────────────
# Helper: run Liquibase in a Docker container targeting the external Vertica.
# $1 = Liquibase version (e.g. "4.23.1")
# $2 = liquibase-vertica JAR filename inside ${EXT_DIR}
# ──────────────────────────────────────────────────────────────────────────────
run_liquibase() {
  local LB_VERSION="$1"
  local LV_JAR="$2"

  docker run --rm \
    --network host \
    -v "${EXT_DIR}/vertica-jdbc-${VERTICA_JDBC_VERSION}.jar:/liquibase/lib/vertica-jdbc.jar:ro" \
    -v "${EXT_DIR}/${LV_JAR}:/liquibase/lib/liquibase-vertica.jar:ro" \
    -v "${SCRIPT_DIR}/changelog:/changelogs:ro" \
    -w "/changelogs" \
    "liquibase/liquibase:${LB_VERSION}" \
      --url="jdbc:vertica://${VERTICA_HOST}:${VERTICA_PORT}/${VERTICA_DB}" \
      --username="${VERTICA_USER}" \
      --password="${VERTICA_PASSWORD}" \
      --changelog-file=master-changelog.yaml \
      --default-schema-name="${SCHEMA}" \
      --liquibase-schema-name="${SCHEMA}" \
      --show-banner=false \
      update
}

# ──────────────────────────────────────────────────────────────────────────────

step "Step 1 — Liquibase ${LB_VERTICA_V4} + liquibase-vertica ${LB_VERTICA_V4} (should succeed)"
echo "This establishes DATABASECHANGELOG / DATABASECHANGELOGLOCK in schema '${SCHEMA}'."
echo ""
if run_liquibase "${LB_VERTICA_V4}" "liquibase-vertica-${LB_VERTICA_V4}.jar"; then
  echo ""
  echo "SUCCESS: Liquibase ${LB_VERTICA_V4} ran without errors."
  echo "DATABASECHANGELOG now exists in schema '${SCHEMA}'."
else
  echo ""
  echo "UNEXPECTED FAILURE: Liquibase ${LB_VERTICA_V4} failed. Cannot continue."
  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────

step "Step 2 — Liquibase ${LB_VERTICA_V5} + liquibase-vertica ${LB_VERTICA_V5} (expected to fail)"
echo "Running against the same database where DATABASECHANGELOG was created by ${LB_VERTICA_V4}."
echo ""
if run_liquibase "${LB_VERTICA_V5}" "liquibase-vertica-${LB_VERTICA_V5}.jar"; then
  echo ""
  echo "Liquibase ${LB_VERTICA_V5} SUCCEEDED — bug may be fixed or not triggered."
else
  echo ""
  echo "Liquibase ${LB_VERTICA_V5} FAILED — bug reproduced."
  echo ""
  echo "Expected error:"
  echo "  ERROR: Exception Primary Class:  NullPointerException"
  echo "  ERROR: Exception Primary Reason:  Cannot invoke \"liquibase.structure.core.Column.getType()\""
  echo "         because the return value of \"liquibase.structure.core.Table.getColumn(String)\" is null"
  echo "  ERROR: Exception Primary Source:  Vertica Database <version>"
fi

echo ""
echo "Done."
