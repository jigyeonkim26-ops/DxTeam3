"""Register the 30 demo records through the app's own API (private records).

Photos: put files in demo_data/photos named after the place, e.g.
    영광오리탕.jpg, 영광오리탕_2.jpg, 밀탑 상무점.png
(JPEG/PNG/WebP, 10MB or less each, up to 5 per place).

Usage (from overlap/backend-fastapi, with the server running):
    .\\.venv\\Scripts\\python.exe ..\\demo_data\\seed_demo_records.py --dry-run
    .\\.venv\\Scripts\\python.exe ..\\demo_data\\seed_demo_records.py --email demo@example.com

The password is read from the DEMO_PASSWORD environment variable or asked
interactively; it is never stored. Places already registered by an earlier
run are skipped (see .seed_state.json).
"""
from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import sys
import time
from pathlib import Path

import httpx

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "backend-fastapi"))
from app.config import KAKAO_REST_API_KEY  # noqa: E402

EMOTIONS = {"최고": "excellent", "좋아": "good", "괜찮아": "okay"}
PHOTO_TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp"}
MAX_PHOTO_BYTES = 10 * 1024 * 1024

# (장소명, 카카오 장소 ID, 감정, 기록 내용)
ROWS = [
    ("영광오리탕", "11892167", "최고", "유동 오리탕 거리에서 먹은 오리탕.. 들깨가루 듬뿍이라 국물이 걸쭉하고 고소함ㅠ 오리탕 원래 잘 안 먹었는데 여기서 입문함"),
    ("현대오리탕", "18612182", "최고", "오리탕 또 먹으러 옴ㅋㅋ 들깨 국물 진하고 오리고기 엄청 부드러움. 국물 계속 떠먹게 되는 맛"),
    ("영양오리탕", "8490524", "최고", "비 오는 날 생각나서 간 오리탕집. 국물 걸쭉하고 고소하고 오리고기 쫄깃해서 밥까지 말아먹음"),
    ("빛고을 애호박찌개", "1239192934", "최고", "광주 오면 애호박찌개는 꼭 먹어야 됨.. 칼칼하고 진한 국물에 돼지고기 넉넉하게 들어가 있어서 밥 두 공기 순삭"),
    ("황솔촌 충장점", "21318122", "최고", "고기 먹으러 갔는데 애호박찌개가 메인이었음ㅋㅋ 애호박 큼직하고 국물 칼칼해서 계속 생각남"),
    ("황솔촌 수완점", "26792051", "최고", "애호박찌개 때문에 또 감. 칼칼하고 진한 국물이라 밥 한 공기 금방 비움"),
    ("육전미가", "1949368121", "최고", "한우 얇게 펴서 바로 부쳐주는 육전.. 따끈할 때 먹으니까 진짜 부드럽고 고소함"),
    ("무등골전집", "21243751", "최고", "육전 노릇노릇하게 잘 부쳐져서 나옴. 부드럽고 촉촉해서 간장 양념이랑 찰떡"),
    ("송림육전곰탕", "13091335", "최고", "갓 부친 육전 부드럽고 고소함ㅠ 육전은 무조건 따뜻할 때 먹어야 됨"),
    ("이조송정떡갈비", "27377975", "최고", "송정 떡갈비 거리에서 먹은 떡갈비..... 진짜 맛있음. 숯불향 배어있고 다진고기 원래 잘 안 먹는데 촉촉하고 달달해서 계속 먹음..."),
    ("동성떡갈비", "7839723", "최고", "떡갈비 두툼하고 육즙 가득함.. 숯불에 구워서 고기 향 진하게 남"),
    ("새송정떡갈비", "7935684", "최고", "송정역 근처라 기차 타기 전에 들른 떡갈비집. 숯불 떡갈비 부드럽고 촉촉해서 여행 시작 기분 좋게 함"),
    ("밀탑 상무점", "366915375", "최고", "상무지구 카페에서 크로플 먹음. 겉은 바삭하고 속은 쫄깃해서 손이 계속 감"),
    ("사월의파랑", "1602056864", "최고", "동명동 갔다가 들른 카페. 크로플 버터향 진하고 바삭하게 나와서 따뜻할 때 먹으니까 최고"),
    ("노담크로플", "1429386716", "좋아", "크로플 전문점이라 종류 많음. 플레인 크로플 바삭하고 담백해서 무난하게 맛있음"),
    ("아우스밀", "908861159", "최고", "휘낭시에 종류별로 다 먹어봄ㅋㅋ 겉은 바삭 속은 촉촉하고 버터향 진함"),
    ("자모크", "890495687", "최고", "상무지구 디저트 카페. 갓 구운 휘낭시에 촉촉하고 버터향 대박"),
    ("무난", "1552039918", "좋아", "조용한 디저트 카페에서 휘낭시에 먹음. 겉 바삭하고 많이 안 달아서 좋았음"),
    ("노군꼬치 광주상무점", "1757975940", "최고", "퇴근하고 들른 이자카야. 숯불에 구운 꼬치 불향 진하고 짭조름해서 술이 술술 들어감"),
    ("토리신 상무점", "24613011", "최고", "야키토리 꼬치 부위별로 시켜봄. 숯불 꼬치 촉촉하고 쫄깃해서 하나도 안 남김"),
    ("훈613 쌍촌본점", "1533625861", "좋아", "분위기 좋은 이자카야. 꼬치 모둠 시켰는데 담백하고 불향 좋음"),
    ("오카츠", "1498075059", "좋아", "등심 돈까스 두툼하고 바삭함. 육즙도 많아서 만족"),
    ("아프리카앤소울", "16808512", "괜찮아", "돈까스랑 우동 같이 먹을 수 있어서 좋음. 돈까스 바삭함"),
    ("돈카츠아라타", "1684390518", "좋아", "동명동 돈카츠집. 안심 돈카츠 부드럽고 튀김옷 바삭바삭"),
    ("마네키 동명본점", "1863998163", "좋아", "우동 면발 쫄깃하고 가쓰오 국물 진함. 날 추울 때 생각날 듯"),
    ("마이짬뽕", "1369078903", "좋아", "짬뽕 국물 불향 제대로고 칼칼함. 해산물도 넉넉하게 들어있음"),
    ("춘리마라탕", "1850198171", "괜찮아", "마라탕 1단계로 먹었는데 얼얼하고 국물 고소함. 맵찔이도 괜찮았음"),
    ("빈도", "1789124035", "좋아", "에그타르트 맛집 카페. 페이스트리 바삭하고 커스터드 부드러움"),
    ("디어문", "981938511", "좋아", "조용한 카페에서 크로플 먹음. 바삭하고 담백해서 부담 없음"),
    ("취화선", "15606674", "좋아", "숯불에 돌려 굽는 양꼬치. 쯔란 찍어 먹으면 고소하고 담백함"),
]


def compact(value: str) -> str:
    return re.sub(r"\s+", "", value).casefold()


def photo_files(photos_dir: Path, place_name: str) -> list[Path]:
    """Files named after the place, optionally numbered (이름_2.jpg, 이름 (2).jpg)."""
    target = compact(place_name)
    matches = []
    for path in sorted(photos_dir.iterdir()) if photos_dir.is_dir() else []:
        if not path.is_file():
            continue
        stem = re.sub(r"(?:[_\-]\d+|\(\d+\))$", "", compact(path.stem))
        if stem == target:
            matches.append(path)
    return matches


def kakao_place(name: str, place_id: str) -> dict:
    """Fetch the place by its exact Kakao ID (keyword search, matched by ID)."""
    for query in (name, f"광주 {name}"):
        response = httpx.get(
            "https://dapi.kakao.com/v2/local/search/keyword.json",
            headers={"Authorization": f"KakaoAK {KAKAO_REST_API_KEY}"},
            params={"query": query, "size": 15}, timeout=8,
        )
        response.raise_for_status()
        for document in response.json()["documents"]:
            if document["id"] == place_id:
                return document
    raise LookupError(f"카카오에서 장소를 찾지 못했습니다: {name} ({place_id})")


def load_state(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError):
        return {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", default="http://127.0.0.1:8002")
    parser.add_argument("--email", default=os.getenv("DEMO_EMAIL"))
    parser.add_argument("--photos-dir", type=Path, default=HERE / "photos")
    parser.add_argument("--dry-run", action="store_true", help="장소·사진만 확인하고 등록하지 않음")
    parser.add_argument("--start", type=int, default=1,
                        help="이 번호부터 처리 (예: 1~10번을 이미 등록했다면 --start 11)")
    args = parser.parse_args()
    if not 1 <= args.start <= len(ROWS):
        print(f"--start는 1~{len(ROWS)} 사이로 지정해 주세요.")
        return 1
    rows = ROWS[args.start - 1:]
    print(f"{args.start}번부터 {len(ROWS)}번까지 {len(rows)}건을 처리합니다.\n")

    # 1) Check every place and photo before touching the server.
    plan, problems = [], []
    for number, (name, place_id, emotion, content) in enumerate(rows, start=args.start):
        photos = photo_files(args.photos_dir, name)
        bad = [p.name for p in photos if p.suffix.lower() not in PHOTO_TYPES or p.stat().st_size > MAX_PHOTO_BYTES]
        try:
            place = kakao_place(name, place_id)
        except (LookupError, httpx.HTTPError) as error:
            problems.append(f"[장소] {error}")
            continue
        if not photos:
            problems.append(f"[사진 없음] {name}")
        elif bad:
            problems.append(f"[사진 형식/용량] {name}: {', '.join(bad)} (JPEG·PNG·WebP, 10MB 이하)")
        elif len(photos) > 5:
            problems.append(f"[사진 5장 초과] {name}: {len(photos)}장")
        plan.append((name, place, emotion, content, photos))
        print(f"{'OK ' if photos else '-- '} {number:>2}. {name} | {place.get('road_address_name') or place['address_name']} | 사진 {len(photos)}장")

    if problems:
        print("\n확인이 필요한 항목:")
        for problem in problems:
            print("  " + problem)
    if args.dry_run:
        print(f"\n[dry-run] 등록 가능 {len(plan) - sum(1 for p in problems if p.startswith('[사진'))}/{len(rows)}건. 실제 등록은 하지 않았습니다.")
        return 0
    if problems:
        print("\n위 항목을 해결한 뒤 다시 실행해 주세요. 아무것도 등록하지 않았습니다.")
        return 1

    # 2) Log in as the demo account.
    if not args.email:
        args.email = input("데모 계정 이메일: ").strip()
    password = os.getenv("DEMO_PASSWORD") or getpass.getpass("데모 계정 비밀번호: ")
    client = httpx.Client(base_url=args.base_url, timeout=60)
    login = client.post("/auth/login", json={"email": args.email, "password": password})
    if login.status_code != 200:
        print(f"로그인 실패 (HTTP {login.status_code}): {login.text[:200]}")
        return 1
    client.headers["Authorization"] = f"Bearer {login.json()['access_token']}"

    state_path = HERE / ".seed_state.json"
    state = load_state(state_path)
    done = set(state.get(f"{args.base_url}|{args.email}", []))

    # 3) Register oldest-first so the feed shows them in list order.
    created = 0
    for name, place, emotion, content, photos in plan:
        if place["id"] in done:
            print(f"건너뜀(이미 등록) {name}")
            continue
        payload = {
            "place": {
                "kakao_place_id": place["id"],
                "name": place["place_name"],
                "address": place.get("road_address_name") or place["address_name"],
                "latitude": float(place["y"]),
                "longitude": float(place["x"]),
            },
            "emotion": EMOTIONS[emotion],
            "content": content,
            "is_private": True,
            "group_ids": [],
        }
        files = [("photos", (p.name, p.read_bytes(), PHOTO_TYPES[p.suffix.lower()])) for p in photos]
        response = client.post("/records", data={"data": json.dumps(payload, ensure_ascii=False)}, files=files)
        if response.status_code != 201:
            print(f"실패 {name} (HTTP {response.status_code}): {response.text[:200]}")
            print("여기서 중단합니다. 문제를 해결한 뒤 다시 실행하면 등록된 장소는 건너뜁니다.")
            return 1
        done.add(place["id"])
        state[f"{args.base_url}|{args.email}"] = sorted(done)
        state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
        created += 1
        print(f"등록 {name} ({created})")
        time.sleep(1.1)  # distinct created_at seconds keep the feed order stable

    print(f"\n완료: 새로 등록 {created}건 ({args.start}~{len(ROWS)}번 중 스크립트로 등록된 건 {len(done & {p[1]['id'] for p in plan})}/{len(rows)}건)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
