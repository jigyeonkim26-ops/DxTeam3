from types import SimpleNamespace

import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.exc import TimeoutError as SQLAlchemyTimeoutError
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import QueuePool

from app import db


def test_db_dependency_closes_connection_after_fastapi_request(monkeypatch):
    test_engine = create_engine("sqlite://", poolclass=QueuePool, pool_size=1, max_overflow=0)
    monkeypatch.setattr(db, "engine", test_engine)
    monkeypatch.setattr(db, "SessionLocal", sessionmaker(bind=test_engine))
    api = FastAPI()

    @api.get("/db-probe")
    def db_probe(session=Depends(db.get_db)):
        return {"result": session.execute(text("SELECT 1")).scalar_one()}

    with TestClient(api) as client:
        response = client.get("/db-probe")

    assert response.status_code == 200
    assert response.json() == {"result": 1}
    assert test_engine.pool.checkedout() == 0
    test_engine.dispose()


def test_db_pool_timeout_logs_request_path_and_pool_counts(monkeypatch, caplog):
    test_engine = create_engine(
        "sqlite://",
        poolclass=QueuePool,
        pool_size=1,
        max_overflow=0,
        pool_timeout=0.01,
    )
    held_connection = test_engine.connect()
    monkeypatch.setattr(db, "engine", test_engine)
    monkeypatch.setattr(db, "SessionLocal", sessionmaker(bind=test_engine))
    request = SimpleNamespace(url=SimpleNamespace(path="/ai/recommendations"))
    caplog.set_level("ERROR", logger="uvicorn.error")

    dependency = db.get_db(request)
    session = next(dependency)
    with pytest.raises(SQLAlchemyTimeoutError) as raised:
        session.execute(text("SELECT 1"))

    with pytest.raises(SQLAlchemyTimeoutError):
        dependency.throw(raised.value)

    assert "database_pool_timeout path=/ai/recommendations" in caplog.text
    assert "pool_size=1 checked_out=1 overflow=0" in caplog.text
    held_connection.close()
    test_engine.dispose()
