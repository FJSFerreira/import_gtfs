# GTFS to PostgreSQL Importer

A Python command-line utility that creates a PostgreSQL database if needed, recreates a target schema, creates GTFS-related tables, and imports GTFS text files (`.txt`) into PostgreSQL.

It supports three input sources:

- A local folder containing GTFS `.txt` files.
- A local ZIP archive containing GTFS `.txt` files.
- A URL pointing to a ZIP archive containing GTFS `.txt` files.

## What it does

1. Prepares the GTFS input source. For ZIP files and URLs, it extracts only `.txt` files into a temporary directory.
2. Checks whether the requested PostgreSQL database exists and creates it if it does not.
3. Connects to the target database.
4. **Drops and recreates the requested schema.** This deletes all existing objects inside that schema.
5. Creates the tables defined in `create_gtfs_schema.sql`.
6. Imports each `.txt` file into the table with the same filename (for example, `stops.txt` into `stops`).
7. Uses PostgreSQL `COPY` to load rows into a temporary staging table, then inserts them into the target table.
8. Ignores rows that conflict with unique or primary-key constraints and reports inserted and ignored row counts. Files without a matching table are skipped.

The importer uses columns present in both the input file header and the destination table. Extra input columns are ignored. The importer does not perform complete validation against the GTFS specification.

## Files

Keep these files in the same directory:

- `import_gtfs.py` — the command-line importer.
- `create_gtfs_schema.sql` — SQL definitions used to create the tables.

> The script currently looks specifically for `create_gtfs_schema.sql` in the same directory as `import_gtfs.py`.

## Requirements

- Python 3.9 or newer.
- PostgreSQL reachable from the computer running the script.
- A PostgreSQL account that can connect to the maintenance database `postgres`, create databases when needed, connect to the target database, and drop/create the target schema and its tables.
- Python package `psycopg` version 3.

Install the dependency:

```bash
python -m pip install "psycopg[binary]>=3.1"
```

## Input formats

### Folder

The folder should contain GTFS `.txt` files directly inside it, for example:

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

The folder mode does not search subdirectories.

### ZIP file or URL

The ZIP archive can contain `.txt` files at its root or in subdirectories. The importer searches recursively after extracting the `.txt` files. Non-`.txt` files are ignored. For URL mode, the URL must point directly to a ZIP archive; the download timeout is 60 seconds.

For all modes, filenames are matched to table names by removing the extension and converting the name to lowercase. For example, `STOP_TIMES.txt` maps to `stop_times`.

## Usage

```text
python import_gtfs.py SOURCE DATABASE SCHEMA [--source-type {folder,zip,url}] [--host HOST] [--port PORT] [--user USER]
```

| Argument | Description | Default |
|---|---|---|
| `SOURCE` | Folder path, ZIP file path, or ZIP URL, according to `--source-type` | Required |
| `DATABASE` | PostgreSQL database name to use or create | Required |
| `SCHEMA` | Schema to drop and recreate in that database | Required |
| `--source-type` | Input type: `folder`, `zip`, or `url` | `folder` |
| `--host` | PostgreSQL server hostname or address | `localhost` |
| `--port` | PostgreSQL server port | `5432` |
| `--user` | PostgreSQL username | `postgres` |

The password is read from the `PGPASSWORD` environment variable if set. Otherwise, the script prompts for it interactively. Avoid putting passwords directly in the command line or in this README.

## Examples

### 1. Import from a folder

```bash
python import_gtfs.py "./gtfs" transporthub gtfs
```

This is the default mode, so `--source-type folder` is optional. The folder must contain the `.txt` files directly inside it.

### 2. Import from a local ZIP file

```bash
python import_gtfs.py "./gtfs.zip" transporthub gtfs --source-type zip
```

### 3. Import from a ZIP URL

```bash
python import_gtfs.py "https://example.org/gtfs.zip" transporthub gtfs --source-type url
```

The URL must return the ZIP file itself, not an HTML download page.

### 4. Specify PostgreSQL connection details

```bash
python import_gtfs.py "./gtfs.zip" transporthub gtfs --source-type zip --host localhost --port 5432 --user postgres
```

### Set `PGPASSWORD` (optional)

PowerShell:

```powershell
$env:PGPASSWORD = "your-password"
python .\import_gtfs.py ".\gtfs" transporthub gtfs
```

Command Prompt (`cmd.exe`):

```bat
set PGPASSWORD=your-password
python import_gtfs.py ".\gtfs" transporthub gtfs
```

Linux/macOS shell:

```bash
export PGPASSWORD='your-password'
python import_gtfs.py ./gtfs transporthub gtfs
```

## Important warning

**The target schema is dropped and recreated on every run.** All tables, data, views, and other objects in that schema will be deleted. Choose a dedicated schema and back up any data you need before running the importer.

If the database already exists, the script does not drop the database; it only recreates the selected schema.

ZIP downloads and extracted files are stored in a temporary directory, which is removed automatically when the script finishes. The importer only extracts `.txt` files from ZIP archives and checks archive paths to prevent writing outside the temporary extraction directory.

## Troubleshooting

- **`ModuleNotFoundError: No module named 'psycopg'`** — install the dependency with `python -m pip install "psycopg[binary]>=3.1"`.
- **Permission denied / insufficient privilege** — use a PostgreSQL account with the required database and schema permissions.
- **SQL file not found** — ensure `create_gtfs_schema.sql` is in the same directory as `import_gtfs.py`.
- **No `.txt` files found** — check the selected source and `--source-type`. For folder mode, files must be directly inside the folder; ZIP modes search subdirectories.
- **Invalid ZIP archive** — ensure the local file or URL points to a valid ZIP archive.
- **Download error** — check the URL, network access, and whether the URL points directly to a ZIP file.
- **Files are skipped** — check that the filename matches a table defined in `create_gtfs_schema.sql`.
- **Some files report errors** — the importer reports errors per file and exits with an error summary if any file fails. Check the specific error message for the file.

## Example output

Output varies depending on the files and database state, but may look like:

```text
Source type: zip; found 7 .txt file(s)
OK: database 'transporthub' already exists
OK: schema 'gtfs' recreated
OK: tables created from 'create_gtfs_schema.sql'
OK: stops.txt - 1200 inserted, 0 duplicates ignored
Import completed successfully.
```
