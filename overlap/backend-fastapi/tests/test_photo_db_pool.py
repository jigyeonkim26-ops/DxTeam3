import io
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import QueuePool

from app.db import Base
from app import db as db_module
from app.db_models import User
from app.main import create_app
from app.record_models import Place, Record, RecordPhoto
from app.security import hash_password
import app.records as records_api
import app.main as main_api


class SlowBody(io.BytesIO):
    def __init__(self, body, engine, read_delay=0.025):
        super().__init__(body)
        self.engine = engine
        self.read_delay = read_delay
        self.checked_out_during_read = []

    def read(self, size=-1):
        self.checked_out_during_read.append(self.engine.pool.checkedout())
        time.sleep(self.read_delay)
        return super().read(size)


class Storage:
    def __init__(self, engine):
        self.engine = engine
        self.keys = {"records/one.png": b"photo-bytes"}
        self.calls = []
        self.fail = False
        self.download_delay = 0.025
        self.bodies = []

    def download(self, key):
        self.calls.append(key)
        # Acts like another request needing the sole pool connection during
        # storage I/O. It succeeds only after the request session releases it.
        assert self.engine.pool.checkedout() == 0
        with self.engine.connect() as connection:
            assert connection.execute(text("SELECT 1")).scalar_one() == 1
        time.sleep(self.download_delay)
        if self.fail:
            raise HTTPException(502, "photo download failed")
        body = SlowBody(self.keys[key], self.engine)
        self.bodies.append(body)
        return body


@pytest.fixture
def photo_app(tmp_path, monkeypatch):
    db_path = tmp_path / "photo-pool.sqlite"
    engine = create_engine(
        f"sqlite:///{db_path}",
        poolclass=QueuePool,
        pool_size=1,
        max_overflow=0,
        pool_timeout=0.5,
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add_all([
            User(id=1, email="owner@example.test", nickname="owner", gender="female",
                 birth_date=date(1990, 1, 1), password_hash=hash_password("password-123"),
                 profile_image_key="records/one.png"),
            User(id=2, email="visitor@example.test", nickname="visitor", gender="female",
                 birth_date=date(1990, 1, 1), password_hash=hash_password("password-123")),
        ])
        db.add(Place(id=1, provider="manual", external_place_id="35,127", name="test place",
                     address="Seoul", latitude=37.5, longitude=127.0))
        db.add(Record(id=1, author_id=1, place_id=1, content="private", emotion="good", is_private=True))
        db.add(RecordPhoto(id=1, record_id=1, object_key="records/one.png", photo_url=None,
                           original_name="one.png", mime_type="image/png", file_size=11, sort_order=0))
        db.commit()

    api = create_app(use_db_auth=True)
    monkeypatch.setattr(db_module, "engine", engine)
    monkeypatch.setattr(db_module, "SessionLocal", sessionmaker(bind=engine, autoflush=False, expire_on_commit=False))
    storage = Storage(engine)
    checkouts = []
    checkins = []
    lease_started = {}
    lease_durations = []

    def on_checkout(_connection, connection_record, _proxy):
        now = time.monotonic()
        checkouts.append(now)
        lease_started[id(connection_record)] = now

    def on_checkin(_connection, connection_record):
        now = time.monotonic()
        checkins.append(now)
        started = lease_started.pop(id(connection_record), None)
        if started is not None:
            lease_durations.append(now - started)

    event.listen(engine, "checkout", on_checkout)
    event.listen(engine, "checkin", on_checkin)
    monkeypatch.setattr(records_api, "get_object_storage", lambda: storage)
    monkeypatch.setattr(main_api, "get_object_storage", lambda: storage)
    yield api, engine, storage, checkouts, checkins, lease_durations
    engine.dispose()


def _login(client, email):
    response = client.post("/auth/login", json={"email": email, "password": "password-123"})
    assert response.status_code == 200, response.text
    return {"Authorization": "Bearer " + response.json()["access_token"]}


def test_record_and_author_photos_release_connection_before_slow_storage(photo_app):
    api, engine, storage, checkouts, checkins, lease_durations = photo_app
    with TestClient(api) as client:
        headers = _login(client, "owner@example.test")
        photo = client.get("/records/1/photos/1", headers=headers)
        assert photo.status_code == 200
        assert photo.content == b"photo-bytes"
        assert photo.headers["content-type"] == "image/png"
        assert photo.headers["cache-control"] == "private, no-store"
        author = client.get("/records/1/author-photo", headers=headers)
        assert author.status_code == 200
        assert author.content == b"photo-bytes"
        profile = client.get("/auth/me/photo", headers=headers)
        assert profile.status_code == 200
        assert profile.content == b"photo-bytes"
    assert storage.calls == ["records/one.png"] * 3
    assert all(body.checked_out_during_read == [0, 0] for body in storage.bodies)
    assert engine.pool.checkedout() == 0
    assert len(checkouts) == len(checkins)


def test_private_missing_and_storage_failure_photo_paths_release_connection(photo_app):
    api, engine, storage, checkouts, checkins, lease_durations = photo_app
    with TestClient(api) as client:
        visitor_headers = _login(client, "visitor@example.test")
        assert client.get("/records/1/photos/1", headers=visitor_headers).status_code == 404
        assert client.get("/auth/me/photo", headers=visitor_headers).status_code == 404
        owner_headers = _login(client, "owner@example.test")
        assert client.get("/records/1/photos/999", headers=owner_headers).status_code == 404
        assert client.get("/records/999/author-photo", headers=owner_headers).status_code == 404
        storage.fail = True
        failed = client.get("/records/1/photos/1", headers=owner_headers)
        assert failed.status_code == 502
    assert engine.pool.checkedout() == 0
    assert len(checkouts) == len(checkins)


def test_concurrent_photo_reads_with_single_db_connection_and_authentication(photo_app):
    api, engine, storage, checkouts, checkins, lease_durations = photo_app
    with TestClient(api) as client:
        headers = _login(client, "owner@example.test")

    def request_photo(_):
        with TestClient(api) as client:
            response = client.get("/records/1/author-photo", headers=headers)
            return response.status_code, response.content

    with ThreadPoolExecutor(max_workers=6) as executor:
        results = list(executor.map(request_photo, range(12)))
    assert results == [(200, b"photo-bytes")] * 12
    with TestClient(api) as client:
        assert client.get("/auth/me", headers=headers).status_code == 200
    assert len(storage.calls) == 12
    assert engine.pool.checkedout() == 0
    assert len(checkouts) == len(checkins)


def test_slow_storage_is_request_time_not_database_connection_lease(photo_app, caplog):
    api, engine, storage, checkouts, checkins, lease_durations = photo_app
    storage.download_delay = 2.05
    caplog.set_level("INFO", logger="uvicorn.error")
    with TestClient(api) as client:
        headers = _login(client, "owner@example.test")
        response = client.get("/records/1/author-photo", headers=headers)
    assert response.status_code == 200
    # get_db logs dependency/request scope duration independently. Its DB
    # connection was already returned before the delayed storage operation.
    assert "database_request_scope_duration path=/records/1/author-photo" in caplog.text
    assert storage.calls == ["records/one.png"]
    assert engine.pool.checkedout() == 0
    assert len(checkouts) == len(checkins)
    assert max(lease_durations) < storage.download_delay
