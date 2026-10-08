import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from sqlalchemy import text

try:
    from app.db import DB_PORT, DB_SSL, DB_SSL_VERIFY, _settings, engine
except Exception as exc:
    print(f"DB 연결 실패 ({type(exc).__name__}): {exc}")
    raise SystemExit(1)


def _safe_message(exc: Exception) -> str:
    message = str(exc)
    password = _settings.get("DB_PASSWORD", "")
    if password:
        message = message.replace(password, "[REDACTED]")
    return message


def main() -> int:
    print(
        "DB 설정: "
        f"host={_settings['DB_HOST']}, port={DB_PORT}, db={_settings['DB_NAME']}, "
        f"user={_settings['DB_USER']}, SSL={DB_SSL}, SSL 검증={DB_SSL_VERIFY}"
    )
    try:
        with engine.connect() as connection:
            one = connection.execute(text("SELECT 1")).scalar_one()
            version = connection.execute(text("SELECT VERSION()")).scalar_one()
            database = connection.execute(text("SELECT DATABASE()")).scalar_one()
            ssl_row = connection.execute(text("SHOW STATUS LIKE 'Ssl_cipher'")).first()
            cipher = ssl_row[1] if ssl_row else ""
            tables = connection.execute(text("SHOW TABLES")).scalars().all()

        print(f"SELECT 1: {one}")
        print(f"SELECT VERSION(): {version}")
        print(f"SELECT DATABASE(): {database}")
        print(f"SHOW STATUS LIKE 'Ssl_cipher': {cipher if cipher else 'SSL 미적용'}")
        print(f"SHOW TABLES: {tables}")
        print("DB 연결 성공")
        return 0
    except Exception as exc:
        message = _safe_message(exc)
        print(f"DB 연결 실패 ({type(exc).__name__}): {message}")
        lowered = message.lower()
        if "1045" in message:
            print("힌트: 계정/비밀번호 또는 접속 허용 호스트를 확인하세요.")
        elif "2003" in message or "timeout" in lowered or "timed out" in lowered:
            print("힌트: 호스트, 포트, 방화벽, 네트워크를 확인하세요.")
        elif "ssl" in lowered or "certificate" in lowered or "tls" in lowered:
            print("힌트: DB_SSL_VERIFY=false로 시도해 보세요.")
        elif "cryptography" in lowered:
            print("힌트: pip install cryptography")
        return 1
    finally:
        engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
