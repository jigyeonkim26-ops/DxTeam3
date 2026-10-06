import os
import ssl

from sqlalchemy import URL, create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.config import BASE_DIR  # noqa: F401 - importing config loads the project's .env


def _required_setting(name: str) -> str:
    value = os.getenv(name, "")
    if not value.strip():
        return ""
    return value.strip() if name != "DB_PASSWORD" else value


_required_names = ("DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD")
_settings = {name: _required_setting(name) for name in _required_names}
_missing = [name for name, value in _settings.items() if not value]
if _missing:
    raise RuntimeError("Missing required database environment variables: " + ", ".join(_missing))

try:
    DB_PORT = int(os.getenv("DB_PORT", "3306").strip() or "3306")
except ValueError as exc:
    raise RuntimeError("DB_PORT must be an integer") from exc

DB_SSL = os.getenv("DB_SSL", "false").strip().lower() in {"true", "1", "yes"}
DB_SSL_VERIFY = os.getenv("DB_SSL_VERIFY", "false").strip().lower() in {"true", "1", "yes"}
DB_SSL_CA = os.getenv("DB_SSL_CA", "").strip()

connect_args: dict[str, object] = {"connect_timeout": 10}
if DB_SSL:
    ssl_context = ssl.create_default_context()
    if not DB_SSL_VERIFY:
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE
    elif DB_SSL_CA:
        ssl_context.load_verify_locations(cafile=DB_SSL_CA)
    connect_args["ssl"] = ssl_context

database_url = URL.create(
    "mysql+pymysql",
    username=_settings["DB_USER"],
    password=_settings["DB_PASSWORD"],
    host=_settings["DB_HOST"],
    port=DB_PORT,
    database=_settings["DB_NAME"],
    query={"charset": "utf8mb4"},
)

engine = create_engine(
    database_url,
    pool_pre_ping=True,
    pool_recycle=3600,
    connect_args=connect_args,
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
