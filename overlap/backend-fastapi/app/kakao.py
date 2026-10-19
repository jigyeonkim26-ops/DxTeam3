import json
import logging

import httpx

from .config import KAKAO_REST_API_KEY
from . import recommendation_diagnostics as diagnostics

logger = logging.getLogger("uvicorn.error")


def search_places(query: str, *, timeout: float = 10.0):
    if not KAKAO_REST_API_KEY:
        raise RuntimeError(".env에서 카카오 REST API 키를 확인해 주세요.")

    # 카카오에 검색어를 보내고 결과 받기
    response = httpx.get(
        "https://dapi.kakao.com/v2/local/search/keyword.json",
        headers={
            "Authorization": f"KakaoAK {KAKAO_REST_API_KEY}"
        },
        params={
            "query": query,
            "size": 5,
        },
        timeout=timeout,
    )

    # Read only counts and status for diagnostics; never log the search term or payload.
    if isinstance(response.status_code, int):
        diagnostics.add_count(f"kakao_http_status_{response.status_code}")
    if not response.is_success:
        logger.warning("Kakao Local response http_status=%d raw_result_count=unavailable", response.status_code)
        response.raise_for_status()
    payload = response.json()
    documents = payload.get("documents")
    if not isinstance(documents, list):
        raise ValueError("Invalid Kakao Local response")
    diagnostics.add_count("kakao_successful_responses")
    diagnostics.add_count("kakao_response_documents", len(documents))
    logger.info("Kakao Local response http_status=%d raw_result_count=%d", response.status_code, len(documents))

    # 받은 장소 정보를 사용하기 편한 형태로 정리
    places = []

    for item in documents:
        places.append({
            "kakao_place_id": item["id"],
            "name": item["place_name"],
            "address": item["road_address_name"] or item["address_name"],
            "latitude": float(item["y"]),
            "longitude": float(item["x"]),
            "place_url": item["place_url"],
            "category_group_code": item.get("category_group_code") or None,
            "category_name": item.get("category_name", ""),
            "phone": item.get("phone") or None,
        })

    return places


# 이 파일을 직접 실행하면 검색 테스트
if __name__ == "__main__":
    result = search_places("대전 카페")
    print(json.dumps(result, ensure_ascii=False, indent=2))
