import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from sqlalchemy import text

from app.db import engine


def main() -> int:
    try:
        with engine.connect() as connection:
            for table, query in (
                ("users", "SHOW CREATE TABLE users"),
                ("refresh_tokens", "SHOW CREATE TABLE refresh_tokens"),
            ):
                row = connection.execute(text(query)).one_or_none()
                print(f"SHOW CREATE TABLE {table}:")
                print(row[1] if row else "table does not exist")

            user_count = connection.execute(
                text("SELECT COUNT(*) FROM users")
            ).scalar_one()
            print(f"SELECT COUNT(*) FROM users: {user_count}")
        return 0
    except Exception as exc:
        print("Schema inspection failed ({}): {}".format(type(exc).__name__, exc))
        return 1
    finally:
        engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
