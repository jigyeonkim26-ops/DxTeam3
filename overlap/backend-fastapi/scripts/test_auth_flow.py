import sys
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from fastapi.testclient import TestClient
from sqlalchemy import delete, select

from app.db import SessionLocal
from app.db_models import User
from app.main import app


def main() -> int:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S%f")
    email = f"test_{stamp}@example.com"
    with SessionLocal() as db:
        if db.scalar(select(User.id).where(User.email == email)) is not None:
            print("생성된 테스트 이메일이 이미 존재합니다. 테스트를 중단합니다.")
            return 1
    password = "Integration-test-123!"
    payload = {
        "email": email,
        "password": password,
        "nickname": "Integration Test",
        "birth_date": "1995-05-17",
        "gender": "female",
        "terms_accepted": True,
    }
    passed = False

    try:
        with TestClient(app) as client:
            registered = client.post("/auth/register", json=payload)
            assert registered.status_code == 201, "registration did not return 201"
            created = registered.json()
            assert created["email"] == email
            assert "password_hash" not in created

            duplicate = client.post("/auth/register", json=payload)
            assert duplicate.status_code == 409, "duplicate registration did not return 409"

            login = client.post(
                "/auth/login",
                json={"email": email, "password": password},
            )
            assert login.status_code == 200, "login did not return 200"
            access_token = login.json().get("access_token")
            assert isinstance(access_token, str) and access_token

            headers = {"Authorization": f"Bearer {access_token}"}
            me = client.get("/auth/me", headers=headers)
            assert me.status_code == 200, "authenticated /auth/me did not return 200"
            assert me.json()["email"] == email
            assert "password_hash" not in me.json()

            logout = client.post("/auth/logout", headers=headers)
            assert logout.status_code == 204, "logout did not return 204"
            after_logout = client.get("/auth/me", headers=headers)
            assert after_logout.status_code == 401, "logged-out token was not rejected"

        passed = True
        print("회원가입/중복가입 409/로그인/내 정보/로그아웃 흐름 성공")
    except Exception as exc:
        print(f"인증 흐름 테스트 실패 ({type(exc).__name__}): {exc}")
    finally:
        try:
            with SessionLocal() as db:
                db.execute(delete(User).where(User.email == email))
                db.commit()
        except Exception as exc:
            passed = False
            print(f"테스트 계정 정리 실패 ({type(exc).__name__}): {exc}")

    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
