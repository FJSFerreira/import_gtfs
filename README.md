# GTFS to PostgreSQL Importer

A Python command-line utility that creates a PostgreSQL database if needed, recreates a target schema, creates GTFS-related tables, and imports GTFS text files (`.txt`) into those tables.

## What it does

1. Checks whether the requested PostgreSQL database exists and creates it if it does not.
2. Connects to that database.
3. **Drops and recreates the requested schema.** This deletes all existing objects inside that schema.
4. Creates the tables defined in `create_gtfs_schema.sql`.
5. Finds `.txt` files in the supplied directory and imports matching files into tables with the same name (for example, `agency.txt` into `agency`).
6. Uses PostgreSQL `COPY` to load rows efficiently into a temporary staging table, then inserts them into the target table.
7. Ignores rows that conflict with unique or primary-key constraints and reports the number of inserted and ignored rows. Files without a matching table are skipped.

The SQL schema includes core GTFS tables and additional GTFS-related tables, including plans, pathways, and fare tables. Columns are generally defined as `TEXT`; the importer does not validate the full GTFS specification or convert values to native PostgreSQL date, time, or numeric types.

## Files

Keep these files together in the same directory:

- `import_gtfs.py` — the command-line importer.
- `create_gtfs_schema.sql` — SQL definitions for the tables.

## Requirements

- Python 3.9 or newer.
- PostgreSQL, with a server reachable from the computer running the script.
- A PostgreSQL account that can connect to the maintenance database `postgres`, create databases when needed, connect to the target database, and drop/create the target schema and its tables.
- Python package `psycopg` version 3.

Install the dependency:

```bash
python -m pip install "psycopg[binary]>=3.1"
```

## Input data

The input directory should contain GTFS `.txt` files, for example:

```text
gtfs/
├── agency.txt
├── stops.txt
├── routes.txt
├── trips.txt
├── stop_times.txt
├── calendar.txt
└── calendar_dates.txt
```

Only `.txt` files directly inside the supplied directory are processed; subdirectories are not searched recursively. Each filename is matched to a table using its name without the extension, converted to lowercase. For example, `STOP_TIMES.txt` maps to `stop_times`.

The importer uses columns present in both the input file header and the destination table. Extra columns in a GTFS file are ignored. Files without a matching table are skipped.

## Configuration

Usage:

```text
python import_gtfs.py DIRECTORY DATABASE SCHEMA [--host HOST] [--port PORT] [--user USER]
```

| Argument | Description | Default |
|---|---|---|
| `DIRECTORY` | Directory containing GTFS `.txt` files | Required |
| `DATABASE` | PostgreSQL database name to use or create | Required |
| `SCHEMA` | Schema to drop and recreate in that database | Required |
| `--host` | PostgreSQL server hostname or address | `localhost` |
| `--port` | PostgreSQL server port | `5432` |
| `--user` | PostgreSQL username | `postgres` |

The password is read from the `PGPASSWORD` environment variable if it is set. Otherwise, the script prompts for it interactively. Avoid putting passwords directly in the command line or in this README.

## How to run

### 1. Install the dependency

```bash
python -m pip install "psycopg[binary]>=3.1"
```

### 2. Prepare the files

Place `import_gtfs.py` and `create_gtfs_schema.sql` in the same directory. Put the GTFS `.txt` files in an input directory.

### 3. Run the importer

Example using the default PostgreSQL connection settings:

```bash
python import_gtfs.py "./gtfs" transporthub gtfs
```

This uses or creates the database `transporthub` and recreates the schema `gtfs` inside it.

To specify connection settings:

```bash
python import_gtfs.py "./gtfs" transporthub gtfs --host localhost --port 5432 --user postgres
```

The script prompts for the PostgreSQL password unless `PGPASSWORD` is set.

#### Set `PGPASSWORD` (optional)

PowerShell:

```powershell
$env:PGPASSWORD = "your-password"
python .\import_gtfs.py ".\gtfs" transporthub gtfs --host localhost --port 5432 --user postgres
```

Command Prompt (`cmd.exe`):

```bat
set PGPASSWORD=your-password
python import_gtfs.py ".\gtfs" transporthub gtfs --host localhost --port 5432 --user postgres
```

Linux/macOS shell:

```bash
export PGPASSWORD='your-password'
python import_gtfs.py ./gtfs transporthub gtfs --host localhost --port 5432 --user postgres
```

## Important warning

**The target schema is dropped and recreated on every run.** All tables, data, views, and other objects in that schema will be deleted. Choose a dedicated schema and back up any data you need before running the importer.

If the database already exists, the script does not drop it; it only recreates the selected schema.

## Troubleshooting

- **`ModuleNotFoundError: No module named 'psycopg'`** — install the dependency with `python -m pip install "psycopg[binary]>=3.1"`.
- **Permission denied / insufficient privilege** — use a PostgreSQL account with the required database and schema permissions.
- **SQL file not found** — ensure `create_gtfs_schema.sql` is in the same directory as `import_gtfs.py`.
- **No `.txt` files found** — check that the input directory exists and contains GTFS files directly inside it.
- **Files are skipped** — check that the filename matches a table defined in `create_gtfs_schema.sql`.

## Example output

Output varies depending on the files and database state, but may look like:

```text
OK: database 'transporthub' already exists
OK: schema 'gtfs' recreated
OK: tables created from 'create_gtfs_schema.sql'
OK: agency.txt - 1 inserted, 0 duplicates ignored
Import completed successfully.
```
