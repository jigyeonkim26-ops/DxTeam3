import json

import httpx

from .config import KAKAO_REST_API_KEY


def search_places(query: str):
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
        timeout=10.0,
    )

    # 카카오 요청이 실패했다면 오류 표시
    response.raise_for_status()

    # 받은 장소 정보를 사용하기 편한 형태로 정리
    places = []

    for item in response.json()["documents"]:
        places.append({
            "kakao_place_id": item["id"],
            "name": item["place_name"],
            "address": item["road_address_name"] or item["address_name"],
            "latitude": float(item["y"]),
            "longitude": float(item["x"]),
            "place_url": item["place_url"],
        })

    return places


# 이 파일을 직접 실행하면 검색 테스트
if __name__ == "__main__":
    result = search_places("대전 카페")
    print(json.dumps(result, ensure_ascii=False, indent=2))