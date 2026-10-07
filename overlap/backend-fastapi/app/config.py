import os
from pathlib import Path

from dotenv import load_dotenv

# overlap-backend 폴더의 위치를 찾기
BASE_DIR = Path(__file__).resolve().parent.parent

# 해당 폴더에 있는 .env 파일 읽기
load_dotenv(BASE_DIR / ".env")

# 설정에서 카카오 REST API 키 가져오기
KAKAO_REST_API_KEY = os.getenv("KAKAO_REST_API_KEY", "").strip()
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "").strip()
