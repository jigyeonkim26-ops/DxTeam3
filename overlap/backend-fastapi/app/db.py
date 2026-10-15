import os
import logging
import ssl
import time

from sqlalchemy import URL, create_engine, event
from sqlalchemy.exc import TimeoutError as SQLAlchemyTimeoutError
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import QueuePool
from fastapi import Request

from app.config import BASE_DIR  # noqa: F401 - importing config loads the project's .env

from . import recommendation_diagnostics as diagnostics

logger = logging.getLogger("uvicorn.error")


class DiagnosticQueuePool(QueuePool):
    """QueuePool with opt-in acquisition wait timing; capacity stays unchanged."""

    def _do_get(self):
        started_at = time.perf_counter()
        outcome = "acquired"
        try:
            return super()._do_get()
        except SQLAlchemyTimeoutError:
            outcome = "timed_out"
            raise
        finally:
            if diagnostics.enabled():
                pool = self
                diagnostics.write_db_event({
                    "event": "pool_wait", "trace_id": diagnostics.trace_id(),
                    "path": diagnostics.current_db_path(),
                    "wait_ms": int((time.perf_counter() - started_at) * 1000),
                    "pool_size": pool.size(), "checked_out": pool.checkedout(),
                    "overflow": pool.overflow(), "outcome": outcome,
                })


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
    poolclass=DiagnosticQueuePool,
    connect_args=connect_args,
)


@event.listens_for(engine, "checkout")
def _record_connection_checkout(_dbapi_connection, connection_record, _connection_proxy):
    connection_record.info["overlap_checkout_started_at"] = time.monotonic()
    connection_record.info["overlap_checkout_path"] = diagnostics.current_db_path() or "unknown"
    connection_record.info["overlap_trace_id"] = diagnostics.trace_id()


@event.listens_for(Session, "after_begin")
def _associate_connection_with_request(session, _transaction, connection):
    connection.info["overlap_checkout_path"] = session.info.get("overlap_request_path", "unknown")


@event.listens_for(engine, "checkin")
def _log_long_connection_lease(_dbapi_connection, connection_record):
    started_at = connection_record.info.pop("overlap_checkout_started_at", None)
    request_path = connection_record.info.pop("overlap_checkout_path", "unknown")
    trace = connection_record.info.pop("overlap_trace_id", None)
    if started_at is None:
        return
    lease_ms = int((time.monotonic() - started_at) * 1000)
    if diagnostics.enabled():
        pool = engine.pool
        diagnostics.write_db_event({
            "event": "connection_lease", "trace_id": trace, "path": request_path, "lease_ms": lease_ms,
            "pool_size": pool.size(), "checked_out": pool.checkedout(), "overflow": pool.overflow(),
        })
    if lease_ms < 2000:
        return
    pool = engine.pool
    logger.warning(
        "database_connection_lease path=%s lease_ms=%d pool_size=%s checked_out=%s overflow=%s",
        request_path,
        lease_ms,
        pool.size() if callable(getattr(pool, "size", None)) else "unknown",
        pool.checkedout() if callable(getattr(pool, "checkedout", None)) else "unknown",
        pool.overflow() if callable(getattr(pool, "overflow", None)) else "unknown",
    )


SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_db(request: Request):
    db = None
    request_scope_started_at = time.monotonic()
    route = getattr(request, "scope", {}).get("route")
    request_path = getattr(route, "path", request.url.path)
    try:
        db = SessionLocal()
        db.info["overlap_request_path"] = request_path
        yield db
    except SQLAlchemyTimeoutError:
        pool = engine.pool
        size = pool.size() if callable(getattr(pool, "size", None)) else "unknown"
        checked_out = pool.checkedout() if callable(getattr(pool, "checkedout", None)) else "unknown"
        overflow = pool.overflow() if callable(getattr(pool, "overflow", None)) else "unknown"
        logger.error(
            "database_pool_timeout path=%s pool_size=%s checked_out=%s overflow=%s",
            request.url.path,
            size,
            checked_out,
            overflow,
        )
        diagnostics.error("database", "pool_timeout")
        diagnostics.set_flag("db_pool_timeout")
        diagnostics.write_db_event({
            "event": "pool_checkout_timeout", "trace_id": diagnostics.trace_id(), "path": request_path,
            "pool_size": size, "checked_out": checked_out, "overflow": overflow,
            "timeout_limit_ms": int(float(getattr(engine.pool, "_timeout", 30)) * 1000),
            "outcome": "timed_out",
        })
        raise
    finally:
        if db is not None:
            db.close()
        scope_ms = int((time.monotonic() - request_scope_started_at) * 1000)
        if scope_ms >= 2000:
            logger.info(
                "database_request_scope_duration path=%s duration_ms=%d",
                request.url.path,
                scope_ms,
            )
        diagnostics.write_db_event({
            "event": "request_scope", "path": request_path, "scope_ms": scope_ms,
            "pool_size": engine.pool.size(), "checked_out": engine.pool.checkedout(),
            "overflow": engine.pool.overflow(), "outcome": "completed",
        })
