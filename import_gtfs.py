import argparse
import csv
import getpass
import os
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

import psycopg
from psycopg import sql
from psycopg.errors import DuplicateDatabase


def parse_args():
    parser = argparse.ArgumentParser(
        description="Create a PostgreSQL database/schema and import GTFS files."
    )

    parser.add_argument(
        "source",
        help="GTFS source: folder path, ZIP file path, or ZIP URL (depending on --source-type)",
    )
    parser.add_argument("database", help="Database name")
    parser.add_argument("schema", help="Target schema name")
    parser.add_argument(
        "--source-type",
        choices=("folder", "zip", "url"),
        default="folder",
        help="Source type: folder (default), zip, or url (URL to a ZIP archive)",
    )
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--user", default="postgres")

    return parser.parse_args()


def ensure_database(config):
    """Create the database if it does not exist."""
    with psycopg.connect(
        host=config["host"],
        port=config["port"],
        dbname="postgres",
        user=config["user"],
        password=config["password"],
        autocommit=True,
    ) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT 1 FROM pg_database WHERE datname = %s",
                (config["dbname"],),
            )

            if cur.fetchone():
                print(f"OK: database '{config['dbname']}' already exists")
                return

            try:
                cur.execute(
                    sql.SQL("CREATE DATABASE {}").format(
                        sql.Identifier(config["dbname"])
                    )
                )
                print(f"OK: database '{config['dbname']}' created")
            except DuplicateDatabase:
                # Another process may have created it concurrently.
                print(f"OK: database '{config['dbname']}' already exists")


def recreate_schema(conn, schema):
    """Drop and recreate the target schema."""
    try:
        with conn.cursor() as cur:
            cur.execute(
                sql.SQL("DROP SCHEMA IF EXISTS {} CASCADE").format(
                    sql.Identifier(schema)
                )
            )
            cur.execute(
                sql.SQL("CREATE SCHEMA {}").format(
                    sql.Identifier(schema)
                )
            )
        conn.commit()
        print(f"OK: schema '{schema}' recreated")
    except Exception:
        conn.rollback()
        raise


def create_tables(conn, schema):
    """Execute create_gtfs_schema.sql."""
    script_path = Path(__file__).resolve().parent / "create_gtfs_schema.sql"

    if not script_path.is_file():
        raise FileNotFoundError(f"SQL file not found: {script_path}")

    with script_path.open("r", encoding="utf-8-sig") as f:
        script = f.read()

    # In create_gtfs_schema.sql, use {schema}.table_name for table names.
    quoted_schema = sql.Identifier(schema).as_string(conn)
    script = script.replace("{schema}", quoted_schema)

    try:
        with conn.cursor() as cur:
            cur.execute(script)
        conn.commit()
    except Exception:
        conn.rollback()
        raise

    print(f"OK: tables created from '{script_path.name}'")



def import_table(conn, schema, file_path):
    table_name = file_path.stem.lower()

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = %s
              AND table_name = %s
            ORDER BY ordinal_position
            """,
            (schema, table_name),
        )
        db_columns = [row[0] for row in cur.fetchall()]

    if not db_columns:
        print(f"SKIP: {file_path.name} - table not found")
        return

    with file_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)

        if not reader.fieldnames:
            print(f"SKIP: {file_path.name} - empty file")
            return

        original_headers = reader.fieldnames
        normalized_headers = [h.strip() for h in original_headers]

        if len(set(normalized_headers)) != len(normalized_headers):
            raise ValueError("Duplicate column names in CSV header")

        header_map = dict(zip(normalized_headers, original_headers))
        common_columns = [
            col for col in normalized_headers if col in db_columns
        ]

        if not common_columns:
            print(f"SKIP: {file_path.name} - no matching columns")
            return

        temp_table = f"_import_{table_name}"

        try:
            with conn.cursor() as cur:
                # Temporary table with the same column definitions,
                # but without primary keys or other constraints.
                cur.execute(
                    sql.SQL(
                        "CREATE TEMP TABLE {} "
                        "(LIKE {}.{} INCLUDING DEFAULTS) "
                        "ON COMMIT DROP"
                    ).format(
                        sql.Identifier(temp_table),
                        sql.Identifier(schema),
                        sql.Identifier(table_name),
                    )
                )

                copy_query = sql.SQL(
                    "COPY {} ({}) FROM STDIN"
                ).format(
                    sql.Identifier(temp_table),
                    sql.SQL(", ").join(
                        sql.Identifier(col) for col in common_columns
                    ),
                )

                count = 0
                with cur.copy(copy_query) as copy:
                    for row in reader:
                        copy.write_row([
                            row.get(header_map[col])
                            for col in common_columns
                        ])
                        count += 1

                insert_query = sql.SQL(
                    "INSERT INTO {}.{} ({}) "
                    "SELECT {} FROM {} "
                    "ON CONFLICT DO NOTHING"
                ).format(
                    sql.Identifier(schema),
                    sql.Identifier(table_name),
                    sql.SQL(", ").join(
                        sql.Identifier(col) for col in common_columns
                    ),
                    sql.SQL(", ").join(
                        sql.Identifier(col) for col in common_columns
                    ),
                    sql.Identifier(temp_table),
                )

                cur.execute(insert_query)
                inserted = cur.rowcount

            conn.commit()
            skipped = count - inserted
            print(
                f"OK: {file_path.name} - "
                f"{inserted} inserted, {skipped} duplicates ignored"
            )

        except Exception:
            conn.rollback()
            raise


def get_gtfs_files(source_type, source, temp_dir):
    """Prepare the source and return its GTFS .txt files."""
    if source_type == "folder":
        directory = Path(source)
        if not directory.is_dir():
            raise FileNotFoundError(f"Directory not found: {directory}")
        files = sorted(directory.glob("*.txt"))

    elif source_type == "zip":
        zip_path = Path(source)
        if not zip_path.is_file():
            raise FileNotFoundError(f"ZIP file not found: {zip_path}")
        directory = Path(temp_dir) / "gtfs"
        directory.mkdir()
        extract_gtfs_txt_files(zip_path, directory)
        files = sorted(directory.rglob("*.txt"))

    else:  # url
        directory = Path(temp_dir) / "gtfs"
        directory.mkdir()
        zip_path = Path(temp_dir) / "download.zip"
        request = urllib.request.Request(
            source,
            headers={"User-Agent": "GTFS-importer/1.0"},
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response, zip_path.open("wb") as output:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    output.write(chunk)
        except Exception as exc:
            raise RuntimeError(f"Could not download ZIP from URL: {exc}") from exc

        extract_gtfs_txt_files(zip_path, directory)
        files = sorted(directory.rglob("*.txt"))

    if not files:
        raise FileNotFoundError(f"No .txt files found for source: {source}")
    return files


def extract_gtfs_txt_files(zip_path, destination):
    """Extract only .txt files from a ZIP, rejecting paths outside destination."""
    try:
        with zipfile.ZipFile(zip_path) as archive:
            root = destination.resolve()
            txt_members = [
                member for member in archive.infolist()
                if not member.is_dir() and Path(member.filename).suffix.lower() == ".txt"
            ]
            for member in txt_members:
                target = (destination / member.filename).resolve()
                if not target.is_relative_to(root):
                    raise ValueError(f"Unsafe path in ZIP archive: {member.filename}")
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(member) as source_file, target.open("wb") as target_file:
                    while True:
                        chunk = source_file.read(1024 * 1024)
                        if not chunk:
                            break
                        target_file.write(chunk)
    except zipfile.BadZipFile as exc:
        raise ValueError(f"Not a valid ZIP archive: {zip_path}") from exc


def main():
    args = parse_args()

    password = os.environ.get("PGPASSWORD")
    if password is None:
        password = getpass.getpass("PostgreSQL password: ")

    config = {
        "host": args.host,
        "port": args.port,
        "dbname": args.database,
        "user": args.user,
        "password": password,
    }

    try:
        # Prepare source inside a temporary directory; it is removed automatically.
        with tempfile.TemporaryDirectory(prefix="gtfs_import_") as temp_dir:
            files = get_gtfs_files(args.source_type, args.source, temp_dir)
            print(f"Source type: {args.source_type}; found {len(files)} .txt file(s)")

            # 1. Create the database if necessary.
            ensure_database(config)

            # 2. Connect to the target database.
            with psycopg.connect(**config) as conn:
                # 3. Drop and recreate the schema, then create all tables.
                recreate_schema(conn, args.schema)
                create_tables(conn, args.schema)

                # 4. Import each GTFS file using COPY.
                errors = 0

                for file_path in files:
                    try:
                        import_table(conn, args.schema, file_path)
                    except Exception as exc:
                        conn.rollback()
                        errors += 1
                        print(f"ERROR: {file_path.name}: {exc}")

            if errors:
                sys.exit(f"Import finished with {errors} file(s) in error.")

            print("Import completed successfully.")

    except Exception as exc:
        sys.exit(f"Import failed: {exc}")


if __name__ == "__main__":
    main()
