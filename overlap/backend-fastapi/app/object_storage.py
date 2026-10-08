"""NCP credentials are read only from this backend's .env, never logged."""
from dataclasses import dataclass
import os
from urllib.parse import quote, urlparse
from uuid import uuid4

import boto3
from botocore.config import Config
from dotenv import dotenv_values
from fastapi import HTTPException

from .config import BASE_DIR


@dataclass(frozen=True)
class UploadedPhoto:
    object_key: str
    photo_url: str


class ObjectStorage:
    def __init__(self):
        settings = dotenv_values(BASE_DIR / ".env")
        names = ("NCP_ACCESS_KEY", "NCP_SECRET_KEY", "NCP_BUCKET_NAME", "NCP_ENDPOINT")
        missing = [name for name in names if not (settings.get(name) or "").strip()]
        if missing:
            raise HTTPException(503, "사진 저장 설정 필요: " + ", ".join(missing))
        self.bucket = settings["NCP_BUCKET_NAME"].strip()
        self.endpoint = settings["NCP_ENDPOINT"].strip().rstrip("/")
        parsed = urlparse(self.endpoint)
        if parsed.scheme != "https" or not parsed.netloc or parsed.query or parsed.username:
            raise HTTPException(503, "NCP_ENDPOINT는 HTTPS Object Storage 주소여야 합니다.")
        ncp_config = Config(
            signature_version="s3v4",
            s3={"addressing_style": "path"},
            request_checksum_calculation="when_required",
            response_checksum_validation="when_required",
            connect_timeout=5,
            read_timeout=20,
            retries={"max_attempts": 2},
        )
        self.client = boto3.client(
            "s3", endpoint_url=os.getenv("NCP_ENDPOINT"),
            region_name="kr-standard",
            aws_access_key_id=os.getenv("NCP_ACCESS_KEY"),
            aws_secret_access_key=os.getenv("NCP_SECRET_KEY"),
            config=ncp_config,
        )

    def upload(self, data: bytes, mime_type: str) -> UploadedPhoto:
        suffix = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}[mime_type]
        key = f"records/{uuid4().hex}.{suffix}"
        url = f"{self.endpoint}/{quote(self.bucket, safe='')}/{quote(key, safe='/')}"
        if len(url) > 500:
            raise HTTPException(503, "Object Storage 주소 길이를 확인해 주세요.")
        try:
            self.client.put_object(Bucket=self.bucket, Key=key, Body=data,
                                   ContentType=mime_type, ACL="private")
        except Exception:
            raise HTTPException(502, "사진 저장에 실패했습니다. 다시 시도해 주세요.") from None
        return UploadedPhoto(key, url)

    def delete(self, key: str):
        self.client.delete_object(Bucket=self.bucket, Key=key)

    def download(self, key: str):
        try:
            return self.client.get_object(Bucket=self.bucket, Key=key)["Body"]
        except Exception:
            raise HTTPException(502, "사진을 불러오지 못했습니다.") from None


def get_object_storage():
    return ObjectStorage()
