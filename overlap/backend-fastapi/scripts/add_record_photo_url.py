"""Add one nullable column, preserving all existing rows and tables."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from sqlalchemy import inspect, text
from app.db import engine


def main():
    try:
        columns = {c["name"] for c in inspect(engine).get_columns("record_photos")}
        if "photo_url" in columns:
            print("record_photos.photo_url already exists; no changes")
            return
        with engine.begin() as connection:
            connection.execute(text("ALTER TABLE record_photos ADD COLUMN photo_url VARCHAR(500) NULL AFTER object_key"))
        print("Added record_photos.photo_url; existing rows and object_key preserved")
    except Exception as error:
        print("Migration failed:", type(error).__name__)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
