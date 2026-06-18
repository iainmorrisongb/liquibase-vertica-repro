# NullPointerException: Cannot invoke Column.getType() because Table.getColumn(String) is null when upgrading from 4.23.1 to 5.0.3

## Environment

- **Liquibase Version**: 5.0.3
- **Integration**: CLI (`liquibase update`)
- **Extension(s) and version(s)**: liquibase-vertica 5.0.3
- **Database vendor and version**: Vertica 25.03.0006
- **Java version**: 21.0.11
- **Vertica JDBC version**: 12.0.0-0
- **Operating System**: Linux (Debian 13 / Trixie)

## Description

After upgrading from Liquibase 4.23.1 + liquibase-vertica 4.23.1 to Liquibase 5.0.3 + liquibase-vertica 5.0.3, the `liquibase update` command fails with a `NullPointerException` on any database that already has a `DATABASECHANGELOG` table created by the previous 4.23.1 installation.

The exception occurs early in the startup sequence — before any changesets are evaluated — suggesting the NPE is triggered during Liquibase's database introspection phase (snapshotting the existing `DATABASECHANGELOG` or `DATABASECHANGELOGLOCK` tables). The error message attributes the failure to "Vertica Database 25.03.0006", indicating it originates in the Vertica-specific snapshot or type-mapping code path.

Rolling back to Liquibase 4.23.1 + liquibase-vertica 4.23.1 immediately resolves the issue on the same database.

## Steps To Reproduce

A self-contained reproduction project is available at: https://github.com/iainmorrisongb/liquibase-vertica-repro
*(see README.md for setup instructions, or follow the manual steps below)*

### Prerequisites

- An existing Vertica instance (any version)
- Docker (used to run Liquibase — no local Java install needed)
- `curl`

### Manual steps

**1. Create a target schema**

```bash
vsql -h <host> -U dbadmin -d <database> -c "CREATE SCHEMA IF NOT EXISTS testschema"
```

**2. Create the changelogs**

`master-changelog.yaml`:
```yaml
databaseChangeLog:
  - include:
      file: schema-changelog.sql
```

`schema-changelog.sql`:
```sql
--liquibase formatted sql

--changeset repro-author:1
CREATE TABLE testschema.event_data
(
    eventId   INTEGER,
    eventName VARCHAR(128),
    createdAt TIMESTAMP DEFAULT NOW()
);

--changeset repro-author:2
INSERT INTO testschema.event_data(eventId, eventName) VALUES (1, 'bootstrap-event');
```

**3. Download the required JARs**

```bash
# Vertica JDBC 12.0.0-0 (Maven Central)
curl -L -o vertica-jdbc-12.0.0-0.jar \
  https://repo1.maven.org/maven2/com/vertica/jdbc/vertica-jdbc/12.0.0-0/vertica-jdbc-12.0.0-0.jar

# liquibase-vertica 4.23.1
curl -L -o liquibase-vertica-4.23.1.jar \
  https://github.com/liquibase/liquibase-vertica/releases/download/liquibase-vertica-4.23.1/liquibase-vertica-4.23.1.jar

# liquibase-vertica 5.0.3
curl -L -o liquibase-vertica-5.0.3.jar \
  https://github.com/liquibase/liquibase-vertica/releases/download/v5.0.3/liquibase-vertica-5.0.3.jar
```

**4. Run `liquibase update` with Liquibase 4.23.1 (succeeds)**

```bash
docker run --rm \
  --network host \
  -v /path/to/vertica-jdbc-12.0.0-0.jar:/liquibase/lib/vertica-jdbc.jar:ro \
  -v /path/to/liquibase-vertica-4.23.1.jar:/liquibase/lib/liquibase-vertica.jar:ro \
  -v /path/to/changelog:/changelogs:ro \
  -w /changelogs \
  liquibase/liquibase:4.23.1 \
    --url=jdbc:vertica://<host>:5433/<database> \
    --username=dbadmin \
    --password=<password> \
    --changelog-file=master-changelog.yaml \
    --default-schema-name=testschema \
    --liquibase-schema-name=testschema \
    --show-banner=false \
    update
```

This succeeds and creates `testschema.DATABASECHANGELOG` and `testschema.DATABASECHANGELOGLOCK`.

**5. Run `liquibase update` with Liquibase 5.0.3 against the same database (fails)**

```bash
docker run --rm \
  --network host \
  -v /path/to/vertica-jdbc-12.0.0-0.jar:/liquibase/lib/vertica-jdbc.jar:ro \
  -v /path/to/liquibase-vertica-5.0.3.jar:/liquibase/lib/liquibase-vertica.jar:ro \
  -v /path/to/changelog:/changelogs:ro \
  -w /changelogs \
  liquibase/liquibase:5.0.3 \
    --url=jdbc:vertica://<host>:5433/<database> \
    --username=dbadmin \
    --password=<password> \
    --changelog-file=master-changelog.yaml \
    --default-schema-name=testschema \
    --liquibase-schema-name=testschema \
    --show-banner=false \
    update
```

## Actual Behavior

Liquibase 5.0.3 exits with a non-zero code and prints:

```
Starting Liquibase at HH:MM:SS using Java 21.0.11 (version 5.0.3 #10665 built at 2026-05-13 17:55+0000)
Liquibase Version: 5.0.3

checking for vertica
ERROR: Exception Details
ERROR: Exception Primary Class:  NullPointerException
ERROR: Exception Primary Reason:  Cannot invoke "liquibase.structure.core.Column.getType()" because the return value of "liquibase.structure.core.Table.getColumn(String)" is null
ERROR: Exception Primary Source:  Vertica Database 25.03.0006

Unexpected error running Liquibase: Error parsing master-changelog.yaml : Cannot invoke "liquibase.structure.core.Column.getType()" because the return value of "liquibase.structure.core.Table.getColumn(String)" is null

For more information, please use the --log-level flag
```

The failure occurs immediately after the Vertica connection is established — before any changesets are evaluated — indicating it is triggered during the initial schema introspection phase (most likely while snapshotting `DATABASECHANGELOG` or `DATABASECHANGELOGLOCK` tables left by the 4.23.1 run).

## Expected/Desired Behavior

Liquibase 5.0.3 with liquibase-vertica 5.0.3 should successfully connect to a Vertica database that contains a `DATABASECHANGELOG` table created by Liquibase 4.23.1, and proceed to apply any pending changesets.

## Additional Context

- The issue is **not** present when running against a **fresh** database (no pre-existing `DATABASECHANGELOG`) with Liquibase 5.0.3 — only the upgrade path from a 4.x-managed database triggers the NPE.
- Rolling back to Liquibase 4.23.1 + liquibase-vertica 4.23.1 on the same database immediately resolves the failure.
- The `DATABASECHANGELOG` and `DATABASECHANGELOGLOCK` tables reside in the schema specified by `--liquibase-schema-name` (not the default `public` schema). It is unknown whether the NPE also occurs when these tables are in the default schema.
- A possible root cause: the liquibase-vertica snapshot generator may have a case-sensitivity regression when mapping Vertica's lowercased catalog entries back to the column name Liquibase expects. If `Table.getColumn(expectedName)` returns `null` because the casing does not match, the subsequent `.getType()` call throws the NPE.
- The `--log-level=FINE` output should reveal the exact column name that triggers the NPE and the call site within the extension.
