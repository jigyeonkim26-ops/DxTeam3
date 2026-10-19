# OVERLAP AI 장소 추천 기능 상세 분석

- 분석 기준 폴더: `DxTeam3-finaltest-1019`
- 브랜치 / HEAD: `overlap-1019` / `4519cb303c140519473356fb712aebe8f53406e9`
- 분석 기준: HEAD에 더해 분석 시점 워킹 트리에 있던 AI 백엔드 미커밋 변경 포함
- 분석 범위: Flutter 추천 화면과 FastAPI 추천 엔드포인트, 기록 선호 분석, Kakao 후보 검색, Tavily 검증, 적합성 점수와 세션 페이지 처리
- 이 문서는 코드 읽기 결과이며, 분석 과정에서 애플리케이션 코드를 수정하거나 테스트를 실행하지 않았다.

> 이 폴더에는 분석 시점에 AI 관련 앱 코드와 테스트의 미커밋 수정이 있었다. 그러므로 아래 내용은 GitHub에 push된 `4519cb3`만 설명하는 것이 아니라 현재 폴더에 존재하던 수정까지 포함한다. 분석 문서 외의 코드는 변경하지 않았다.

## 1. 한눈에 보는 구조

```text
로그인 사용자
  ├─ 긍정 기록 최대 30건 + 방문 장소 ID/이름 조회
  ├─ 지역 결정: 요청 지역 또는 긍정 기록 주소에서 추론
  ├─ OpenRouter 구조화 분석: 기록별 장소 유형과 선호 facet 추출
  ├─ 기록에서 검색어 생성: 지역 + 구체 선호어 + 장소 유형 문맥
  ├─ Kakao Local 키워드 검색: 실제 POI 후보 수집
  ├─ 지역·방문 이력·중복·카테고리 필터
  ├─ 제한된 Tavily 웹 검색: Kakao 후보의 장소 정체성과 선호 근거 확인
  ├─ 결정적 A/B 적합성 판정 및 점수 정렬 (C는 제외)
  ├─ 후보 풀 최대 10곳을 서버 세션에 보관
  └─ Flutter에는 한 번에 최대 3곳 반환, 다음 요청에서 다음 페이지 반환
```

핵심은 **검색어는 기록을 분석해 만들고, 장소 후보는 Kakao에서만 가져오며, Tavily는 후보 장소가 실제로 해당 선호를 충족하는지 검증**한다는 점이다. 모델이 임의로 장소 이름을 만들어 결과로 내보내는 방식은 아니다.

## 2. 실제로 사용하는 파이프라인

기본 운영 경로는 `ai_recommendations.py`의 category pipeline이다. `router()`가 기본 collaborators를 구성할 때 `PlaceCandidateSearchService`와 `RecordPreferenceAnalysisService`를 만든다. 예전 keyword → Tavily 후보 검색 → Kakao 확인 → LLM 순위 경로는 레거시 collaborators를 명시적으로 주입하거나 `use_legacy_recommendation_pipeline=True`일 때 선택된다.

현재 category pipeline에서 기록 선호 분석은 `RecordPreferenceAnalysisService`가 OpenRouter Chat Completions API를 직접 호출한다. 모델 식별자는 `OPENROUTER_MODEL` 설정을 사용하며 설정 기본값은 `dots-studio/dots-3-note-preview:free`다. `.env` 값은 환경별로 달라질 수 있으므로 이 문서는 실제 키나 운영 설정값을 읽거나 기록하지 않는다. **현재 기본 category pipeline에는 Gemini 호출이 없다.** `LLM_PROVIDER`로 provider factory가 만드는 OpenRouter 선호 키워드/랭킹 서비스는 주로 이전 레거시 경로의 구성이다.

라우트는 `category` 쿼리 값을 받아도 현재 구현에서 `RecommendationCategory.ALL`로 고정한다. 요청 category가 `food` 등으로 들어오면 로그에 legacy 값으로 기록하고 전체 프로필 기반 추천을 수행한다. Flutter API는 보통 `/ai/recommendations`를 호출하며 지역을 보내지 않는다. 그래서 서버가 긍정 기록 주소에서 지역을 추론한다. API를 직접 호출하는 클라이언트가 `region`을 보내면 그 지역이 사용된다.

관련 코드:

- `overlap/backend-fastapi/app/ai_recommendations.py`
- `overlap/backend-fastapi/app/record_preference_analysis.py`
- `overlap/backend-fastapi/app/place_candidate_search_service.py`
- `overlap/backend-fastapi/app/kakao.py`
- `overlap/frontend/lib/features/ai/services/ai_recommendations_api.dart`
- `overlap/frontend/lib/features/ai/screens/ai_recommendation_screen.dart`

## 3. 추천에 들어가는 사용자 기록과 지역

### 3.1 입력 기록

`RecordRecommendationAdapter.list_positive_records()`는 로그인 사용자 소유의 기록 중 감정값이 `excellent`, `good`, `okay`인 기록만 조회한다. 각각 내부적으로 `LOVE`, `LIKE`, `GOOD`에 대응한다. 감정 강도는 `LOVE=1.0`, `LIKE=0.8`, `GOOD=0.6`으로 분석·가중치에 사용한다. `neutral`, `disappointed`, `poor` 기록은 선호를 긍정적으로 학습하는 입력에는 들어가지 않는다.

조회는 최신 작성순이며, 분석 서비스가 최대 30건만 사용한다. 각 기록의 본문은 외부 분석 요청 전에 URL·이메일·전화번호 패턴을 가리고 최대 500자로 제한한다. place name은 최대 120자, trusted category는 최대 120자다. 사용자의 원문 기록은 추천 검색·분석 provider로 전달되는 값이므로 이런 제한과 마스킹이 적용된다.

방문 장소 제외용 ID/이름 조회는 별도다. 이는 감정과 관계없이 사용자의 기록 장소를 읽되, 기록 본문은 이 조회에 포함하지 않는다. Kakao 장소 ID가 있으면 ID로, Kakao ID가 없는 장소면 정규화한 이름으로 이미 방문한 장소를 제외한다.

### 3.2 지역 선택

1. API 요청에 `region`이 있으면 이를 사용한다.
2. 없으면 긍정 기록 주소들의 앞부분에서 가장 자주 나오는 시·도 및 구/군 조합을 고른다.
3. 주소를 가진 긍정 기록이 하나도 없어 지역을 만들 수 없으면 category pipeline은 `422`로 지역 지정 오류를 반환한다.

주소 정규화는 Kakao 검색 문자열에 쓰는 이름과 행정구역 비교용 canonical 이름을 구분한다. 특히 새 통합 광역 주소의 core city 검색어는 Kakao 친화적인 `광주` 별칭으로 변환하면서, 후보 필터에서는 구·군 행정구역도 비교한다. 구/군이 명시된 요청은 해당 구/군 후보로 제한한다. 지역 확장은 요청에서 지역을 직접 지정하지 않았고 주소가 복수 지역 단위일 때만 가능하다. 현재 실제 도시 확장 rescue는 통합 광주 core city 범위에 구현되어 있다.

후보의 Kakao 도로명/지번 주소가 둘 다 있으면 **두 주소가 모두 요청 범위와 일치해야** 통과한다. 편한 주소 하나만 골라 통과시키지 않는다.

## 4. 기록을 검색 가능한 선호로 바꾸는 과정

### 4.1 OpenRouter가 만드는 분석 구조

각 기록은 다음 정보로 변환된다.

- `place_type`: `food`, `bar`, `cafe`, `nature`, `activity`, `unknown`
- `categories`: `all`과 관련 영역 목록
- `facets`: 기록 안의 하나의 구체 대상과 그 특징 관계
  - `target_kind`: `menu`, `drink`, `food`, `ambience`, `space`, `activity`, `scenery`, `service`, `facility`, `other`
  - `target_text`: 기록에 실제 등장한 구체 대상 명사
  - `features`: 기록에 실제 등장한 선호 특징
  - `polarity`: `liked`, `disliked`, `neutral`
  - `evidence`: 원문에서 그대로 가져온 짧은 인용
  - `confidence`: 0~1

프롬프트는 한 기록 안에서 긍정 감정과 세부 부정 표현이 함께 있을 수 있다고 설명한다. 예컨대 “낙지볶음은 맛있었지만 너무 매웠다”에서는 메뉴의 긍정과 매움의 명시적 부정을 별도 facet으로 나누도록 한다. 사용자 감정이나 일반 칭찬을 음식/장소 특징으로 둔갑시키지 않고, 기록에 없는 대상(예: 넓다는 표현만 보고 주차장을 추론)을 만들지 말라고 제한한다.

정서값은 모델이 바꾸지 못한다. 감정과 감정강도는 데이터베이스 기록에서 가져오며 모델 출력은 장소 유형·범주·facet 해석에만 사용한다.

### 4.2 모델 결과의 로컬 검증

모델의 JSON은 단순히 믿고 쓰지 않는다.

- `record_id`는 이번에 보낸 허용 ID 중 하나여야 하고 중복되면 제외한다.
- 필수 필드와 배열 형식, enum, 길이·범위는 Pydantic 모델로 검증한다.
- `target_text`는 기록 본문 또는 장소 이름에 실제 있어야 한다.
- `evidence`는 기록 본문 또는 장소 이름에 실제 인용되어야 한다.
- 각 `feature`는 기록 본문에 그대로 있어야 한다.
- `liked` facet은 긍정 기록이어야 하며, 명시적 부정 표현을 liked로 만들지 않는다.
- `disliked` facet은 정해진 부정 표현의 근거가 있어야 한다.
- 장소 유형은 Kakao trusted metadata, 로컬의 명시적 문맥/장소명 규칙, 검증 가능한 모델 인용 순으로 확정한다.
- 로컬 검증에서 범주를 다시 결정한다. 모델이 출력한 category label만으로 실제 음식/활동 범주라고 믿지 않는다.

분석 모델이 출력한 대상이 문장형 평가인 경우에도 검색 키워드가 되지 않도록 별도 판정이 추가돼 있다. `is_predicate_phrase()`는 `-습니다`, `-었음`, `-어요`, `-었고`, `-었지만` 같은 종결·과거형 연결 어미로 끝나는 표현을 걸러낸다. 따라서 `개맛있음`, `재밌었다` 같은 평가 문장을 target noun이나 Kakao 검색어로 취급하지 않는다. `조용해서`, `넓은`처럼 현재 특징을 꾸미는 말은 이 predicate 목록에 포함하지 않는다.

### 4.3 분석 provider가 실패할 때

OpenRouter 분석이 없거나 실패하면 로컬 기반 분석을 반환한다. 로컬은 place type을 Kakao category metadata, 기록의 명시적 표현, 모호하지 않은 장소명으로 추정하고 긍정 기록에만 제한된 literal term 목록을 적용한다. 그 목록에는 예를 들면 `유자하이볼`, `하이볼`, `칵테일`, `꼬치`, `치킨`, `초밥`, `파스타`, `커피`, `노을`, `산책`, `공원`, `조용`, `넓`, `아늑` 등이 있다. 목록은 무제한 키워드 사전이 아니다.

기록 문장에 있는 literal facet이 있어 안전한 검색어를 만들 수 있으면 해당 값으로 검색을 계속할 수 있다. 분석이 불가하고 안전한 검색 입력도 없으면 빈 검색어를 임의 생성하지 않고 503 오류로 실패시킨다.

## 5. Kakao에 실제 전달하는 검색어

### 5.1 검색어 기본 형식

검색어는 아래 구성으로 만든다.

```text
[정규화한 지역] [기록에서 나온 구체 선호어] [장소 유형 문맥어]
```

예를 들어 기록 분석이 다음과 같은 facet을 만들었다고 가정한다.

- target: `유자하이볼`, kind `drink`, category `bar`
- feature: 기록에 명시된 맛/분위기 표현
- inferred place type: `bar`

Kakao 요청은 예컨대 `서울 유자하이볼 이자카야`가 될 수 있다. 원래 term을 넓힌 후속 검색어 `서울 하이볼 이자카야`도 후보가 될 수 있다. 카페 영역에서 기록 특징이 `조용해서`라면 search-term 정규화 규칙에 의해 `서울 조용한 카페` 같은 형태가 만들어질 수 있다. 음식 영역의 `삼겹살`은 `광주 삼겹살 음식점`, 자연 선호의 `노을`은 유형에 따라 `광주 노을 산책로`와 같이 지역·특징·장소문맥으로 조합될 수 있다.

이 예시는 입력과 분석 결과가 해당 값으로 나왔을 때의 조합 예다. 기록과 OpenRouter 분석 내용에 따라 달라지며 매 요청에서 고정된 검색어를 보내는 것은 아니다.

### 5.2 어떤 기록 표현을 검색 term으로 쓰는가

- 음식/메뉴/음료 facet: 구체 `target_text`를 검색 term으로 사용한다. 단 `음식`, `메뉴`, `음료`, `술`, `매장`, `분위기`, `공간` 같은 넓은 단어는 검색 term으로 쓰지 않는다.
- 활동/경관 facet: 2자 이상인 target을 사용한다.
- facet의 `features`도 검색 term 후보지만 `맛있다`처럼 “맛있/좋/아름” 계열의 일반 칭찬은 제외한다.
- 특징 중 일부는 검색어 문법에 맞게 정규화한다. `조용…`→`조용한`, `넓…`→`넓은`, `아늑…`→`아늑한`, `친절…`→`친절한`이다. 기록 원문 근거는 그대로 유지하고 검색어 표기만 바뀐다.
- term이 이미 장소 문맥어 안에 있으면 중복 검색이 되므로 제외한다. `경기`가 `경기장`이라는 context와 겹치는 경우 같은 방식으로 빠진다.
- 현재 추가 수정에서는 평가 문장(predicate), 장소 유형 문맥에 포함된 term, 지역명만 있는 term을 query term에서 제외한다.

### 5.3 장소 context와 폭넓은 검색어

검색 카테고리별 context 목록은 다음과 같다.

| 선호 영역 | Kakao 검색 문맥어 후보 |
|---|---|
| food | `음식점`, `맛집` |
| bar | `술집`, `이자카야` |
| cafe | `카페` |
| nature | `산책로`, `공원`, `자연 명소`, `수목원`, `숲길`, `등산로` |
| activity | `경기장`, `문화시설` |

기록에 알려진 장소 유형이 있으면 현재 코드가 유형에 맞는 context 하나를 선택하는 경우가 많다. 예를 들어 BAR는 bar category에서 `이자카야`, 음식점 유형은 `음식점`, 카페는 `카페`, 자연은 `산책로` 또는 `자연명소`, activity는 `문화시설`을 고른다. 유형을 모르면 해당 범주의 첫 context를 사용한다.

검색어 빌더는 카테고리를 선호 강도에 따라 배치한다. 각 분석은 `emotion_intensity × facet.confidence × specificity`로 기여한다. 메뉴·음료·활동·경관 등 구체 대상의 specificity는 1.15, 그 외는 0.85다. 한 기록에 여러 facet이 있어도 category 기여는 기록별 상한으로 제한해 한 장문의 기록 하나가 모든 검색 슬롯을 차지하지 않게 한다. 카테고리마다 강한 선호 하나씩 번갈아 뽑아 처음 6회에 음식 검색어만 몰리지 않도록 한다.

추가로 범주 context만 붙인 broad fallback이 생성된다. 자연 범위가 있다면 `지역 산책로`, `지역 공원`, `지역 자연 명소`, `지역 수목원`, `지역 숲길`, `지역 등산로` seed 검색어가 후보가 된다. 이 broad 결과가 Kakao 후보를 발견하더라도, 특정 기록 선호어로 찾은 후보와 동일한 선호 근거를 자동으로 받은 것으로 취급하지 않는다.

### 5.4 term 축약 / 재검색 목록

현재 명시된 query reduction은 다음과 같다.

| 더 구체적인 표현 | 축약 검색 term |
|---|---|
| `유자하이볼` | `하이볼` |
| `과일하이볼` | `하이볼` |
| `칵테일` | `바` |
| `조용해서`, `조용하고`, `조용함` | `조용한` |
| `넓고`, `넓어서`, `넓음`, `넓은 실내` | `넓은` |

특정 의도의 원형 검색을 약한 축약형보다 우선한다. query budget이 작으므로 모든 동의어를 무차별로 먼저 보내지 않고 강한 독립 선호 검색어를 우선 처리한다. 특정 의도 수가 초기 슬롯보다 많으면 다음 검색 batch에서 broad context를 축약형보다 먼저 넣어, 많은 facet이 최대 12회 검색을 모두 소진하는 것을 완화한다.

### 5.5 검색 횟수·확장·중단 범위

- Kakao 전체 최대 호출 예산: 12회
- 최초 검색 예산: 최대 6회
- 최초 query 빌드 결과가 6개보다 적으면 가능한 만큼만 실행
- 장소별 최대 후보 풀: 50개
- 동일 query에서 새 장소는 최대 6개
- 최초 결과가 3개 미만이고 최초 query 구간을 모두 다뤘으면 남은 Kakao 예산/검색어로 continuation 검색
- continuation은 `query_offset`을 초기 예산 위치로 설정해 처음 query를 반복하지 않는다.
- query를 compact 형식으로 비교해 중복을 제거한다.
- Kakao 검색 응답은 성공 결과 5분 캐시, 빈 응답은 30초 캐시로 일시적인 빈 검색이 장기간 고착되지 않게 한다.

지역이 기록으로 추론된 구·군 범위이고 통합 광주 core city에 해당하면, 초기에는 해당 구를 검색하고 뒤에서 도시 범위 rescue 검색을 구성한다. 구 검색에서 결과가 있었던 선호 term을 도시 재검색에서 우선하고, 해당 구에서 결과가 비어 있었던 term은 뒤로 보낸다. 현재 이 확장 분기는 광주 특수 주소 케이스에 한정되어 있다.

## 6. Kakao 후보 필터와 분류

Kakao Local 키워드 endpoint는 지역/term query에 대한 장소 정보를 공급한다. 응답에서 장소 ID, 이름, 도로/지번 주소, 위경도, 장소 URL, category code/name, 현재 수정본에서는 전화번호도 내부 candidate로 매핑한다.

후보는 다음 순서로 정리된다.

1. 좌표·필수 필드가 유효한지 검증한다.
2. 모든 주소 variant가 지역 범위와 맞는지 확인한다.
3. 사용자가 이미 기록한 방문 장소인지 Kakao ID 또는 compact한 장소명으로 확인한다.
4. Kakao ID가 같은 후보는 합치고, 이름+지역이 같은 반복 후보는 중복 제거한다. 서로 다른 지점은 주소 locality가 다르면 무조건 합치지 않는다.
5. Kakao category group code와 category path, activity 일부는 장소명을 사용해 영역을 분류한다.

주요 Kakao 분류는 `FD6` 음식점, `CE7` 카페, 바 하위 분류(이자카야·호프·포차·펍·와인바 등), 자연 하위 분류, activity 하위 분류를 본다. 요청 범주가 전체일 때도 알려진 카테고리가 하나 이상 있어야 `CONFIRMED`가 된다. category가 없거나 넓은 것만 확인되면 `UNKNOWN`/`VERIFICATION_REQUIRED`로 남을 수 있다. 최종 personalized ranker는 Kakao 카테고리가 confirmed가 아닌 후보를 건너뛴다. 따라서 Kakao query가 장소를 반환했다는 사실만으로 추천 결과가 되지는 않는다.

## 7. Tavily 검색: 장소 확인과 특징 근거 확인

### 7.1 무엇을 Tavily에 보내나

Tavily는 Kakao에서 수집된 후보를 위해서만 호출되며, Kakao category가 confirmed이고 연결할 관련 선호 facet이 있는 후보 중 최대 6개를 선택한다. 한 검색 intent에서 후보 하나씩 우선 뽑는 round-robin을 적용해 특정 Kakao query에서 나온 후보만 Tavily 예산을 독점하지 않게 한다. 후보 우선순위는 더 높은 Kakao query priority, 장소명, Kakao ID 순으로 정렬된다.

현재 수정 코드에서는 후보를 발견한 Kakao query 전체를 장소별로 보관한다. 후보의 Kakao query 안에 facet의 target/feature 또는 허용 축약어가 **whole-token**으로 등장할 때 그 facet을 `query-linked`로 연결한다. 그래서 “경기”가 “경기장” 안에 우연히 포함되어 연결되는 식의 substring 오탐을 피한다.

Tavily query는 다음 모양이다.

```text
[Kakao 장소명] [그 장소 주소에서 추출한 시/구/동 지역] [Kakao query에 연결된 선호 term 최대 2개]
```

예: Kakao 후보 `별빛카페`, 주소 `서울특별시 마포구 …`, linked facet term `조용한`과 `넓은`이 있다면 `별빛카페 서울 마포구 조용한 넓은` 형태가 될 수 있다. 주소 지역을 쓰는 이유는 사용자가 지정한 큰 지역이나 요청 구와 후보 주소의 실제 구가 다를 수 있기 때문이다. Kakao에서 발견된 query에 연결된 선호만 Tavily query에 넣는다. 무관한 기록 term을 많이 넣으면 레시피나 다른 장소가 검색되어 장소 동일성 확인을 어렵게 하기 때문이다.

후보가 broad query로만 발견되어 Kakao query와 연결되는 facet이 없다면 Tavily 검색문에는 장소명+주소지역만 들어갈 수 있다. 그래도 해당 후보에 연결 가능한 category facet의 evidence terms를 결과 문서에서 확인할 수는 있지만, 관련 선호를 검색어에 억지로 끼워 넣지는 않는다.

### 7.2 외부 웹 결과에서 실제 장소라고 확인하는 기준

기본 Tavily 요청은 `search_depth=basic`, `max_results=5`, timeout 8초이며 후보 한 곳당 외부 요청 최대 1회다. 반환된 제목/내용에서 HTML tag와 entity를 정규화한다. 결과 URL은 허용된 안전한 URL이어야 한다.

장소 정체성은 아래 신호로 확인한다.

- 결과 URL에 해당 Kakao place ID URL이 있으면 직접 identity signal로 인정한다.
- 그렇지 않으면 같은 결과의 제목 또는 본문 한 필드 안에서 장소명과 주소 지역/구 locality가 함께 맞아야 한다.
- 전화번호가 Kakao에서 넘어왔으면 결과의 전화번호 일치도 강한 identity signal이다.
- 지점명이 있는 프랜차이즈는 base brand만 일치하는 것으로 다른 지점까지 섞지 않도록 branch suffix를 확인한다. `스타벅스 광주상무점`의 경우 주소도 맞는 `스타벅스 상무점` 표기는 허용하되 다른 branch는 걸러내는 방식이다.
- 짧은 장소명은 다른 단어 안에서 부분 일치하는 오탐이 많아 standalone 단어로 나타나거나 도로명/전화 같은 강한 신호를 동반해야 통과한다.
- title에 지점명이 있고 content에 별도 구 이름이 나오는 식으로 identity와 locality가 서로 다른 결과 필드에 흩어져 있으면 합쳐서 인정하지 않는다.

### 7.3 선호 근거 확인

identity가 먼저 확인된 문서에서만 선호어를 검사한다. 확인어는 입력 원문을 그대로 evidence key로 유지하지만 검색 매칭은 compact 형태, 알려진 어미 제거, 작은 의미 유사어 그룹으로 넓힌다. 현재 가까운 유사어 그룹은 다음과 같다.

- 조용 ↔ 한적·차분·고요
- 아늑 ↔ 포근
- 넓 ↔ 여유·쾌적
- 깔끔 ↔ 청결
- 전망 ↔ 경치·조망
- 노을 ↔ 석양·일몰

유사어는 이 폐쇄된 작은 그룹에만 적용한다. `친절`과 `서비스`처럼 의미를 넓게 연결해 과장된 A급 근거를 만들지는 않는다. preference term은 장소 이름 언급 주변 최대 250 compact 문자 윈도우 안에서 발견되어야 한다. Kakao place ID URL 자체가 결과 URL에 있으면 장소명 span을 못 찾는 경우 전체 결과 텍스트를 검사 구간으로 사용할 수 있다.

일치하는 term과 identity 문서가 있고 URL도 안전하면 facet별 `CONFIRMED` evidence를 만들고 본문 최대 320자를 evidence text로 보관한다. identity는 맞지만 term이 없으면 `INSUFFICIENT`, identity 자체를 찾지 못하면 `PLACE_IDENTITY_UNVERIFIED`다. provider가 없거나 실패하면 `UNAVAILABLE`이어서 검증 근거로 계산하지 않는다.

현재 uncommitted 수정의 요점은 (a) 모든 Kakao 발견 query를 보존해 실제 검색 term과 facet을 연결하고, (b) 전체 문장 부분 포함이 아니라 whole-token 매칭을 쓰며, (c) Tavily 문장에도 그 linked facet만 최대 2개 넣고, (d) Kakao phone/branch/road 신호와 250자 근접 근거창으로 동일 장소·동일 특징 확인을 강화한 것이다.

### 7.4 Tavily 호출 수와 캐시

- 전체 후보당 최대 6개 Tavily 검증 target / 외부 호출
- 초기 예산은 최대 3개, 부족한 결과를 위한 continuation은 전체 실제 사용량을 빼고 남은 예산을 계산
- 후보 query는 최대 2개의 linked 선호 term만 포함
- 결과 문서 최대 5개 사용
- Tavily 결과 캐시는 결과가 있으면 1시간, 빈 결과는 60초
- Kakao 검색 캐시는 정상 결과 5분, 빈 결과 30초

이번 폴더의 미커밋 라우트 변경은 continuation 예산을 초기 할당량 기준으로 단순 차감하지 않고 실제 `search_result.tavily_call_count`와 초기 Tavily 대상 수를 기준으로 남은 budget을 계산한다. 초기 검색에서 호출하지 않은 Tavily 예산을 불필요하게 잃지 않고, 이미 확인 대상에 포함된 Kakao 후보 수를 중복 계산하지 않으려는 수정이다.

## 8. 추천 적합성 판정과 점수

활성 category pipeline의 최종 ranker는 `ai_recommendations.py::_build_category_recommendations()`다. 이 기본 경로는 LLM에게 장소를 새로 만들거나 후보를 직접 순위화시키지 않고, 검증된 Kakao 후보에 규칙 기반 적합성·점수를 적용한다.

### 8.1 먼저 통과해야 하는 문

- Kakao category가 `CONFIRMED`여야 한다.
- 후보가 명시적으로 dislike한, Kakao category subtype으로 확인되는 유형과 충돌하면 거부한다.
- positive facet은 후보가 분류된 범주와 연결되어야 한다.
- 직접 특징 A급 주장이면 Tavily `CONFIRMED` evidence가 같은 `record_id`의 같은 target/feature에 연결되어야 한다.

### 8.2 A/B/C 등급

- **A**: Kakao category가 확정됐고, positive 기록 facet과 Kakao 후보를 연결하는 Tavily 웹 특징 근거가 확인된다. 근거 term은 같은 기록의 같은 facet target 또는 feature에 연결되어야 한다.
- **B**: 특정 category subtype이 기록 target과 일치하는 유형 근거가 있거나, 여러 긍정 기록에서 반복된 category affinity가 확인된다. 개별 음식/특징을 웹에서 확인한 것처럼 말하지 않는다.
- **C**: 장소 category만 맞고 개인 기록의 positive 선호와 연결되는 근거가 없다. 제외한다.

category affinity는 verified/partial 분석 기록에서 적어도 3개의 별도 긍정 기록이 같은 범주를 뒷받침하고, facet이 있는 경우 서로 다른 target이 적어도 2개 있어야 한다. facet 없는 범주 경험만으로는 3개의 기록이 반복돼야 한다. 같은 기록 내 overlapping category/facet을 여러 건의 독립 기록인 것처럼 부풀리지 않는다.

자연/경관은 Kakao category path만으로 “노을이 보인다”를 증명하지 않는다. 전망대처럼 특정 Kakao type과 해당 기록의 자연 선호/기술 cue가 맞는 경우에 한해 type-level B로 쓸 수 있다. 음식·바·카페·activity는 Kakao category path의 구체 leaf subtype이 기록 facet target과 일치할 때 type-level support를 인정하며, `음식점`, `카페`, `술집`, `문화시설` 같은 상위 generic label만으로는 구체 subtype 증거가 되지 않는다.

### 8.3 결정적 점수 공식

직접 검증한 A 후보의 점수는 다음과 같다.

```text
feature_weight = 각 같은 기록별 (감정강도 × facet confidence) 최댓값의 합
feature_by_record 수 = 특징 근거가 연결된 서로 다른 기록 수
A 점수 = min(1.0, 0.55 + min(0.35, feature_weight × 0.12)
                    + min(0.10, 서로 다른 근거 기록 수 × 0.025))
```

같은 기록의 여러 facet이 점수를 무한히 중복 가산하지 않게 record별 최대치를 쓴다.

```text
type_weight = min(1.5, 서로 다른 type 근거 기록별 (감정강도 × 0.5)의 합)
B(type subtype) 점수 = min(0.45, 0.32 + type_weight × 0.08)
```

```text
category_affinity_weight = affinity를 뒷받침하는 distinct record 감정강도 합
B(category affinity) 점수 = min(0.34,
  0.20 + min(0.10, category_affinity_weight × 0.012)
       + min(0.03, 서로 다른 긍정 target 수 × 0.01))
```

`match_score`는 확률로 해석하면 안 된다. 로컬 코드의 비교·정렬용 rubric 값이다.

### 8.4 정렬과 첫 페이지 다양성

기본 정렬은 `점수 내림차순 → Kakao query priority 내림차순 → 장소명 오름차순`이다. 동점권에서 같은 선호 term에 몰리지 않도록 첫 페이지 최대 3개에 한해 다양화를 시도한다. 현재 최고 점수보다 0.04 이내인 후보 중 아직 덜 다룬 선호 term을 더 많이 덮는 후보를 우선하고, 점수·검색 query priority·장소명으로 정한다. 점수가 크게 낮은 장소를 다양성 때문에 무리하게 앞세우는 category quota는 아니다.

서버 풀은 최대 10개를 보관하고 첫 응답은 최대 3개를 반환한다. `rank`, 이유(reason), `matched_keywords`, Kakao 장소 ID, 주소, 위경도, 장소 URL이 응답에 들어간다. 이미지 enrichment는 추천이 만들어진 뒤의 표시 보강이며 후보검색·적합성 근거를 만드는 단계와는 별개다.

## 9. 서버 세션과 Flutter 다음 추천 동작

서버 세션 키는 사용자 ID와 기록 fingerprint로 만든다. category pipeline fingerprint에는 방문 장소 목록, 선택 지역, 버전도 들어간다. 같은 사용자가 기록을 바꾸면 이전 사용자 세션을 지운다. 서버 세션과 분석 결과는 process-local LRU(최대 128 entry)이고 20분 TTL을 둔다. 프로세스 재시작 시 캐시가 없어질 수 있다.

- 일반 최초 요청: 해당 세션의 `first` 최대 3곳 반환
- 후속 요청 `refresh=true`: 이미 보여준 Kakao ID를 뺀 다음 최대 3곳 반환
- 더 보여줄 후보가 없음: `exhausted`와 빈 recommendations 반환. 이미 본 후보를 새 후보인 것처럼 반복 반환하지 않는다.
- 적격 결과가 실제로 0곳: `empty` 상태를 저장
- 빈 세션에서 명시적으로 refresh: 30초 cooldown 이후 최대 2회까지만 다시 탐색 가능
- 유효한 추천이 들어 있는 세션을 일반 요청으로 다시 열면 최초 3곳을 재현한다.

Flutter `AiRecommendationsApi`는 access token별로 메모리에 페이지 목록/페이지 인덱스/상태를 캐시한다. 첫 응답 이후 `refresh=true`로 받은 새 페이지를 기존 페이지 뒤에 쌓고 Kakao ID, 없으면 장소명으로 중복을 제거한다. 화면의 `처음 추천 다시 보기`는 기존 첫 페이지를 선택하므로 Gemini/OpenRouter, Kakao, Tavily를 재호출하지 않는다. 화면을 새로 만들더라도 같은 로그인 token의 API cache가 있으면 현재 저장된 페이지를 복원한다. 새 추천 세션을 명시적으로 시작하는 동작만 `startNewSession()`을 사용한다.

## 10. 분석 시점 워킹 트리의 AI 미커밋 수정 요약

`git status`에서 본 미커밋 변경은 아래 7개 파일이다. 문서는 이 변경까지 읽었다.

| 파일 | 변경 요지 |
|---|---|
| `overlap/backend-fastapi/app/ai_recommendations.py` | continuation의 Tavily 잔여 호출/후보 budget을 초기 할당치가 아니라 실제 사용량 기준으로 계산 |
| `overlap/backend-fastapi/app/kakao.py` | Kakao 결과 전화번호를 candidate 내부에 전달 |
| `overlap/backend-fastapi/app/place_candidate_search_service.py` | predicate/중복/지역 query 억제, 모든 후보 발견 query 보관, query-linked facet을 Tavily query와 연결, whole-token 매칭, morphology·폐쇄적 동의어 lookup, 후보 지점/짧은 이름/주소/전화 identity 확인, linked facet 최대 2개 Tavily query, 개발 진단 로그 |
| `overlap/backend-fastapi/app/record_preference_analysis.py` | 문장형 predicate target을 facet 검증에서 제외하고 OpenRouter prompt도 target은 구체 명사라고 명시 |
| `overlap/backend-fastapi/tests/test_ai_recommendation_category_integration.py` | continuation 예산 관련 통합 기대값 갱신 |
| `overlap/backend-fastapi/tests/test_place_candidate_search_service.py` | 새 검색 term/identity/Tavily 연결 동작 회귀 사례 추가 |
| `overlap/backend-fastapi/tests/test_record_preference_analysis.py` | predicate target 검증 회귀 사례 추가 |

현재 수정은 추천 검색/검증/랭킹 체인의 품질 개선이다. 앱 코드와 테스트 밖에 자동 생성 문서/진단 산출물을 기록하는 기능은 확인되지 않았다. 진단 로그는 diagnostics 활성 시 Kakao query, 장소 후보, Tavily query/검색 결과 신호를 추가 기록할 수 있으므로 개인정보/운영 로그 보관 정책과 별도로 점검하는 것이 좋다. 기본 preference analysis 로그는 사용자 원문/provider 답변을 직접 로그에 쓰지 않도록 안전한 범주·스키마 오류만 남긴다.

## 11. 확인 가능한 한계와 해석 주의

1. Kakao query 결과는 실제 장소 후보이고 Tavily는 웹 근거를 보충하지만, 웹 문서가 없거나 장소명/지역/전화 identity를 맞추지 못하면 A급이 되지 않는다. 이런 경우 subtype/category 반복 근거가 있을 때만 B로 살아남을 수 있다.
2. Kakao category metadata가 빈약하면 장소가 실제로 적절해 보여도 `CONFIRMED`를 못 받아 제외될 수 있다. 특히 범용 category path만 제공되는 장소는 보수적으로 빠질 수 있다.
3. 웹 검색 term의 가까운 동의어는 작고 고정된 집합만 허용한다. 거짓 근거를 줄이는 대신 의미가 통하는데도 단어가 달라 검증에 실패할 수 있다.
4. 최대 12회 Kakao 검색, 6개 Tavily 후보/호출, 50 Kakao candidate cap 때문에 검색 영역 전체를 완전히 나열하는 것이 아니다. 우선순위와 예산 안에서 적격 추천을 찾는다.
5. 지역 자동 선택은 기록 주소의 빈도에 의존한다. 주소 입력이 잘못됐거나 과거 방문지가 현재 원하는 추천 지역과 다르면 API의 `region`을 직접 줘야 의도와 일치한다. 현 Flutter 호출이 지역을 생략하면 서버 inferred region을 따른다.
6. A/B 점수는 고정된 확률이나 사용자 취향의 통계적 확률이 아니다. evidence grade를 거친 뒤 후보를 정렬하는 규칙 점수다.
7. 이번 문서는 정적 코드 분석이다. 외부 API에서 현재 어떤 결과가 나오는지, 운영 환경의 `.env`에서 어떤 모델이 설정되어 있는지, 실제 기록 한 건에서 어떤 query가 생성되는지는 확인하지 않았다.

## 12. 주요 코드 위치 빠른 참조

- API / 세션 / 분석·검색 호출: `overlap/backend-fastapi/app/ai_recommendations.py`
- 기록 분석 schema, prompt, source evidence 검증: `overlap/backend-fastapi/app/record_preference_analysis.py`
- 검색어 생성, Kakao category classifier, Tavily 호출/identity/evidence: `overlap/backend-fastapi/app/place_candidate_search_service.py`
- Kakao Local 응답 mapping: `overlap/backend-fastapi/app/kakao.py`
- 실제 사용자 긍정 기록 및 방문 장소 조회: `overlap/backend-fastapi/app/recommendation_record_adapter.py`
- Flutter page cache/API: `overlap/frontend/lib/features/ai/services/ai_recommendations_api.dart`
- Flutter 추천 카드·다음 페이지·처음 페이지 replay: `overlap/frontend/lib/features/ai/screens/ai_recommendation_screen.dart`
