# liquibase-vertica 5.0.3 — NullPointerException reproduction

Minimal reproduction of a `NullPointerException` in **liquibase-vertica 5.0.3** when running
`liquibase update` against a Vertica database whose `DATABASECHANGELOG` table was created by
Liquibase 4.23.1.

See [`ISSUE.md`](./ISSUE.md) for the full bug report (ready to paste into a GitHub issue).

## Prerequisites

- Docker (to run Liquibase — no local Java install needed)
- `curl`
- An existing Vertica instance

## Quick start

```bash
VERTICA_HOST=mylab \
VERTICA_DB=mydb \
./reproduce.sh
```

The script creates the schema (`testschema` by default) automatically if it does not exist,
so it is fully isolated — nothing outside that schema is touched.

The script will:

1. Download the required JARs into `./ext/` (one-time):
   - `vertica-jdbc-12.0.0-0.jar` from Maven Central
   - `liquibase-vertica-4.23.1.jar` from GitHub Releases
   - `liquibase-vertica-5.0.3.jar` from GitHub Releases
2. Run `liquibase update` with **Liquibase 4.23.1** — succeeds and writes
   `DATABASECHANGELOG` / `DATABASECHANGELOGLOCK` to `testschema`.
3. Run `liquibase update` with **Liquibase 5.0.3** against the same database — fails
   with the NPE.

## Configuration

All connection settings are overridable via environment variables:

| Variable | Default | Description |
|---|---|---|
| `VERTICA_HOST` | `localhost` | Vertica server hostname |
| `VERTICA_PORT` | `5433` | Vertica port |
| `VERTICA_DB` | `VMart` | Database name |
| `VERTICA_USER` | `dbadmin` | Username |
| `VERTICA_PASSWORD` | _(empty)_ | Password |
| `VERTICA_JDBC_VERSION` | `12.0.0-0` | JDBC driver version to download |
| `SCHEMA` | `testschema` | Schema for changelogs and tracking tables |

Example with all options:

```bash
VERTICA_HOST=mylab \
VERTICA_DB=mydb \
VERTICA_USER=dbadmin \
VERTICA_PASSWORD=secret \
VERTICA_JDBC_VERSION=24.4.0-0 \
SCHEMA=testschema \
./reproduce.sh
```

## Expected output (step 2 failure)

```
ERROR: Exception Details
ERROR: Exception Primary Class:  NullPointerException
ERROR: Exception Primary Reason:  Cannot invoke "liquibase.structure.core.Column.getType()" because the return value of "liquibase.structure.core.Table.getColumn(String)" is null
ERROR: Exception Primary Source:  Vertica Database <version>

Unexpected error running Liquibase: Error parsing master-changelog.yaml : Cannot invoke "liquibase.structure.core.Column.getType()" because the return value of "liquibase.structure.core.Table.getColumn(String)" is null
```

## Re-running from scratch

Use `cleanup.sh` to drop the schema — the same env vars as `reproduce.sh`:

```bash
VERTICA_HOST=mylab VERTICA_DB=mydb VERTICA_PASSWORD=secret ./cleanup.sh
```

`reproduce.sh` will recreate the schema on the next run.

## Troubleshooting

**JDBC connection refused**

Ensure `VERTICA_JDBC_VERSION` matches your Vertica server version. Available versions on
Maven Central start at `10.0.1-0`. Check with:

```bash
vsql -h <host> -U dbadmin -d <database> -c "SELECT version()"
```

**macOS / Docker Desktop**

`--network host` is not supported on macOS. Pass `--add-host host.docker.internal:host-gateway`
and set `VERTICA_HOST=host.docker.internal` if targeting localhost, or use the server's
hostname/IP directly for a remote instance.
