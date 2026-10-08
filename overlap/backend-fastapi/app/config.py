import os
from pathlib import Path

from dotenv import load_dotenv

# overlap-backend 폴더의 위치를 찾기
BASE_DIR = Path(__file__).resolve().parent.parent

# 해당 폴더에 있는 .env 파일 읽기
load_dotenv(BASE_DIR / ".env")

# 설정에서 카카오 REST API 키 가져오기
KAKAO_REST_API_KEY = os.getenv("KAKAO_REST_API_KEY", "").strip()
LLM_PROVIDER = os.getenv("LLM_PROVIDER", "openrouter").strip().lower()
SEARCH_PROVIDER = os.getenv("SEARCH_PROVIDER", "tavily").strip().lower()
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "").strip()
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "openrouter/free").strip()
TAVILY_API_KEY = os.getenv("TAVILY_API_KEY", "").strip()
