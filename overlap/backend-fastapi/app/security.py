"""비밀번호는 Argon2id, 로그인 토큰은 임의의 256비트 값으로 처리합니다."""

import hashlib
import secrets

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

password_hasher = PasswordHasher()
# 존재하지 않는 아이디도 비밀번호 검증 작업을 거치도록 합니다.
_dummy_hash = password_hasher.hash(secrets.token_urlsafe(24))


def hash_password(password: str) -> str:
    return password_hasher.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    try:
        valid = password_hasher.verify(password_hash or _dummy_hash, password)
        return bool(valid and password_hash)
    except (VerificationError, InvalidHashError):
        return False


def new_token() -> str:
    return secrets.token_urlsafe(32)


def token_digest(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
