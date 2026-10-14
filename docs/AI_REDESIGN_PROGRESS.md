# OVERLAP AI 재설계 진행 상황

## 1단계: 기록별 취향 맥락 분석 기반

### 적용 범위

- 구현 범위는 기록별 선호 분석 모듈과 독립 단위 테스트다.
- 기존 `GET /ai/recommendations` 라우트, legacy 키워드 추출, Tavily/Kakao 파이프라인, 순위화/fallback, 캐시, 응답 DTO, Flutter 동작은 연결하거나 변경하지 않았다.
- 테스트는 OpenRouter 응답을 mock 처리했다. 실제 계정/외부 API 호출은 하지 않았다.
- DB 스키마와 데이터는 변경하지 않았다.

### 현재 구조에서 확인된 한계

현재 adapter는 `Record`와 `Place`에서 기록 ID, 장소 ID/이름/주소/좌표, 본문, 감정 코드를 읽는다. 그러나 `Place` 모델에는 저장된 Kakao category 필드가 없고 장소 유형도 없다. 따라서 기존 recommendation DTO만으로는 **저장된 Kakao 업종을 우선 사용**할 수 없다. 이 단계에서 DB 컬럼이나 Kakao 호출을 추가하지 않고, 새 분석 서비스가 선택적 `RecordPlaceMetadata`로 Kakao category 또는 신뢰된 place type을 받을 수 있게 했다. 현재 caller는 이를 공급하지 않으므로 기본 동작은 명확한 장소명 힌트, 다음으로 OpenRouter 분석이며 불명확하면 `unknown`이다.

기존 키워드 추출은 여러 기록을 최대 5개의 일반 키워드로 뭉치기 때문에 `장소 유형 → 좋아한 대상 → 특징` 관계, 어느 기록에서 나온 취향인지, 취향의 직접 근거를 보존하지 않는다. 기존 감정은 코드로 전달되지만 강도로 쓰이지 않고, 기존 키워드 fallback은 빈도 기반이라 대상과 장소 분야 간 관계를 복원하지 못한다.

### 신규 데이터 모델과 서비스

- `RecordPreferenceAnalysis`: 기록 ID/장소명, 장소 유형·표기·유형 근거, 관련 분야, 원 감정 코드와 강도, 기록별 facet 목록, 근거 상태.
- `PreferenceFacet`: 제한된 대상 유형(menu/drink/food/ambience/space/activity/scenery/service/facility/other), 원문에 실제 등장하는 대상 표현, 특징 표현 목록, 연관 분야, liked/disliked/neutral 극성, 원문 인용 근거, 0~1 신뢰도.
- `RecordPlaceMetadata`: Kakao category 또는 신뢰된 장소 유형을 전달하는 선택 입력. 현재 DB/adapter에는 해당 값이 없어 아직 생산자 연결은 없다.
- `RecordPreferenceAnalysisService.analyze(records, place_metadata=None, category="all")`: 최대 30개 최신 입력 기록, 본문 최대 500자/기록, 개인정보처럼 보이는 전화번호·이메일·URL 제거, strict JSON Schema OpenRouter 분석, 원문 근거 검증, 분야 범위 필터를 제공한다.

장소 유형은 선택적 신뢰 메타데이터를 우선 적용하고, 메타데이터가 없으면 명확한 장소명 규칙을 사용한다. 둘 다 불명확하면 모델 유형도 원문 근거가 있는 경우에만 인정한다. 구체적인 메뉴/특징은 `target_text`, `features`, `evidence`가 입력 원문과 일치해야 살아남는다. 모델 오류나 설정 누락 시 임의 키워드 fallback은 하지 않는다. 오류는 안전한 빈 facet과 `unavailable` 상태를 반환한다. 기록의 감정 강도는 모델 출력이 아니라 감정 코드에서 계산하며, 부정/중립 기록을 긍정 취향으로 바꾸지 않는다.

분야 선택은 분석 응답에서만 수행한다. `bar`/`food`는 술집 기록의 겹침을 허용하지만, `cafe`, `nature`, `activity` 간의 취향 전이는 하지 않는다. `all`은 각 분야 맥락을 보존한 전체 결과다. 이번 단계에서는 API query parameter로 `category`를 추가하지 않았다.

### 설계안과 실제 코드의 차이 및 충돌 결정

1. 설계안 1단계에는 `category` API 파라미터가 포함되어 있지만, 이번 요청은 기존 추천 API와 추천 결과를 그대로 두고 새 분석 모듈만 구현하도록 제한한다. 따라서 category 지원은 모듈 메서드의 필터로만 제공했다. API 연결은 후속 단계에서 별도 회귀 검증 후 해야 한다.
2. 설계안은 DB/Kakao category 우선을 제안하지만 실제 `Place` ORM/adapter에는 category 컬럼이나 Kakao category 응답이 없다. DB 변경 및 새 Kakao 호출은 범위 밖이므로 선택 메타데이터만 도입했다. 실제 우선 활용은 caller가 trusted metadata를 전달하도록 확장해야 완성된다.
3. 설계안은 Record/Place 모델의 기존 필드를 확인한 뒤 우선 DTO부터 도입하라고 한다. 새 `RecordPreferenceAnalysisService`는 기존 `RecommendationRecord`를 입력으로 읽으며, 기존 adapter 및 API 의존성 그래프에 연결하지 않았다.
4. 설계안은 감정 범주를 예시 JSON에서 단순히 보였지만, 이번 구현은 현재 adapter의 모든 감정 코드에 수치 강도를 부여한다. legacy 추천용 adapter는 여전히 positive 기록만 조회하므로, 새 모듈은 별도 caller가 neutral/negative 기록을 넘기면 polarity 보존 분석도 가능하다.

### 수정 파일

- 추가: `overlap/backend-fastapi/app/record_preference_analysis.py`
- 추가: `overlap/backend-fastapi/tests/test_record_preference_analysis.py`
- 추가: `docs/AI_REDESIGN_PROGRESS.md`

### 테스트 결과

다음 명령으로 새 모듈과 기존 추천 경로의 직접 관련 회귀 테스트를 실행했다.

```text
python -m pytest -p no:cacheprovider \
  tests/test_record_preference_analysis.py \
  tests/test_recommendation_record_adapter.py \
  tests/test_ai_recommendations.py \
  tests/test_openrouter_structured_output_and_fallback.py -q
```

결과: **43 passed**, 경고 1건(설치된 Starlette의 `httpx` 테스트 클라이언트 deprecation). 테스트 API 요청은 mock이며 실제 OpenRouter 호출은 없다.

신규 테스트는 이자카야의 유자하이볼/꼬치 분리, 카페의 조용함/넓음 맥락, 넓다는 말에서 주차장 취향을 만들지 않는 검증, 야구장·자연 분야, 혼합 기록 분야 필터, 감정 강도/극성, 기록에 없는 메뉴 차단, unknown 장소, trusted Kakao category 우선, 입력 길이·건수 예산, 개인정보형 문자열 제거, malformed 응답 및 API 실패 처리 등을 다룬다.

### 다음 단계 연결점

후속 통합 시 `RecordRecommendationAdapter.list_positive_records`가 반환한 `RecommendationRecord`를 `RecordPreferenceAnalysisService.analyze`에 전달할 수 있다. Kakao category 우선순위를 실제로 사용하려면 먼저 기존 DB/기록 구조에서 category의 신뢰 가능한 원천을 확인하거나, 새 별도 read-only Kakao metadata 조회를 설계해야 한다. 조회를 추가할 경우 요청 예산/timeout과 추천 전체 실패 여부를 합의하고 테스트해야 한다.

예시 호출(현재는 독립 내부 모듈 호출이며 public API가 아님):

```python
analysis = RecordPreferenceAnalysisService().analyze(
    records,
    place_metadata={record_id: RecordPlaceMetadata(kakao_category="카페")},
    category="cafe",
)
```

다음 단계 전에 검토할 점: 카테고리 매핑표의 범위, Kakao category 신뢰/갱신 경로, 부정 기록을 추천 선호에서 어떻게 활용할지, 민감정보 제거 규칙, 최신 30건 제한과 기록별 500자 제한, OpenRouter JSON Schema provider 지원 여부를 실제 설정에서 검증해야 한다.

## Git / 변경 보호

작업 시작 당시 브랜치는 `feature/fullstack-ujin`이었다. 기존 미커밋 변경, 삭제 상태의 `.env.example`, Excel 파일 및 앞선 분석 문서를 보존했다. 이 작업으로 commit, push, merge, branch 변경, DB 스키마 변경은 하지 않았다.

## 2단계: Kakao 후보 탐색 및 Tavily 특징 근거

### 구현 범위

- `PlaceCandidateSearchService`를 새 모듈로 추가했다. 기존 `GET /ai/recommendations`에는 연결하지 않았다.
- Flutter/UI, DB 스키마·데이터, 기존 AI 추천 DTO/순위화/세션/이미지 흐름은 바꾸지 않았다.
- 기존 `kakao.search_places()` 내부 결과에 `category_group_code` 필드만 추가했다. 기존 결과 키(`kakao_place_id`, `name`, `address`, 좌표, `category_name`, `place_url`)는 그대로 유지한다. 외부 지도/장소 API 응답 형식에는 변경이 없다.
- 실제 외부 Kakao/Tavily 호출은 하지 않았다. 관련 테스트는 모킹했다.

### Kakao 원본 응답과 내부 매핑

Kakao Local keyword API `documents[]`의 필드를 내부 후보 DTO로 다음처럼 변환한다.

| Kakao 원본 | 내부 `KakaoPlaceCandidate` | 기존 helper |
|---|---|---|
| `id` | `kakao_place_id` | `kakao_place_id` |
| `place_name` | `place_name` | `name` |
| `road_address_name` 또는 `address_name` | `address` | `address` |
| `y` | `latitude` | `latitude` |
| `x` | `longitude` | `longitude` |
| `category_group_code` | `category_group_code` | 새 선택 필드로 전달 |
| `category_name` | `category_name` | `category_name` |
| `place_url` | `place_url` | `place_url` |

기존 helper 형식과 raw Kakao 형식을 모두 `KakaoPlaceCandidate.from_kakao_result()`에서 받아 DB migration 없이 쓸 수 있다. 누락된 category는 `None`으로 남기며, 유효하지 않은 ID·좌표·필수 장소 필드는 후보 생성 단계에서 거른다.

### 분야별 분류 정책

`KakaoCategoryClassifier`는 Kakao의 실제 `category_group_code`, 계층형 `category_name`, Kakao 장소명을 이용한다. 1단계에서 LLM이 추정한 `place_type`은 Kakao 실카테고리 근거로 간주하지 않는다.

- `CE7` 또는 카페 세부 category → `cafe`
- `FD6` → 기본 `food`; 세부 경로에 술집·이자카야·호프·포차·펍 등이 있으면 `bar`와 `food`를 함께 부여
- 일반 `FD6`만으로 `bar`를 단정하지 않고 `verification_required`로 둠
- `AT4`에 공원·산책로·수목원·전망대 같은 세부 category가 확인되면 `nature`; 넓은 관광명소 코드만 있으면 검증 필요
- `CT1`에 경기장·전시장·공연장·문화체험 같은 구체 분류가 있으면 `activity`; 넓은 문화시설 코드만 있으면 검증 필요
- `PK6` 등 알려진 무관 장소 그룹은 요청 분야와 불일치로 제외
- 알려진 분야 불일치는 결과에서 제거하고, 정보가 부족한 후보는 `verification_required`/`unknown` 상태로 남긴다. 검증 필요 후보는 최종 추천 가능 후보가 아니라 후속 단계가 판단할 검토 입력이다.

### Kakao 중심 후보 검색

`search(category, region, preferences, visited_place_ids, visited_place_names)`가 1단계 `RecordPreferenceAnalysis` 목록과 명시적 지역을 입력받는다. 첫 기록의 주소로 지역을 정하지 않는다.

- 선택 분야와 해당 기록의 장소 유형, facet 대상/특징을 조합해 지역이 포함된 검색어를 만든다. 예: `광주 유자하이볼 이자카야`, `광주 조용한 카페`, `광주 넓은 카페`.
- 선호가 구체적이면 먼저 구체어, 사전 정의한 완화어, 마지막으로 분야 일반어 순으로 검색 범위를 넓힌다. 검색 일반화는 후보 적합성 증거로 기록되지 않는다.
- 동일 정규화 검색어는 중복 제거한다. 서비스 인스턴스는 Kakao 결과를 5분 캐시하고 최대 256개를 보관한다.
- 최대 6회 Kakao 호출, 호출별 6초 timeout, Kakao keyword helper의 결과 최대 5개를 사용한다. 실제 ID/좌표/지역 주소가 확인된 결과만 내부 DTO로 인정한다.
- Kakao ID 중복, 정규화 장소명 중복, 사용자 방문 ID/장소명 중복을 제거한다.
- 분야 일치 후보가 3곳 미만이면 검색 범위를 넓혀 더 찾되 최대 호출 예산을 넘지 않는다. 0곳이어도 일반 결과를 분야 적합/개인화 적합으로 표시하지 않는다.

### Tavily 특징 근거 보강

분야가 Kakao category로 `confirmed`된 후보 중 최대 3곳에만 Tavily를 호출한다. 검색어는 Kakao 장소명, 명시 지역, 주소의 구 단위, 해당 기록의 관련 선호를 포함한다. Tavily는 기본 검색, 결과 최대 5개, 호출별 8초 timeout을 사용한다.

웹 결과는 Kakao의 실재 장소 확인 역할을 대신하지 않는다. 장소명 전체와 지역/구가 같은 제목 또는 같은 요약 필드에서 확인되어야 동일 지점으로 취급한다. 이름만 같고 다른 구인 지점은 근거에서 제외한다. 일치 장소의 제목/요약에 구체 선호가 실제로 나타나고 HTTPS 근거 URL이 있을 때만 `confirmed`로 남긴다.

후보별 출력은 Kakao 장소 필드/카테고리 판정, 선호별 확인 상태·발췌·근거 URL, 부족/미확인 상태를 분리한다. Tavily 미설정·오류·timeout·근거 부족은 Kakao 후보를 삭제하지 않는다. 미확인 선호는 근거 없는 개인화 사유로 바꾸지 않는다.

동일 서비스 인스턴스에서 Kakao 질의 결과는 5분 캐시한다. Tavily 근거 결과는 장소 ID+정규화 검색어 기준으로 성공 1시간, 빈 결과 1분 캐시한다. 캐시는 인스턴스 메모리 전용이므로 여러 worker 간 공유되지 않는다. 3단계에서 service lifetime 및 다중 worker 캐시 필요성을 정해야 한다.

### 외부 호출 예산

- 최악의 상한: Kakao 6회 × 6초 + Tavily 3회 × 8초 = 단계별 timeout 총합 기준 60초.
- Kakao는 순차 broadening, Tavily는 최대 3개 후보를 병렬 처리하므로 네트워크 대기만 놓고 본 일반적인 상한은 약 36초 + 8초에 가깝다. OS/thread scheduling/provider overhead는 별도다.
- 기존 경로의 분석상 Tavily 최대 3회와 Kakao 최대 6회를 이미 쓴다. 새 독립 서비스의 예산은 호출 수를 늘리지 않고, OpenRouter 순위 호출은 하지 않는다.
- 범주가 불확실한 후보에는 Tavily를 호출하지 않아 웹 요청을 아낀다.

### 설계안·1단계와 실제 코드 차이

1. 2단계 목표에 맞춰 새 서비스는 Kakao를 먼저 조회하고 Tavily를 동일 후보의 특징 검증에만 쓴다. 기존 운영 서비스는 여전히 Tavily 후보를 Kakao로 확인하는 순서이며 변경하지 않았다.
2. 실제 DB에 Kakao category 컬럼은 여전히 없다. Kakao category는 새로운 검색 응답/선택 DTO에만 담고 DB에는 저장하지 않는다.
3. 분야 불일치는 제거하지만 불명확 분류는 별도 `verification_required`/`unknown` 후보로 보존한다. 이는 임의 업종 확정을 금지하는 정책을 반영한다.
4. 설계안의 `Tavily에서 발견한 상호 → Kakao 검증` 역검색은 이번 하위 작업에서 구현하지 않았다. 이번 요청은 Kakao 중심 후보 검색과 Kakao 후보에 대한 Tavily 근거 확인이므로, 별도 역검색 경로는 통합 전 비용/품질 근거가 있을 때 추가한다.

### 수정 파일 및 테스트

- 수정: `overlap/backend-fastapi/app/kakao.py` (내부 helper 선택 category 필드 추가)
- 추가: `overlap/backend-fastapi/app/place_candidate_search_service.py`
- 추가: `overlap/backend-fastapi/tests/test_place_candidate_search_service.py`
- 수정: `docs/AI_REDESIGN_PROGRESS.md`

새 후보 검색 테스트 단독: **21 passed**.

기존 AI 관련 테스트(1단계 분석, record adapter, 기존 추천 API, Kakao 검증/API, OpenRouter 구조/fallback, 이미지 서비스): **65 passed**.

위 두 범위를 합친 실행: **86 passed**, 경고 1건(설치된 Starlette 테스트 클라이언트의 `httpx` deprecation). 외부 네트워크 호출 없이 모두 mock으로 실행했다.

### 다음 3단계 연결 지점

새 추천 API service/factory에서 다음 순서로 호출할 수 있다.

```python
profile = RecordPreferenceAnalysisService().analyze(records, category=category)
candidate_result = PlaceCandidateSearchService().search(
    category=category,
    region=region,  # 선택/지도에서 결정한 값을 명시 전달
    preferences=profile.analyses,
    visited_place_ids=visited_ids,
    visited_place_names=visited_names,
)
```

3단계는 `CandidateSearchResult`의 Kakao confirmed 후보만 hard gate 통과 후보로 취급하고, `verification_required`는 보수적 후속 검증을 거쳐야 한다. 사용자 선호 relevance는 `preference_evidence.status == confirmed`일 때만 점수/추천 이유에 반영한다. Tavily 불충분/오류는 해당 후보를 자동 탈락시키지 않되, 그 선호를 확인했다는 말도 하지 않는다. 그 뒤 점수·최대 3개 응답·category/region 포함 cache key를 별도 구현해야 한다.

## 작업 보호 상태

브랜치 `feature/fullstack-ujin`을 유지했다. 기존 미커밋 변경, `.env.example` 삭제, Excel 파일과 앞서 추가된 1단계 분석 산출물을 보존했다. commit/push/merge, DB 스키마/데이터 변경, Flutter 변경은 하지 않았다.

## 3단계: 분야별 추천 API 통합

### 구현 범위

- `GET /ai/recommendations`의 기본 실행 경로에서 1단계 기록별 분석, 2단계 Kakao 우선 후보 검색/Tavily 근거 확인을 연결했다.
- API는 `category=all|food|bar|cafe|nature|activity` 및 `region`을 받는다. 기존 Flutter 호출 호환을 위해 두 값이 생략되면 `all`과 기록 주소의 최빈 광역 지역을 사용한다. 동일 빈도인 지역은 최근 기록 순으로 결정된다. 기록 주소에서 지역을 얻지 못하면 422를 반환한다.
- 추천 후보는 요청 분야의 Kakao 분류가 `confirmed`인 장소만 반환한다. 분야 분류 불명·검증 필요 후보는 안전한 후속 검증기가 아직 없으므로 결과에서 제외한다.
- Tavily에서 `confirmed`된 선호만 개인화 점수, `matched_keywords`, 추천 이유에 사용한다. 근거가 없는 후보는 분야 적합 장소로만 소개하며 취향 근거 부족을 응답 이유에 명시한다. Tavily가 실패해도 Kakao 장소 후보 자체는 보존한다.
- 기존 응답 DTO, 인증, 최대 3개 반환, 추천 새로고침 세션, 기존 장소 방문 중복 방지, 이미지 보강을 유지했다. 세션 키에 category, region, 분석 로직 버전을 추가했다.
- 기록별 OpenRouter 분석은 category/region 선택마다 반복하지 않도록 사용자+기록 fingerprint 기준으로 20분 메모리 캐시한다. 후보 검색 서비스는 기존의 Kakao 최대 6회, Tavily 최대 3회 및 각 요청 timeout/cache 제한을 유지한다.
- 기존 레거시 서비스를 명시 주입하는 테스트/통합 경로는 그대로 동작한다. `create_app`의 일반 운영 기본값은 새 분야별 경로다.

### 변경 파일

- 수정: `overlap/backend-fastapi/app/ai_recommendations.py`
- 수정: `overlap/backend-fastapi/app/main.py` (검색/분석 서비스를 테스트·운영 구성에서 주입 가능)
- 추가: `overlap/backend-fastapi/tests/test_ai_recommendation_category_integration.py`
- 수정: `docs/AI_REDESIGN_PROGRESS.md`

### 통합 API 예시

```http
GET /ai/recommendations?category=bar&region=광주
```

4단계 Flutter는 사용자가 고른 분야와 명시 지역을 전달하면 된다. 기존 클라이언트는 현재 기본값 및 주소 기반 지역 호환 경로를 사용한다. 다중 worker 환경에서 분석·검색·세션 캐시는 프로세스별로 분리되므로 배포 규모가 커지면 공용 cache/cursor로 옮겨야 한다.

### 3단계 확인 결과

- 신규 API 통합 테스트: **3 passed** (Kakao/Tavily/분석을 모두 stub으로 처리; 확정된 술집 및 메뉴 근거 응답, 불확실 분류 제외, 기존 응답 모양 확인).
- AI 추천 관련 테스트 묶음: **84 passed** (새 통합 테스트와 기존 추천 API, 1·2단계 분석/검색, OpenRouter fallback, Kakao 검증, 이미지 서비스 포함).
- 전체 FastAPI 테스트: **273 passed, 11 failed**. 남은 실패는 수정하지 않은 map/records/group membership·notification 테스트에서 발생했다(공유 장소 가시성, 그룹 멤버십 중복 등의 assertion/SQLite unique 오류). 추천 API 관련 테스트는 별도 묶음에서 모두 통과했다.
- 경고 1건은 설치된 Starlette 테스트 클라이언트의 `httpx` deprecation이다. 전체 실행에는 `-p no:cacheprovider`를 써서 pytest cache 쓰기를 끄고 기존 cache 파일을 보존했다.
- 외부 유료 API는 호출하지 않았다. DB schema/data와 Flutter는 변경하지 않았다.

### 다음 단계

4단계에서는 Flutter에 분야 선택과 지역 선택 입력을 연결하고, `category`와 `region` query parameter를 전송한다. API는 이미 이 두 값을 수용한다. 실제 계정의 추천 수·분야 일치율·개인화 근거율 및 응답시간은 mock 테스트와 별도로 확인할 운영 검증 과제다.

## category-v3 기본 분기 오류 수정 (2026-10-14)

### 원인과 수정

`ai_recommendations.router()`가 기존 Tavily 경로의 서비스 객체를 기본 생성한 다음 `use_category_pipeline`을 계산하고 있었습니다. 따라서 호출자가 레거시 서비스를 전달하지 않아도 기본 생성된 객체들이 “서비스 주입됨” 조건으로 판정되어, 기본 요청이 `legacy-tavily-v2`로 흘렀습니다. 또한 `create_app()`은 `candidate_search_service=None`을 그대로 라우터에 전달하고 있었습니다.

분기 선택을 기본 서비스 생성보다 먼저 계산하도록 바꾸고, 정상 `create_app()` 구성에서 `PlaceCandidateSearchService`와 `RecordPreferenceAnalysisService`를 생성해 주입합니다. 기본 category 값은 API 모델의 기존 기본값인 `all`을 유지합니다. category가 생략된 요청과 `all`, `food`, `bar`, `cafe`, `nature`, `activity` 요청은 category-v3 경로를 사용합니다.

기존 테스트 및 롤아웃 호환을 위해 레거시 협력 객체를 명시적으로 전달하면 레거시 경로를 유지합니다. `create_app(use_legacy_recommendation_pipeline=True)`로도 레거시를 명시 선택할 수 있습니다. 새 후보 검색 서비스가 함께 제공되면 category-v3가 우선합니다.

### 검증

기본 `create_app()` 구성으로 인증된 API 요청을 보내는 회귀 테스트를 추가했습니다. 외부 API는 호출하지 않고 분석 및 Kakao 후보 검색 메서드를 mock으로 대체해 다음을 확인합니다.

- category 생략은 `all`로 전달되고 category-v3가 선택됨
- 6개 지원 분야가 신규 후보 검색 서비스에 전달됨
- 기록 분석은 첫 요청에 실행되고 분석 캐시가 재사용됨
- 추천 세션 cache/refresh 응답 계약이 유지됨
- 기본 로그에서 `pipeline=category-v3`가 확인되고 `legacy-tavily-v2`가 선택되지 않음
- 명시적으로 주입된 기존 mock 서비스와 레거시 추천 테스트가 계속 통과함

관련 FastAPI AI 테스트: **85 passed**, 경고 1건(Starlette 테스트 클라이언트의 httpx deprecation).

### 변경 파일

- `overlap/backend-fastapi/app/ai_recommendations.py`
- `overlap/backend-fastapi/app/main.py`
- `overlap/backend-fastapi/tests/test_ai_recommendation_category_integration.py`
- `docs/AI_REDESIGN_PROGRESS.md`

이번 작업 환경에서는 확인 시점에 포트 8002 리스너가 없어 실행 중 프로세스 경로는 확인하지 못했습니다. 실행 중인 Uvicorn 프로세스는 이미 import한 모듈을 계속 사용할 수 있으므로, 변경을 적용하려면 프로세스를 재시작해야 합니다. Windows에서 포트 8002의 프로세스와 실행 명령을 확인하려면 `$owners = Get-NetTCPConnection -LocalPort 8002 -State Listen | Select-Object -ExpandProperty OwningProcess -Unique; foreach ($owner in $owners) { Get-CimInstance Win32_Process -Filter "ProcessId = $owner" | Select-Object ProcessId, ExecutablePath, CommandLine }`를 실행합니다. 출력된 명령의 `uvicorn app.main:app` 및 `--app-dir`(있는 경우)을 확인하고, 실행 PowerShell의 현재 폴더가 `overlap/backend-fastapi`인지 대조합니다.

## DB 연결 풀 안정성 개선: 사진 조회에서 Object Storage I/O 분리 (2026-10-14)

### 진단 결과

운영 엔진은 SQLAlchemy `create_engine()`에서 `pool_size`, `max_overflow`, `pool_timeout`을 별도로 지정하지 않습니다. 따라서 QueuePool 기본치인 pool size 5, overflow 10, 대기 30초가 적용됩니다. DB 세션 의존성은 요청에서 만든 `Session`을 `yield`한 뒤 응답 처리가 끝날 때 `close()`합니다. DB 인증의 `current_user()`가 사용자 조회로 연결을 열고, 같은 세션을 사진 라우터가 사용합니다.

기록 사진, 기록 작성자 사진, 댓글 작성자 사진, 내 프로필 사진, 모임 멤버 사진은 권한/메타데이터 조회가 끝난 뒤에도 DB 세션을 반환하기 전에 NCP Object Storage를 호출하고 `StreamingResponse`로 본문을 전송했습니다. FastAPI의 yield dependency 정리는 스트리밍 응답이 끝날 때까지 유지될 수 있어, Object Storage 응답 지연 및 이미지 전송 시간이 DB 연결 lease에 더해집니다. 15개 연결이 사진 응답들에 묶이면 다음 요청의 인증 쿼리가 연결을 얻지 못해 30초 후 QueuePool Timeout이 나는 경로가 성립합니다. 따라서 인증은 원인이라기보다 같은 풀을 필요로 하는 후속 요청의 실패 지점입니다.

`database_connection_lease`는 코드상 SQLAlchemy `checkout` 이벤트 시각부터 `checkin` 이벤트 시각까지의 실제 연결 대여 시간입니다. 연결 checkout 대기 시간 자체가 아닙니다. 30.396초 lease 로그는 실제 checkout된 연결이 약 30.4초 뒤 반환됐다는 의미이며, 별도의 `database_pool_timeout`은 연결 checkout 실패입니다. 이번에 `database_request_scope_duration`도 추가해 요청/의존성 총 시간과 연결 lease를 구분할 수 있게 했습니다.

### 변경 내용

사진 데이터를 확인한 직후 응답에 필요한 객체 키와 MIME 타입을 일반 문자열로 복사하고 `db.rollback()`하여 읽기 전용 트랜잭션과 연결을 반환합니다. 이어서 NCP 다운로드와 스트리밍을 시작하며, 그 뒤에는 ORM 객체의 지연 로딩을 사용하지 않습니다. 기존 권한 필터, 404/502 처리, 콘텐츠 타입, Cache-Control 및 nosniff 헤더를 유지했습니다. `get_db` 종료 시 2초 이상인 요청 의존성 범위는 `database_request_scope_duration`으로 기록합니다. 기존 checkout/checkin 기반 `database_connection_lease`는 연결 점유 시간 진단을 계속합니다.

QueuePool 크기나 timeout은 조정하지 않았습니다. AI 추천 코드, 추천 알고리즘, Flutter, 스키마와 DB 데이터는 수정하지 않았습니다.

### 검증 결과

- 신규 QueuePool(크기 1, overflow 0) 사진 API 테스트: **4 passed**. 실제 QueuePool checkout/checkin 이벤트 짝을 측정했고, 느린 Object Storage 호출 및 본문 읽기 때 checked-out 연결이 0임을 확인했습니다. 느린 응답에서는 request scope 로그가 발생하면서 연결 lease는 Object Storage 지연보다 짧았습니다.
- 사진/인증 권한, 누락 사진, 저장소 오류 및 동시 12건 요청 중 인증 재조회: 위 테스트에 포함; 외부 저장소는 mock.
- DB pool 진단 테스트: 신규 사진 테스트와 함께 **6 passed**.
- 기존 record/group/comment 사진 관련 테스트: **7 passed, 48 deselected**.
- 기존 AI 추천 회귀 묶음: **85 passed**.
- FastAPI 전체: **277 passed, 11 failed**. 실패는 map/record visibility·group membership 및 notification 관련 기존 assertion/SQLite unique 제약 영역입니다. 이 작업의 사진 pool 테스트와 AI 회귀 테스트는 통과했습니다. 이전 작업 기록에도 같은 범주의 전체 테스트 실패 11건이 보고되어 있습니다.
- `git diff --check`: 오류 없음(Windows CRLF 변환 안내만 출력).

모든 DB 검증은 격리된 SQLite QueuePool을 사용했고, NCP는 mock 처리했습니다. 운영 MySQL의 연결 제한/응답 지연과 실제 NCP 지연은 이번 작업에서 직접 검증하지 않았습니다.

### 변경 파일

- `overlap/backend-fastapi/app/db.py`
- `overlap/backend-fastapi/app/records.py`
- `overlap/backend-fastapi/app/comments.py`
- `overlap/backend-fastapi/app/main.py`
- `overlap/backend-fastapi/tests/test_photo_db_pool.py`
- `docs/AI_REDESIGN_PROGRESS.md`

### 남은 점검

운영 서버에서 요청 path별 `database_connection_lease`와 `database_request_scope_duration`을 비교해 lease가 실제로 낮아졌는지 확인해야 합니다. MySQL `max_connections`, 현재 연결 수, slow query 및 NCP의 실제 응답/스트림 종료 오류는 별도 운영 관측이 필요합니다. NCP `get_object` 요청에는 기존 connect timeout 5초, read timeout 20초, 재시도 설정이 있으나, 반환된 body를 스트리밍하면서 발생하는 읽기 오류는 `download()`의 초기 `get_object` 예외 처리 바깥에서 생길 수 있습니다.


## 4단계: Flutter 분야 선택 UI 및 API 연동

### 구현 내용

- 기존 AI 추천 Bottom Sheet의 상단에 가로 스크롤 ChoiceChip 6개를 추가했다. 화면 라벨은 전체, 맛집, 술집, 카페, 자연산책, 문화스포츠이고 API 값은 각각 all, food, bar, cafe, nature, activity다.
- 새 분야 선택 즉시 이전 카드를 비우고 로딩 표시를 낸다. 요청 세대와 현재 선택 분야를 확인해 오래된 성공 응답이나 오류 응답이 현재 결과를 덮지 못하게 했다.
- AiRecommendationsApi는 분야별 진행 요청을 각각 병합한다. 분야별 첫 요청은 category만 보내고 refresh를 생략한다. 같은 분야 재방문 및 다음 추천 요청에는 해당 분야가 이미 성공적으로 로드된 경우에만 refresh=true를 보낸다. 인증 토큰 변경 시 분야별 이력을 초기화한다.
- 같은 칩 재선택은 요청하지 않는다. 다른 장소 추천 버튼은 현재 선택 분야의 다음 요청을 실행하며 문구는 다음 장소 추천받기로 표시한다. 실제 신규 검색은 추가하지 않았다.
- 빈 결과 안내는 “이 분야에서 취향에 맞는 장소를 아직 찾지 못했어요.”로 표시한다. 로그인 만료, 서버 오류, 네트워크 오류, timeout 메시지를 분리했다. 기존 카드의 이미지, 상세/지도 이동, 즐겨찾기 구현은 그대로 사용한다.
- 디버그 로그에는 category, refresh, 성공 시 실제 HTTP 상태 코드, 실패 시 상태 코드, 추천 개수, 처리 시간과 stale 응답 폐기 여부만 기록한다. 토큰, 사용자 식별 정보, 기록 원문은 기록하지 않는다.

### 검증

- 관련 AI 추천 API, 분야 선택, 카드 및 지도 테스트: **28 passed**.
- Flutter 전체 테스트: **156 passed**.
- flutter analyze: **No issues found**.
- Android debug APK: **빌드 성공**. 산출물은 overlap/frontend/build/app/outputs/flutter-apk/app-debug.apk.
- 작은 320px 폭 위젯 테스트에서 가로 칩 스크롤과 레이아웃 예외가 없는지 확인했다. 지연된 전체 응답이 카페 선택 결과를 덮지 않는 위젯 테스트도 통과했다.

### 변경 파일

- overlap/frontend/lib/features/ai/screens/ai_recommendation_screen.dart
- overlap/frontend/lib/features/ai/services/ai_recommendations_api.dart
- overlap/frontend/lib/core/network/api_client.dart
- overlap/frontend/lib/core/network/api_transport.dart
- overlap/frontend/test/ai_recommendations_api_test.dart
- overlap/frontend/test/ai_recommendation_category_test.dart
- overlap/frontend/test/ai_recommendation_card_test.dart
- overlap/frontend/test/ai_recommendation_map_focus_test.dart
- overlap/frontend/test/notification_integration_test.dart
- docs/AI_REDESIGN_PROGRESS.md

실제 Android 에뮬레이터와 실제 계정에서 분야별 추천 품질은 아직 실행 확인하지 않았다. 디버그 로그와 APK를 이용해 실제 category 파라미터 및 응답을 검증할 수 있다.


에뮬레이터에 앱을 설치해 실행했고 로그인 화면 표시까지 확인했다. 테스트 계정이 없어 인증 후 분야 선택 화면과 실제 계정 응답은 확인하지 않았다.


## 5단계: 실제 개인화 근거와 전체 추천 순위 개선

### 기존 경로 진단

- category-v3 응답 조립부는 OpenRouter 장소 순위 서비스를 호출하지 않았다. Kakao 분야 확인 후보를 Tavily 선호 키워드 일치 여부, 일치 개수 기반 점수, 장소명으로 정렬했다. 여러 분야의 후보를 한 번에 비교하는 모델 순위 단계는 없었다.
- `all` 검색어는 분석 결과에 들어온 분야 순서대로 생성했고, Kakao 확정 후보가 3개 쌓이면 검색을 중단했다. 따라서 앞선 분야에서 후보 3개가 발견되면 뒤 분야 선호는 후보 수집 및 Tavily 근거 확인 기회가 줄 수 있었다.
- Tavily는 Kakao 확정 후보 중 검색 순서 앞의 최대 3곳만 조사했다. 근거가 없는 후보도 category-v3 응답 조립부에서 Kakao 분야 확인 문구와 웹 근거 부족 문구를 합친 추천 이유로 반환했다.
- 기본 지역은 명시적 `region`이 없으면 긍정 기록 주소의 첫 행정구역 중 빈도가 가장 높은 값으로 정한다. 기록 지역의 혼합은 이 기본 선택에 영향을 준다. 이번 작업은 이 지역 정책을 변경하지 않았다.
- 현재 실제 계정의 긍정 기록 분야 분포, unknown 비율, 후보 분포 및 Tavily 성공률은 실행 계정에 접근하지 않아 측정하지 않았다. 새 진단 로그에서 요청별 집계를 확인할 수 있다.

### 구현 내용

- `all` 검색어의 우선순위를 기록 분야 입력 순서가 아니라 감정 강도, facet 신뢰도, 대상 구체성으로 계산한다. 긍정 기록의 구체적인 대상을 우선하고 `맛있었다` 같은 일반적인 평가어만으로 검색어를 만들지 않는다. 분야별 강제 할당량은 추가하지 않았다.
- 후보를 수집할 때 3개 분야 확인 후보만으로 Kakao 검색을 조기 종료하지 않고, 생성한 우선순위 검색어를 최대 6회까지 확인한다. 최대 호출 상한은 기존 Kakao 6회, Tavily 3회에서 늘리지 않았다. 실제 호출 수는 기존 조기 종료보다 증가할 수 있다(최악의 경우 요청당 Kakao 최대 6회). Tavily는 확인 후보 중 사용자 기록의 분야·facet과 맞는 후보를 우선해 기존 최대 3곳만 조회한다.
- category-v3 개인화 점수는 확인된 facet 특징 근거(A)를 우선하고, 같은 분야의 긍정 기록과 후보 업종만 일치하는 후보(B)는 0.30 이하의 낮은 점수로 둔다. 사용자 기록 분야와 후보 분야가 연결되지 않는 C는 제외한다. A는 감정 강도와 facet 신뢰도를 반영하고, 반복되는 확인 취향을 합산한다. 정렬 동률은 장소명으로 안정화한다.
- 추천 이유는 확인된 선호 대상과 웹 근거가 연결되는 A에 대해서만 해당 선호를 언급한다. B는 기록에서 좋아한 업종과 후보 분야가 일치한다는 수준으로 설명한다. 내부 Kakao/Tavily 검증 상태 문구는 추천 이유에서 제거했다. Tavily 응답 실패는 B의 업종 근거와 구분하며 없는 메뉴·분위기를 주장하지 않는다.
- 서버 로그에는 긍정 기록 수, 분야별 분석 건수, unknown 수, 분야별 후보 수, 확인된 Kakao/Tavily 수, A/B 분포, 순위 입력·출력 수, 점수 구성 및 순위를 남긴다. 사용자 ID, 기록 원문, 인증 토큰, API 키는 기록하지 않는다.

### 변경 파일 및 테스트

- `overlap/backend-fastapi/app/ai_recommendations.py`
- `overlap/backend-fastapi/app/place_candidate_search_service.py`
- `overlap/backend-fastapi/tests/test_ai_recommendation_category_integration.py`
- `overlap/backend-fastapi/tests/test_place_candidate_search_service.py`
- `overlap/backend-fastapi/tests/test_personalized_candidate_ranking.py`
- 테스트는 합성 기록과 모킹 기반이며 실제 외부 API 및 실제 사용자 계정은 사용하지 않았다.


## 긴급 복구: 분석 실패 후 Kakao 검색어 0개

### 진단

- 당시 OpenRouter 로그는 `HTTPStatusError` 유형만 기록하고 HTTP 상태 코드를 저장하지 않았다. 제공된 로그만으로 400 스키마 오류인지, 401/403, 429, 5xx인지 과거 상태 코드를 확정할 수 없다. 실제 OpenRouter 호출은 다시 하지 않았다.
- 코드 경로는 분석 실패 시 장소명 규칙으로 판별된 유형·분야만 가진 base 분석을 `UNAVAILABLE` 상태로 돌려주고 있었다. 검색의 `all` 분야 수집과 쿼리 생성은 `liked` facet만 순회했으며, 알려진 장소 유형만으로는 쿼리를 만들지 않았다. `category=all`에서는 facet이 없는 분석의 분야도 수집되지 않았고, `category=nature`에서도 facet 반복문이 비어 검색어가 0개였다. 이후 Kakao 반복문에 진입하지 않아 호출 수가 0이 됐다.
- 추가로 Kakao 빈 결과는 성공 응답과 함께 300초 캐시됐다. 동일 쿼리의 캐시 적중은 외부 호출 수를 0으로 만들 수 있었지만, 기존 로그에는 빈 캐시 적중 수가 없어 입력 쿼리 0개와 구별할 수 없었다.

### 수정 내용

- 분석 실패 및 설정 누락 로그에 HTTP 상태 코드와 안전한 원인 분류를 남긴다. 400은 요청/스키마 호환성, 401/403은 인증·권한, 429는 rate limit, 5xx는 제공자 서버 오류로 구분한다. 응답 본문, 자격 증명, 기록 내용은 기록하지 않는다. 자동 재시도는 추가 API 비용과 요청 제한을 피하기 위해 하지 않는다.
- OpenRouter 실패 시 장소명에서 확인된 유형과 원문에 실제로 포함된 일부 명시적 메뉴·활동·자연 키워드를 보수적인 local facet으로 유지한다. `조용`, `넓`처럼 분야가 없는 특징은 분야를 임의로 붙이지 않는다. 명시적 facet이 없어도 신뢰 가능한 장소 유형과 긍정 감정이 있으면 그 분야의 낮은 우선순위 일반 Kakao 검색어를 생성한다.
- A/B/C 정책은 유지한다. 확인된 메뉴·특징은 Tavily 근거가 연결될 때만 A다. 유형 및 분야만 확인된 후보는 약한 B로 남고, 연결 분야가 없는 C는 제외한다. LLM 장애인데 안전한 검색 입력도 만들지 못하면 API는 빈 성공 응답 대신 503을 반환한다. 정상 Kakao 검색의 0건은 기존처럼 200과 빈 추천 목록을 반환한다.
- 검색 시작 시 category, 지역 원문/공백 정규화 결과, 입력 분석 수, 분야가 맞는 기록 수, 사용 가능한 facet 수, 생성 쿼리 수, 설정 존재 여부를 남긴다. 결과 로그는 Kakao 호출 수, 일반·빈 캐시 적중 수, 후보 수, 분야 필터 수 및 결과 원인을 구분한다. Kakao의 성공한 빈 검색 결과 캐시는 300초에서 30초로 줄였다.
- 분석 캐시는 기존대로 사용자 ID와 기록 fingerprint를 함께 키로 사용한다. Kakao 검색 응답 캐시는 사용자 기록이 아닌 공개 검색어 결과만 공유한다.
- 분석 응답을 받았어도 safe input이 없는 `category=all`/선택 분야는 503으로 구분하고, 안전한 검색을 수행한 결과 0건은 200 빈 목록으로 유지한다. Kakao 설정 누락은 기존 503 처리와 설정 여부 진단을 유지한다.

### 검증

- 13개 합성 기록(자연 유형 7개, 유형 불명 6개), OpenRouter 400/401/403/429/500/503 모킹, `all`·`nature` 검색, Kakao 실제 호출 모킹, 빈 입력/빈 결과/빈 캐시 만료, A/B/C, 사용자 fingerprint 격리 테스트를 추가했다.
- AI 추천·분석·후보 검색 관련 테스트: **97 passed**. FastAPI 전체: **296 passed, 11 failed**. 실패 11개는 이전 전체 테스트에서도 보고된 지도·기록·그룹 멤버십 테스트이며 이번 변경 파일과 무관하다. `git diff --check` 통과.
- 실제 외부 OpenRouter/Kakao 호출 및 실제 사용자 계정은 사용하지 않았다. 백업은 `.local-backups/ai-recovery-20261014-01`에 코드 변경 전 생성했다. 브랜치와 HEAD, 변경 파일 사본, 삭제 파일 목록, 바이너리 diff를 보관한다.

## 추천 이유 개인화 문구 개선 (2026-10-14)

### 원인 및 확인 범위

- category-v3의 A등급 이유는 Tavily에서 기록 facet과 연결된 확인 근거가 있을 때만 생성된다. 기존 문구는 연결된 선호어들을 한 문장에 넣었지만 후보별 근거의 차이를 문장에 드러내지 않아, 구체성이 약하고 반복적으로 느껴질 수 있었다.
- B등급 후보는 확인된 기록 장소 유형과 후보 업종만 일치한다. 이 경우 세 장소가 모두 술집이면 같은 안내 문구가 나오는 것은 의도된 보수적 정책이다. 메뉴/분위기 근거가 확인되지 않은 상태에서 후보마다 다른 취향을 지어내는 방식은 사용하지 않는다.
- A/B/C 실제 비율 및 사용자 기록의 분석 facet, Tavily 결과는 서버의 계정별 진단 자료가 없어 이번 작업에서 계산할 수 없다. 제공된 세 장소와 문장만으로 세 후보가 실제 A인지 B인지 단정하지 않는다.
- A등급 연결은 기록 ID 및 선호 문자열이 일치하고, 근거 상태가 confirmed이며 URL이 있는 후보 evidence만 수용한다. Tavily는 후보명과 지역(가능하면 세부 지역)이 같은 결과 문서에 등장해야 장소 동일성을 통과시키고, 그 뒤에도 선호 표현의 정규화된 문자열 일치를 요구한다. 이 엄격한 연결은 다른 지점/동명 장소의 오근거를 막지만, 표현이 다르면 관련 정보가 있어도 A로 연결되지 않을 수 있다. 이번에는 검증 문턱을 임의로 낮추지 않았다.
- OpenRouter 성공/실패 여부, 분석된 실제 facet, Tavily 메뉴/분위기 확인 결과는 요청별 안전 로그/계정 자료가 없어서 확인할 수 없다. 기록 원문, 인증정보를 추가로 기록하지 않는다.

### 변경 내용

- A등급 이유는 검증된 URL 근거에 연결된 실제 선호어를 직접 보여주도록 변경했다. 확인되지 않은 facet은 이유에 들어가지 않는다.
- B등급 이유와 A/B 점수, 추천 순위, 캐시, Tavily/Kakao 호출 예산, Flutter 응답 모델은 변경하지 않았다. 따라서 같은 수준의 근거만 있는 B 후보의 같은 문구는 계속 허용하며, 이를 무작위 동의어로 분산하지 않는다.
- 테스트는 서로 다른 두 A등급 메뉴 근거가 서로 다른 이유에 반영되는지, B등급 후보의 이유에 확인되지 않은 구체 취향이 들어가지 않는지 검증한다.
- 외부 API 호출이나 실제 사용자 계정 검증은 수행하지 않았다.
## 실제 로그 기반 category-v3 장애 수정 (2026-10-14)

### 확인된 내용

- 현재 로컬 설정의 `OPENROUTER_MODEL`은 `google/gemini-2.5-flash`이며 API 키 설정 여부만 확인했다(값은 출력하지 않음). 요청 endpoint는 OpenRouter Chat Completions이고 `response_format.type=json_schema`, 이름/strict/schema 구조 및 `provider.require_parameters=true`를 사용한다. 모델은 OpenRouter 문서상 structured output을 지원한다.
- 기존 분석 JSON Schema에는 Gemini structured-output subset에서 지원 여부가 확인되지 않는 문자열 `minLength`/`maxLength` 키워드가 있었다. 기록 분석은 응답 검증을 Pydantic에서도 수행하므로 해당 두 schema 제약을 요청에서 제거하고 애플리케이션 검증은 유지했다. 이는 제공된 400 로그와 일치하는 요청 형식 호환성 결함이다. 과거 로그에는 provider의 안전 오류 코드가 저장되어 있지 않아 해당 요청의 세부 코드를 소급 확정할 수는 없다.
- OpenRouter 400 분류 로그는 앞으로 상태 코드와 제한된 문자 집합의 provider `error.code`/`error.type`만 기록한다. 메시지/body, 키, 기록 원문은 출력하지 않는다.
- `unknown_category_count`는 이제 specific 분야 category가 없는 분석만 집계하며, 장소 유형만 unknown인 수는 `unknown_place_type_count`로 별도 기록한다. 기존 DB `places`에는 Kakao 카테고리 컬럼이 없고 adapter도 장소명/주소만 읽으므로, 카테고리 메타데이터가 분석기에 자동 전달되지 않는다. 400 시 로컬 이름 규칙으로 인식하지 못한 유형은 unknown으로 남을 수 있다. DB 스키마는 변경하지 않았다.
- 기존 Tavily 0회 로그에는 facet 수, Tavily 설정, 결과 캐시 여부가 없어 실제로 no-facet, 설정 누락, Tavily 캐시 적중 중 어느 분기였는지 소급 판별할 수 없다. 코드상 호출은 기록과 분야가 일치하는 liked facet 및 Kakao 분야 확인 후보가 모두 있을 때만 실행된다. 새 진단 로그는 facet 수, 분야 확인 후보 수, 키 설정 boolean, 결과 캐시 적중 수, 예상 외부 호출 수, 생략 사유를 표시한다. 호출 상한은 기존 3회다.
- 지역은 원본 값과 앞뒤/연속 공백을 제거한 값을 로그로 남긴다. Kakao 주소 지역 비교는 행정구역 alias를 적용하지만 검색어 자체에는 trim 외의 alias 변환을 하지 않는다. 후보의 실제 주소 문자열 대신 지역 불일치 개수와 요청 정규화 지역을 기록한다.
- `_log_place_decision()`의 format 문자열은 `reason=%s`를 포함하지만 전달 인자에서 reason을 빠뜨리고 있었다. 인자에 reason을 추가했다.
- 분석 결과 중 `UNAVAILABLE`가 포함되면 사용자별 기록 fingerprint 분석 캐시에 저장하지 않고, 이전 unavailable 캐시도 재사용하지 않는다. 추천 세션 캐시와 성공 분석 캐시의 사용자 격리는 유지한다.

### 수정 및 검증

- 분석 Schema 요청에서 unsupported 가능성이 있는 문자열 길이 키워드 제거, Pydantic 길이 검증 유지, 제한된 provider 오류 코드 로그 추가.
- Tavily 0회 분기를 facet 부재/분야 확인 후보 부재/설정 누락/결과 캐시 적중으로 관측 가능하게 했다. 실근거 없는 A 승격이나 검색/순위 변경은 없다.
- 분석 성공 yuzu-highball/skewer facet, HTTP 400 코드 안전 로그, 11 Kakao 후보에서 최대 3 Tavily 호출, 지역 앞 공백, category=all/bar/cafe 통합, A/B 검증, 후보 진단 로그 포맷, 분석 실패 캐시 비저장 테스트를 추가/확장했다.
- 실제 OpenRouter/Tavily/Kakao 호출과 사용자 계정 요청은 수행하지 않았다. 현재 장애 요청의 정확한 provider 오류 코드는 남은 정보가 없어 소급 확인 불가다.
### 최종 회귀 결과

- 관련 AI/category-v3 테스트: **90 passed**.
- 전체 FastAPI: **301 passed, 11 failed**. 실패 11개는 기존과 동일한 지도 핀/그룹 멤버십/기록 접근 관련 테스트이며, 이 수정 범위에서 새 실패는 확인되지 않았다.
- `git diff --check`: 통과.

## 실제 로그 기반 개인화 장애 점검 (2026-10-14)

### 확인 결과

- OpenRouter 요청은 endpoint `https://openrouter.ai/api/v1/chat/completions`, 모델 `google/gemini-2.5-flash`, `response_format.type=json_schema`, `json_schema={name, strict, schema}`, `provider.require_parameters=true`, `temperature=0`, `stream=false` 구성이다. API 키와 요청 payload 본문은 출력하지 않았다.
- 로컬 스키마는 객체마다 `required`가 모든 `properties`를 포함하고 `additionalProperties=false`를 사용한다. 로그의 `provider_error_code=400`만으로 거부 필드나 원인을 확정하지 못한다. 현재는 고정 허용목록에 있는 오류 파라미터와 JSON Schema 키워드만 따로 기록하고 메시지 전체는 기록하지 않는다.
- 공식 문서상 Gemini 2.5 Flash와 OpenRouter 모델 경로는 JSON Schema 구조화 출력을 지원한다. 다만 이는 현재 요청의 실제 HTTP 성공을 증명하지 않는다. 실제 외부 호출은 승인/비용 확인 전 실행하지 않았으므로 400의 제공자별 정확한 원인과 성공 여부는 미확정이다.
- 성공 모킹은 이자카야 기록의 유자하이볼/꼬치 개별 facet과 카페의 넓음/조용함 facet, 장소 맥락 및 분야 보존을 확인한다. 400 모킹은 허용된 파라미터/스키마 키워드만 로그에 남고 민감 메시지와 기록 원문은 남지 않는지 확인한다.
- A등급은 Kakao 확인 후보에서 confirmed 상태, URL, 동일 record ID, facet 대상/특징 문자열이 모두 일치해야 생성된다. 제공된 `tavily_evidence_confirmed_count=1` 집계는 해당 행의 장소/기록/facet 연결 정보를 포함하지 않아 과거 한 건이 A가 되지 못한 세부 원인을 특정할 수 없다. 연결 단계별 익명 집계 로그와 동일 record/facet이면 A, 다른 record ID이면 B인 테스트를 추가했다. 장소 동일성 및 지점 검증은 완화하지 않았다.
- `all` 점수에서 한 분석 기록의 category가 `cafe,food` 양쪽과 겹치면 `type_records`가 라벨별 중복 생성되어 유형 지지를 반복 합산하는 코드 결함을 재현했다. 동일 기록을 한 번만 반영하도록 수정했고 중첩 라벨 수/고유 지지 기록 수 로그를 추가했다. 점수 계수와 A/B 기준은 바꾸지 않았다. 과거 0.1660 결과의 실제 분석 category 스냅샷이 없어 해당 수치 중복 기여분은 확정하지 못했다.
- 지역은 명시값이 있으면 그대로 우선하고, 명시값이 없으면 기록 주소에서 빈도가 가장 높은 첫 두 주소 요소를 기본 지역으로 선택한다. 후보 주소도 광역 지역과 시군구/구 단위까지 비교하므로 통합특별시 같은 넓은 광역 이름만으로 여수·순천 후보가 광산구 기록에 섞이지 않는다. 광역 이름만 명시한 요청은 의도대로 광역 범위 검색이다. 실제 후보 주소 목록은 제공된 로그에 없어 이전 실행의 혼입 여부는 검증하지 못했다. 이전 로그의 정규화 값 앞 공백은 현재 `_norm()`의 trim 코드로 재현되지 않는다. DB 주소는 변경하지 않았다.

### 변경 및 검증

- OpenRouter 실패 로그에 허용목록 기반 schema 키워드와 고정 schema 경로만 추가. 프롬프트, 스키마 필드, 요청 예산은 바꾸지 않았다.
- 동일 기록의 중첩 category가 유형 지지에 이중 반영되는 문제만 제거하고 진단 계수를 추가했다.
- Tavily 확인 근거에서 같은 기록 연결 수와 facet 연결 수, 미연결 수를 기록한다. 원문, 사용자 식별정보, 토큰은 포함하지 않는다.
- 관련 AI/후보 검색 테스트: **90 passed**.
- 전체 FastAPI 테스트: **307 passed, 11 failed**. 기존과 동일한 map/records/notification 그룹 멤버십·가시성 실패이며 이번 변경에서 새 실패는 없다.
- DB, Flutter, 외부 API를 변경하지 않았다. 실제 OpenRouter 성공, 실제 후보 주소 분포, 과거 Tavily 근거가 A로 연결되지 않은 현장 후보는 실제 계정 호출로 아직 검증하지 않았다.
