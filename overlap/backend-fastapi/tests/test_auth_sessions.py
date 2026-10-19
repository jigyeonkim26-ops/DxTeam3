from datetime import date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool
from sqlalchemy import create_engine

from app.db import Base, get_db
from app.db_models import AuthSession, User
from app.main import create_app
from app.security import hash_password, token_digest
from app.service import MemoryService


@pytest.fixture
def db_auth_client():
    engine = create_engine(
        "sqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False}
    )
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add(User(
            id=1, email="auth@example.test", nickname="인증 테스트", gender="female",
            birth_date=date(1990, 1, 1), password_hash=hash_password("password-123"),
        ))
        db.commit()

    def session():
        with Session(engine) as db:
            yield db

    def make_client():
        api = create_app(use_db_auth=True, service=MemoryService())
        api.dependency_overrides[get_db] = session
        return TestClient(api)

    client = make_client()
    try:
        yield client, make_client, engine
    finally:
        client.close()
        engine.dispose()


def test_refresh_is_hashed_rotated_and_survives_service_restart(db_auth_client):
    client, make_client, engine = db_auth_client
    login = client.post("/auth/login", json={
        "email": "auth@example.test", "password": "password-123",
    })
    assert login.status_code == 200
    original = login.json()
    assert original["expires_in"] == 3600
    assert original["refresh_expires_in"] == 30 * 24 * 60 * 60

    with Session(engine) as db:
        row = db.scalar(select(AuthSession))
        assert row is not None
        assert row.refresh_token_hash == token_digest(original["refresh_token"])
        assert row.access_token_hash == token_digest(original["access_token"])
        assert original["refresh_token"] not in row.refresh_token_hash

    # A fresh app/service instance can authenticate from the persistent DB row.
    restarted = make_client()
    headers = {"Authorization": f"Bearer {original['access_token']}"}
    assert restarted.get("/auth/me", headers=headers).status_code == 200
    rotated_response = restarted.post("/auth/refresh", json={
        "refresh_token": original["refresh_token"],
    })
    assert rotated_response.status_code == 200
    rotated = rotated_response.json()
    assert rotated["session_id"] == original["session_id"]
    assert rotated["refresh_token"] != original["refresh_token"]
    assert restarted.get("/auth/me", headers=headers).status_code == 401
    assert restarted.post("/auth/refresh", json={
        "refresh_token": original["refresh_token"],
    }).status_code == 401
    assert restarted.get(
        "/auth/me", headers={"Authorization": f"Bearer {rotated['access_token']}"}
    ).status_code == 200
    restarted.close()


def test_refresh_logout_revokes_session_without_access_token(db_auth_client):
    client, _, engine = db_auth_client
    issued = client.post("/auth/login", json={
        "email": "auth@example.test", "password": "password-123",
    }).json()
    response = client.post("/auth/logout", json={"refresh_token": issued["refresh_token"]})
    assert response.status_code == 204
    assert client.post("/auth/refresh", json={
        "refresh_token": issued["refresh_token"],
    }).status_code == 401
    with Session(engine) as db:
        row = db.scalar(select(AuthSession))
        assert row is not None and row.revoked_at is not None


def test_expired_access_token_can_be_recovered_from_live_refresh_token(db_auth_client):
    client, _, engine = db_auth_client
    issued = client.post("/auth/login", json={
        "email": "auth@example.test", "password": "password-123",
    }).json()
    with Session(engine) as db:
        row = db.scalar(select(AuthSession))
        assert row is not None
        row.access_expires_at = datetime.utcnow() - timedelta(seconds=1)
        db.commit()

    assert client.get("/auth/me", headers={
        "Authorization": f"Bearer {issued['access_token']}"
    }).status_code == 401
    recovered = client.post("/auth/refresh", json={
        "refresh_token": issued["refresh_token"],
    })
    assert recovered.status_code == 200
    assert client.get("/auth/me", headers={
        "Authorization": f"Bearer {recovered.json()['access_token']}"
    }).status_code == 200
