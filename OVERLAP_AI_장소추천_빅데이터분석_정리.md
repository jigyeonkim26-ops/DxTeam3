# OVERLAP AI 장소 추천 기능 분석 정리

> 작성 기준: 통합 테스트 브랜치 `test/overlap-reminder-integration-20261015`, 커밋 `880b43d8eb0201612cf0ca3959d15f67e42dfe90`의 최신 로컬 코드. AI 추천 파이프라인 버전은 코드의 `category-v6`이다.
>
> 이 문서는 코드·테스트에서 직접 확인한 사실과 확인되지 않은 실사용 자료를 구분한다. 현재 worktree에서는 테스트 계정의 최신 진단 JSONL, DB 조회 결과, 실제 추천 카드의 TOP3 상세를 찾지 못했다. 따라서 사용자 이메일, 실제 기록 문구, 추천 장소명·주소·점수는 임의로 기입하지 않았다. 팀원이 두 계정에서 각각 3개 카드가 보였다고 전한 내용은 사용자 제공 정보로만 기록한다.

## 1. 기능 개요

**기능명:** OVERLAP AI 개인화 장소 추천

사용자가 앱에 남긴 장소 기록 가운데 긍정 감정 기록을 바탕으로 선호 분야와 세부 취향을 구조화하고, Kakao Local에서 실제 장소 후보를 찾는다. 지역·장소 유형·방문 이력 등 필수 조건을 확인한 뒤 Tavily의 장소 특징 근거와 사용자 취향을 연결해 후보를 평가하고 최대 3곳을 응답한다.

**최신 코드 처리 흐름**

`사용자 인증 → 사용자 기록 및 방문 장소 식별 조회 → 긍정 기록 분석 → 선호 facet/category 구성 → 지역·취향 기반 검색어 생성 → Kakao 장소 후보 검색 → 지역·유형·방문·중복 검증 → Tavily 장소 동일성 및 특징 근거 확인 → A/B 개인화 평가 및 순위화 → 최대 3곳 응답 및 세션 저장`

A/B는 추천 근거 수준을 구분한다. 충분한 후보가 없으면 3곳을 채우지 않는다. 이미지 처리 기능은 추천 카드 표시를 위한 별도 서비스이며, 이 문서의 개인화 순위 산정 근거에는 포함하지 않는다.

## 2. 데이터 준비

### 2.1 데이터 정의

| 데이터 항목 | 출처 | 의미 | AI 추천에서의 활용 |
|---|---|---|---|
| 사용자 ID | 인증된 요청 및 DB | 요청 사용자 식별자 | 본인 기록 조회, 사용자별 분석·추천 세션 분리 |
| 기록 ID | Record DB | 기록 식별자 | LLM 분석 결과와 원 기록 facet을 연결 |
| 장소 ID / Kakao 장소 ID | Record·Place DB | 기록이 가리키는 내부 장소 및 외부 장소 식별자 | 방문 장소 제외, Kakao 후보 중복·동일성 연결 |
| 장소명 | Place DB | 기록에 연결된 장소명 | 분석 입력의 장소명·장소 유형 힌트, 방문 장소명 대조 |
| 주소 | Place DB | 도로명 주소 우선, 없으면 기존 주소 | 자동 추천 지역 추론 및 검색 지역 구성 |
| 위도·경도 | Place DB | 저장된 장소 좌표 | 기록 DTO에 포함. 후보 검색은 Kakao 후보 좌표를 사용 |
| 기록 내용(content) | Record DB | 사용자가 작성한 텍스트 | 취향 facet 및 근거 문구 분석 |
| 감정값(emotion) | Record DB | 기록의 감정 코드 | 긍정 기록 선별, 감정 강도 계산, facet polarity 검증 |
| 작성일(created_at) | Record DB | 기록 생성 시각 | 분석 입력 기록을 최신순 정렬하는 데 사용. 방문일로 해석하지 않음 |
| 선호 category | 분석 결과 | `food`, `bar`, `cafe`, `nature`, `activity`, `all` | 검색 의도와 Kakao 장소 유형 비교 |
| 선호 facet | LLM 분석 결과 | 대상(`target_kind`, `target_text`), 명시 특징, polarity, 근거, confidence | 검색어 생성 및 후보 특징 일치 검증 |
| Kakao 유형·주소·ID | Kakao Local 응답 | 실제 장소 검색 결과 메타데이터 | 후보 실재성, 지역 및 장소 유형 판정 |
| Tavily 검색 결과 | 외부 검색 API | 후보 장소에 관한 제목·본문·URL | 장소 동일성이 확인된 문서에서 기록 취향 특징을 검증 |

감정 선별은 DB 값 기준 `excellent`, `good`, `okay`이며 추천 DTO에서는 각각 `LOVE`, `LIKE`, `GOOD`으로 변환된다. 분석기의 긍정 감정 집합도 `LOVE`, `LIKE`, `GOOD`이다. 나머지 `neutral`, `disappointed`, `poor`는 취향 분석용 긍정 기록으로 조회하지 않는다. 단, 방문 장소 제외는 감정과 무관하게 해당 사용자의 전체 기록을 기준으로 한다.

### 2.2 데이터 획득 방법

| 데이터/서비스 | 획득 방법 | 사용 목적 | 실제 사용 여부 |
|---|---|---|---|
| OVERLAP 사용자 기록 | FastAPI가 인증 사용자 ID로 MySQL의 Record와 Place를 조회 | 긍정 취향 분석 및 방문 장소 제외 | 사용 |
| OpenRouter Chat Completions | 코드의 `https://openrouter.ai/api/v1/chat/completions` 호출 | 구조화된 기록 선호 분석 | category-v6 분석 경로에서 사용 |
| Kakao Local 키워드 검색 | 코드의 `https://dapi.kakao.com/v2/local/search/keyword.json` 호출 | 실제 장소 후보, Kakao 장소 ID, 카테고리, 주소·좌표 확보 | 사용 |
| Tavily Search | 코드의 `https://api.tavily.com/search` 호출 | 장소 동일성 및 구체 특징 추가 검증 | 후보가 있을 때 제한적으로 사용 |
| Flutter 앱 요청 | 인증된 `GET /ai/recommendations` 요청 | 사용자 선택 지역/추천 결과 표시 | 사용 |

공식 제품 문서: [OpenRouter API](https://openrouter.ai/docs/api-reference/overview), [Kakao Local API](https://developers.kakao.com/docs/latest/ko/local/dev-guide#search-by-keyword), [Tavily Search API](https://docs.tavily.com/documentation/api-reference/endpoint/search). 키 값은 문서화하지 않는다.

### 2.3 수집 데이터 예시

실제 A/B 사용자 기록 원문은 현재 worktree에 포함되어 있지 않고, 최신 DB를 읽기 전용으로 조회하지 않았다. 과거 로그를 최신 결과처럼 재사용하거나 기록 내용을 만들어내지 않기 위해 실제 기록 예시를 기입하지 않는다.

| 사용자 | 장소 | 감정 | 코멘트 |
|---|---|---|---|
| A 사용자(usera 계정) | 확인 필요 | 확인 필요 | 최신 DB/분석 trace 미확보 |
| A 사용자(usera 계정) | 확인 필요 | 확인 필요 | 최신 DB/분석 trace 미확보 |
| B 사용자(userb 계정) | 확인 필요 | 확인 필요 | 최신 DB/분석 trace 미확보 |

최종 산출문서에 실제 3~5건을 넣으려면 비밀값을 제외한 최신 테스트 trace에서 기록 ID별 장소·감정·비식별 처리된 코멘트와 분석 결과를 확보해야 한다. 이메일·토큰·연락처는 예시에도 포함하지 않는다.

## 3. 전처리

### 3.1 전처리 과정

1. 인증 사용자 ID로 긍정 감정 기록을 조회한다. Record와 Place를 외부 조인하고 작성일 및 기록 ID 내림차순으로 정렬한다.
2. 별도 조회로 같은 사용자의 전체 기록에 연결된 장소 ID·장소명을 가져와 이미 방문한 장소를 판별한다. 이 조회는 다른 사용자의 기록 내용을 추천 입력에 포함하지 않는다.
3. 외부 분석 전 DB 세션의 읽기 작업을 끝낸다. 현재 코드에서는 DTO를 구성한 뒤 `db.rollback()`을 호출하고 외부 LLM·검색 API를 진행한다.
4. 분석기에 전달할 기록은 최대 30건이다. 내용은 최대 500자, 장소명과 신뢰 카테고리 입력은 각각 최대 120자까지 제한된다.
5. LLM에 전달하는 텍스트에서는 URL·이메일·전화번호 패턴을 치환하고 공백을 정리한다. 이것은 일반적인 직접 식별자 패턴 정리이며, 모든 개인정보를 제거한다고 보장하지 않는다.
6. 감정 코드를 분석 모델의 enum으로 변환한다. 긍정 강도는 LOVE 1.0, LIKE 0.8, GOOD 0.6, NEUTRAL 0.35, DISAPPOINTED 0.2, BAD 0.0으로 정의되어 있다. 추천 입력 조회 단계에서 긍정 기록만 선택하므로 뒤 세 값은 분석 대상 긍정 DTO에 들어오지 않는다.
7. 모델 출력의 필수 필드와 category·facet 자료형을 Pydantic으로 검증한다. 명시적 원문 인용, 대상 키워드 및 긍·부정 polarity가 원 기록에 맞는지 다시 확인한다. 불명확한 장소 유형은 unknown으로 둘 수 있다.
8. 자동 지역은 저장 주소에서 추론하고, 요청에 지역이 명시되면 그 값을 사용한다. 자동 추론 지역에 한해서 후보 부족 시 도시 범위 확장을 허용한다.
9. 방문 장소는 사용자 ID 또는 장소명으로 후보와 비교한다. Kakao 후보는 Kakao ID 기준으로 중복 제거한다. 사용자 기록 자체를 중복 제거한다는 처리는 현재 코드에서 확인되지 않는다.

### 3.2 전처리 데이터 예시

아래는 **형식 설명용 가상 예시**이며 실제 A/B 기록이 아니다.

**원본 기록(가상)**

- 장소: `[저장된 장소명]`
- 감정: `good`
- 코멘트: `[사용자가 남긴 장소 경험]`

**분석 입력 형태(코드 기준)**

- 분석 대상 여부: `good`은 긍정 기록에 해당
- record_id: 원 기록 식별자
- place_name: 최대 120자, URL/이메일/전화번호 정리 후 전달
- place_type_hint: 코드가 판별한 장소 유형 또는 unknown
- trusted_category: 호출자가 신뢰 카테고리를 제공한 경우에만 값이 존재
- emotion: `LIKE`
- content: 식별자 패턴 정리, 공백 정리 후 최대 500자
- created_at: 정렬에 사용되며 방문일로 전달·추론하지 않음

## 4. 데이터 분석

### 4.1 데이터 분석 목표

긍정 기록에서 사용자가 좋아한 대상과 특징을 원문 근거와 연결해 구조화한다. 반복되는 분야 선호는 기록 수와 서로 다른 취향 대상의 폭을 함께 확인한다. 이 프로파일을 Kakao 장소 검색과 후보 순위화에 활용한다. 부정적으로 표현된 특징은 positive preference로 바꾸지 않는다.

### 4.2 데이터 분석 시나리오

| 단계 | 입력 | 처리 | 출력 |
|---|---|---|---|
| 사용자 기록 조회 | 인증 사용자 ID | 본인 긍정 기록 및 본인 전체 방문 장소 식별 조회 | 분석 DTO와 방문 ID/이름 집합 |
| 텍스트 정리 | 장소명·코멘트 | URL/이메일/전화번호 패턴 치환, 공백 정리, 길이 제한 | 제한된 분석 입력 |
| 기록 분석 | 최대 30개 입력 기록 | OpenRouter Chat Completions로 JSON 응답 요청 | record별 구조화 결과 |
| 분석 검증 | 모델 출력 및 원 기록 | 스키마, 원문 인용, 대상·특징의 존재, polarity를 검증 | 승인 facet 및 검증 상태 |
| 취향 프로파일 구성 | 승인된 record 분석 | category, place type, emotion intensity, facet, confidence 구성 | 검색·추천용 사용자 선호 |
| 지역 및 검색어 결정 | 요청 지역 또는 저장 주소와 선호 | 구체 facet query를 우선하고 유형·일반 검색어로 보완, 중복 제거·분야 간 순서 분산 | Kakao 검색어 목록 |
| Kakao 검색 | 검색어와 검색 지역 | 호출 예산 안에서 장소 검색 | ID·이름·주소·좌표·카테고리 후보 |
| 후보 필터링 | Kakao 후보와 사용자 기록 | 지역, 카테고리, 방문 여부, Kakao ID 중복 판정 | 기본 적격 후보 |
| Tavily 검증 | 후보, 지역, 원문 취향 용어 | 제한된 검색 결과에서 장소 동일성·특징·URL 검증 | 확인된 특징 근거 또는 미확인 상태 |
| 개인화 평가 | 후보 유형, 긍정 facet 및 Tavily 근거 | A/B 등급, 음성 취향 충돌, 점수 및 다양성 순위 계산 | 적격 후보 순위 |
| 최종 응답 | 순위 결과 | 최대 3곳 반환하고 다음 페이지용 세션 상태 저장 | 추천 장소와 근거 문구 |

### 4.3 선호 분석 항목

| 분석 항목 | 의미 | 추천에서의 활용 |
|---|---|---|
| `record_id` | 원 기록과 분석 결과 연결 키 | 같은 기록의 취향과 외부 근거를 연결 |
| `place_type` / `place_type_label` | 기록 장소 유형 또는 unknown | 기록 및 검색 문맥 구성, 명확하지 않으면 미분류 |
| `categories` | food, bar, cafe, nature, activity, all | 기록 취향과 후보의 분류 영역 비교 |
| `target_kind` | menu, drink, food, ambience, space, activity, scenery, service, facility, other | facet의 대상 성격 표시 |
| `target_text` | 원문에서 복사한 선호 대상 | 검색 query·태그·추천 이유의 기록 측 근거 |
| `features` | 코멘트에 명시된 대상 특징 목록 | Tavily로 확인할 후보 특징 |
| `polarity` | liked, disliked, neutral | 긍정 선호와 부정 충돌 구분 |
| `evidence` | 원문과 일치하는 짧은 인용 | 모델 추정이 아닌 원 기록 근거 검증 |
| `confidence` | 분석 facet 신뢰 점수(0~1) | 검색 및 ranking 가중치의 일부 |
| `emotion_intensity` | 감정 코드별 고정 강도 | 반복 선호 및 후보 가중치 계산 |
| `evidence_status` | verified, partial, unknown, unavailable | 분석의 사용 가능 상태 판정 |

분석 출력 스키마는 category/facets/features를 배열로 요구하며, target과 feature는 기록의 표현을 근거로 하도록 프롬프트한다. 코드에는 비상 시 제한된 literal fallback 용어표도 있다. 따라서 “모든 새로운 취향이 fallback에서도 동적으로 추출된다”고 쓰면 안 된다. 정상 Provider 분석은 목록에 고정되지 않은 표현도 모델이 분석할 수 있지만, API 실패 시 fallback의 인식 범위는 코드에 등록된 문자 표현과 문맥 판정으로 제한된다.

### 4.4 검색 Query 생성

검색기는 긍정 facet을 category별로 묶고 감정 강도·facet confidence·대상 종류에 따라 우선순위를 계산한다. 구체 대상 검색을 먼저 배치하고 동일 취향의 검색어는 중복 제거한다. 첫 검색 묶음에서 분야별 취향을 교차 배치하며, 결과가 충분하지 않으면 단순화·유형·분야 일반 검색어를 후속 검색에 사용한다.

- query 조합: 정규화된 검색 지역 + facet에서 얻은 구체 용어 + 장소 유형 문맥
- facet이 없는 경우: 검증된 place type과 그 분야 검색 문맥을 사용
- 검색 예산: Kakao 최대 12회, 첫 단계 최대 6회
- 확장: 명시 지역은 임의 확장하지 않고 자동 추론 지역만 도시 범위 확장 가능
- 실제 A/B에서 생성된 query 문자열: 현재 worktree에 최신 trace가 없어 **확인 필요**. 과거 로그·가상 문자열은 실제 테스트 query로 제시하지 않는다.

최종 문서에 실제 예를 넣을 때 필요한 자료는 같은 trace_id의 `generated_queries`, 분야별 query 집계 및 실행 query 익명 로그다. 현재 개인정보 안전 로그는 검색어 원문을 기록하지 않도록 설계되어 있어, 별도 안전한 테스트 로그가 없다면 실제 query 문자열은 확인 불가다.

### 4.5 후보 장소 검색 및 검증

- **실재성:** Kakao Local 후보의 장소 ID, 이름, 주소, 좌표, 장소 URL을 사용한다.
- **지역:** 후보의 Kakao 주소 행정구역을 요청/추론 지역과 비교한다. 위경도에 임의 사각형을 적용하지 않는다. 자동 추론 지역은 구 단위에서 시작하고 조건에 따라 도시의 다른 구로 넓힐 수 있다. 통합 시·도 이름이 같다는 이유만으로 먼 군 지역을 같은 도심으로 취급하지 않도록 주소의 구·군을 비교한다.
- **유형:** Kakao category group code와 category_name을 내부 category로 매핑한다. 요청 분야에 확인된 유형이 아니거나 mismatch/verification required인 후보는 최종 개인화 단계에서 제외될 수 있다.
- **방문·중복:** 본인 전체 기록의 Kakao 장소 ID 또는 장소명과 대조한다. Kakao ID를 기준으로 검색 결과 중복을 제거한다.
- **Tavily:** 후보명·검색지역·세부지역·기록 기반 용어를 사용해 결과를 찾는다. 제목/본문의 장소 동일성, 지역 및 특징 용어를 확인한다. 근거 URL의 유효성도 확인한다. 다른 장소를 다룬 검색 결과의 단어만으로 후보 특징을 확정하지 않는다.
- **근거 등급:** A는 확인된 후보 특징이 같은 원 기록의 긍정 facet과 연결된 경우다. B는 Tavily 특징을 확인하지 못해도 Kakao 세부 유형과 기록의 facet이 연결되거나, 반복적이고 폭이 있는 분야 선호가 충족된 경우다. 단순 광범위 업종 일치만으로는 B가 되지 않는다. C/미적격은 개인화 관련 근거가 없거나 필수 검증에서 제외되는 후보다.
- **분야 반복 선호 기준:** 같은 category의 검증 가능한 긍정 기록이 최소 3개이고, 서로 다른 facet 대상이 최소 2개이거나 구체 facet이 없는 긍정 기록이 최소 3개일 때 분야 선호를 인정한다. 이것은 특정 메뉴·시설을 주장하는 근거가 아니다.
- **호출 상한:** Kakao 12회, 후보 최대 50개(검색어별 최대 6개), Tavily 최대 6회·6후보를 코드에서 제한한다. 초기 Tavily 예산은 최대 3회·3후보다. 타임아웃은 Kakao 6초, Tavily 8초다. 실제 사용량은 후보 상황과 캐시에 따라 상한보다 작을 수 있다.
- **후보 부족:** 초기 탐색의 적격 추천이 3곳보다 적고 1차 Kakao 예산을 다 쓴 경우 남은 검색 예산으로 계속 탐색한다. 검증된 적격 후보가 부족하면 적은 수만 반환하거나 빈 결과를 반환한다.

### 4.6 Ranking 방식

점수는 확률이나 예측 정확도가 아니다. 소스 코드에 정의된 휴리스틱 적합 점수다.

| Ranking 요소 | 의미 | 순위에 미치는 영향 |
|---|---|---|
| 검증된 같은 기록 특징(A) | Tavily가 후보 장소에서 확인한 특징이 해당 기록의 같은 facet과 연결 | A 적격 후보. 감정 강도·facet confidence·서로 다른 기록 지원 수로 특징 기여 계산 |
| Kakao 세부 유형과 facet 연결(B) | Kakao의 구체 유형이 사용자의 긍정 facet 분야와 부합 | Tavily 성공이 아니어도 B 가능. 확인되지 않은 세부 특징은 문구에 넣지 않음 |
| 반복 category affinity(B) | 검증된 긍정 기록 3개 및 대상 다양성 또는 facet 없는 기록 조건 충족 | 해당 분야의 장소 유형 후보에 제한된 B 점수 제공 |
| 감정 강도·facet confidence | 기록 긍정 정도와 분석 facet confidence | 특징 및 유형 관련 가중치에 사용 |
| 명시적 부정 취향 충돌 | 사용자의 disliked facet과 후보의 확인된 구체 유형이 충돌 | hard exclusion |
| 검색 query 우선순위 | 취향 query 순서상 후보 발견 우선도 | 점수 동점/유사 시 보조 순위 기준 |
| 다양성 | 첫 3곳에서 이미 다룬 검증 취향과 다른 후보 | 점수 차가 0.04 이내일 때 다양성 우선 고려. category별 고정 배분은 없음 |

코드의 A 점수는 `min(1, 0.55 + min(0.35, feature_weight×0.12) + min(0.10, 지원 기록 수×0.025)` 형태다. 유형 근거 B와 반복 분야 affinity B는 별도의 낮은 범위로 계산된다. 점수 구성의 구체식은 코드 구현 세부값이며, 대외 산출물에서는 측정된 확률로 표현하지 않는다. 최초 페이지 최대 3곳, 내부 추천 세션은 별도 풀을 유지한다.

## 5. 데이터 분석 결과

### 5.1 A 사용자

| 항목 | 확인 결과 |
|---|---|
| 테스트 계정 | A 사용자: usera 계정(요청에서 제시한 usera 이메일 계정) |
| 전체 기록 수 | 최신 DB 조회 미실시 — 확인 필요 |
| 분석 대상·긍정 기록 수 | 최신 trace 미확보 — 확인 필요 |
| 주요 category / keyword / facet | 최신 분석 출력 미확보 — 확인 필요 |
| 주요 place type | 최신 분석 출력 미확보 — 확인 필요 |
| 생성 검색 query | 최신 trace 미확보 — 확인 필요 |
| 실제 추천 TOP3 이름·주소·category·순위 점수 | 카드 또는 응답 자료 미확보 — 확인 필요 |
| 추천 이유 | 실제 API 응답 근거 미확보 — 확인 필요 |
| 사용자 제공 테스트 결과 | 팀원이 최신 코드에서 3개 카드 표시를 확인했다고 전달함. 이 문서 작성 시점에 독립 검증할 로그는 없음 |

### 5.2 B 사용자

| 항목 | 확인 결과 |
|---|---|
| 테스트 계정 | B 사용자: userb 계정(요청에서 제시한 userb 이메일 계정) |
| 전체 기록 수 | 최신 DB 조회 미실시 — 확인 필요 |
| 분석 대상·긍정 기록 수 | 최신 trace 미확보 — 확인 필요 |
| 주요 category / keyword / facet | 최신 분석 출력 미확보 — 확인 필요 |
| 주요 place type | 최신 분석 출력 미확보 — 확인 필요 |
| 생성 검색 query | 최신 trace 미확보 — 확인 필요 |
| 실제 추천 TOP3 이름·주소·category·순위 점수 | 카드 또는 응답 자료 미확보 — 확인 필요 |
| 추천 이유 | 실제 API 응답 근거 미확보 — 확인 필요 |
| 사용자 제공 테스트 결과 | 팀원이 최신 코드에서 3개 카드 표시를 확인했다고 전달함. 이 문서 작성 시점에 독립 검증할 로그는 없음 |

실제 계정 상세를 완성하려면 개발 진단을 켠 상태에서 각 계정이 추천을 새로 요청한 뒤, 동일 요청의 `trace_id`와 앱에 표시된 카드 응답을 함께 확보해야 한다. 코드의 안전 진단 JSONL은 개인 식별자를 해시 처리하고 기록 원문·검색 query 원문을 저장하지 않으므로, 취향 원문 예시는 사용자가 승인한 별도 비식별 샘플에서 가져와야 한다.

### 5.3 A/B 비교

| 구분 | A 사용자 | B 사용자 |
|---|---|---|
| 전체 기록 수 | 확인 필요 | 확인 필요 |
| 긍정 기록 수 | 확인 필요 | 확인 필요 |
| 주요 취향·category | 최신 분석 trace 필요 | 최신 분석 trace 필요 |
| 주요 키워드/facet | 최신 분석 trace 필요 | 최신 분석 trace 필요 |
| 선호 장소 유형 | 최신 분석 trace 필요 | 최신 분석 trace 필요 |
| 추천 1~3위 | 실제 응답 카드 필요 | 실제 응답 카드 필요 |
| 카드 수 관련 사용자 제공 정보 | 3개 표시 확인 보고 | 3개 표시 확인 보고 |

두 사용자 모두 각각 3개 카드가 표시됐다는 전달 내용은 있으나, 장소·주소·근거가 다른지를 확인할 자료가 없어 “개인화 결과가 서로 달랐다”고 단정하지 않는다.

## 6. 모델 생성 및 학습

### 6.1 모델링 목표

사용자의 장소 기록을 사전학습 LLM API로 분석해 추천에 필요한 category, 장소 유형, 취향 facet, polarity 및 원문 근거를 구조화한다. 분석 결과는 Kakao 장소 검색과 개인화 순위 계산에 사용한다.

### 6.2 사용 모델

| 항목 | 확인 결과 |
|---|---|
| Provider | 코드 기본값 `openrouter`; 원본 작업 폴더의 로컬 설정도 `openrouter` |
| Model | 코드 기본값은 `dots-studio/dots-3-note-preview:free`; 원본 작업 폴더의 로컬 설정은 `google/gemini-3.1-flash-lite` |
| API 방식 | OpenRouter Chat Completions HTTP API |
| 설정 확인 범위 | 통합 worktree에는 `.env`가 없음. 원본 작업 폴더에서는 비밀값을 제외하고 Provider/Model 이름만 확인 |
| 실제 배포 운영 모델 | 원본 로컬 설정과 같다고 단정할 수 없음 — 배포 설정 확인 필요 |

모델 기본값은 `app/config.py`에 있다. API 키는 문서화하지 않는다. 다른 OpenRouter 보조/호환 서비스 코드에도 같은 config 값을 참조하는 구 경로가 남아 있으나, 기본 AI 추천 endpoint는 category-v6 기록 분석 서비스를 사용한다.

### 6.3 학습 방법

- 자체 모델 생성 없음
- 자체 모델 학습 없음
- Fine-tuning 없음
- 별도 학습 데이터셋 구축 없음
- 사전학습 LLM을 API로 사용
- 사용자 기록을 inference 입력으로 사용
- prompt 및 구조화 JSON 스키마에 따라 분석값 반환
- epoch, loss, optimizer, train/validation split 없음

### 6.4 모델 출력 결과

실제 계정 원문/응답을 확보하지 못했으므로 실제 결과 예시를 만들지 않는다. 코드 스키마의 출력 형태는 다음과 같다.

```json
{
  "record_id": 0,
  "place_type": "unknown",
  "place_type_label": null,
  "place_type_evidence": null,
  "categories": [],
  "facets": [
    {
      "target_kind": "other",
      "target_text": "[원문에서 복사한 대상]",
      "features": ["[원문에 명시된 특징]"],
      "categories": ["all"],
      "polarity": "liked",
      "evidence": "[입력 원문에 존재하는 짧은 근거]",
      "confidence": 0.0
    }
  ]
}
```

위 JSON은 필드 형태를 설명하기 위한 스키마 예시이며 실제 모델 출력·실제 추천 데이터가 아니다. 실제 산출물의 “모델 분석 결과 예시”에는 비식별 처리된 최신 trace를 사용해야 한다.

## 7. 검증

### 7.1 분석 검증 방안

- OpenRouter 응답 JSON과 Pydantic 구조 검증
- 모델의 target, feature, evidence가 입력 기록에 실제 존재하는지 확인
- positive/negative polarity와 기록 감정의 일관성 확인
- category/place type unknown 허용 및 Kakao 카테고리 대조
- Kakao 후보 ID·주소·좌표·유형·지역 및 방문 장소 필터 검사
- Tavily 결과의 장소 동일성, 지역 및 취향 특징·URL 확인
- A/B 근거 등급, 사용자 취향 연결 및 최종 최대 3개 제한 테스트
- 지역 별칭·도시 확장·검색 예산·빈 결과·세션 테스트
- 외부 API 대신 Mock을 사용하는 단위/통합 테스트

실사용 A/B 계정에 대한 최신 로그 및 추천 카드 비교는 확인되지 않았다. Kakao/Tavily 실제 API 사용 여부와 두 사용자의 응답시간도 이번 작업에서 실측하지 않았다.

### 7.2 분석 평가 결과

| 평가 항목 | 측정 방법 | 확인된 결과 |
|---|---|---|
| 백엔드 추천·검색·분석 집중 회귀 | Mock 중심 관련 테스트 실행 | 62 passed |
| 백엔드 통합 전체 | 전체 pytest 실행 | 399 passed, 11 failed. 실패 11개는 AI 원본 브랜치에서도 같은 테스트와 오류로 재현된 기존 실패로 확인 |
| Flutter 전체 테스트 | 통합 worktree에서 실행 | 156 passed |
| Flutter analyze | 통합 Flutter 프로젝트 analyze | 이전 통합 검증에서 문제없음. 이번 문서 작성 중 재실행은 무출력 대기로 중단 |
| A 사용자 최신 TOP3 | 최신 응답/앱 캡처 대조 | 팀원 전달은 3개 표시. 장소 상세·trace 독립 확인 필요 |
| B 사용자 최신 TOP3 | 최신 응답/앱 캡처 대조 | 팀원 전달은 3개 표시. 장소 상세·trace 독립 확인 필요 |
| 장소 실재·지역 적합성 | 최신 A/B Kakao 상세/응답 대조 | 최신 두 계정 결과는 자료 미확보 — 확인 필요 |
| 실제 모델 provider/model | 배포 설정 조회 | 로컬 코드 기본값은 확인. 배포 환경 적용값은 확인 필요 |
| 정확도·정량 성능 | 실제 정답 라벨/표본 측정 | 수행 자료 없음. 정확도 퍼센트 산출 불가 |

11개 기존 백엔드 실패는 통합 신규 회귀로 보고하지 않는다. 전체 테스트는 완전 통과가 아니므로 산출문서에도 `399 passed, 11 failed (동일 실패가 원본 브랜치에서도 재현)`로 정확히 표기한다.

## 8. 기술 구성

| 역할 | 기술/API | 사용 목적 |
|---|---|---|
| API 서버 | FastAPI | 인증된 AI 추천 endpoint 제공 |
| ORM/DB | SQLAlchemy / MySQL | 사용자 기록·장소 조회 |
| 구조화 선호 분석 | OpenRouter Chat Completions | 기록 텍스트를 분석 필드로 변환 |
| 실제 장소 검색 | Kakao Local 키워드 검색 API | 장소 ID·주소·좌표·카테고리 후보 확보 |
| 외부 장소 근거 보강 | Tavily Search API | 후보 동일성 및 구체 특징 근거 확인 |
| 데이터 검증 | Pydantic | LLM 및 API 데이터 형식 검증 |
| 진단 | 개발환경 opt-in JSONL | trace, 단계 시간, 후보 판정 코드 기록 |

기술 버전은 의존성 파일에 선언된 범위와 버전 고정 항목에 따른다. 서버·DB의 실제 배포 버전은 현재 자료에서 확인되지 않는다.

## 9. 예외 및 Fallback 처리

| 상황 | 현재 코드에서 확인되는 동작 |
|---|---|
| 긍정 기록 없음 | 빈 추천 응답과 empty session 상태 반환 |
| LLM 키/모델 설정 없음 | literal fallback 기반 분석 객체는 만들지만 evidence status를 unavailable로 표시 |
| LLM HTTP/JSON/스키마/근거 오류 | 정상 Provider 분석으로 취급하지 않고 local base 결과를 unavailable 상태로 반환. 재시도는 코드 경로별 예외 처리에 따름 |
| 일부 모델 기록만 유효 | 레코드 ID와 필드 검증을 수행하고 정상 검증된 기록 분석을 보존 |
| Kakao 설정/호출 실패 | provider unavailable/error 진단. Kakao 자체 이용 불가 시 endpoint 503 처리 |
| Kakao 정상 빈 검색 | 후보 없음으로 처리하고 후속 검색 예산이 남으면 이어서 탐색 |
| 지역 불일치 | 주소 기반 지역 필터에서 제외. 명시 지역은 자동 확장하지 않음 |
| category 미확인/mismatch | final category gate에서 제외 |
| 이미 방문한 장소 | 사용자 전체 기록의 Kakao 장소 ID 또는 장소명 기준으로 제외 |
| Tavily 미설정·오류·시간 초과 | 특징 evidence를 unavailable/미확인으로 기록. 그 자체로 사실 주장을 허용하지 않음. 별도 Kakao 유형/반복 분야 근거로 B 자격이 있으면 평가 가능 |
| 장소 동일성 실패 | 특징 근거를 해당 후보의 근거로 연결하지 않음 |
| 적격 후보 부족 | 확보한 1~2곳만 반환하거나 0곳 반환. 3곳 강제 충원 없음 |
| 빈 추천 세션 재요청 | 코드에 짧은 cooldown 및 제한된 empty retry 수 설정 |
| 추천 캐시 | 세션과 분석 캐시는 프로세스 내 제한 크기·TTL을 두고 사용자 및 기록 fingerprint로 분리 |
| 진단 로그 | development 및 opt-in 설정에서만 JSONL 작성. trace·익명 사용자 식별자·수치/판정코드를 기록하고 원문 코멘트·검색어·API 키는 기록하지 않도록 구성 |

현재 로컬 진단 파일 경로 기본값은 backend의 `logs/ai_recommendation_diagnostics.jsonl`이며 `OVERLAP_AI_DIAGNOSTICS_FILE`로 경로를 지정할 수 있다. 이 파일은 환경에 따라 민감한 운영 정보를 다루지 않도록 접근을 제한해야 한다.

## 10. 최종 빅데이터 분석 정의서 요약표

| 빅데이터 분석 정의서 항목 | OVERLAP 작성 내용 |
|---|---|
| 기능명 | OVERLAP AI 개인화 장소 추천 |
| 데이터 정의 | 인증 사용자 본인의 긍정 기록(장소명·주소·코멘트·감정·작성일 등), 장소 메타데이터, 모델이 원문 근거로 구조화한 category/facet, Kakao 및 Tavily 후보 데이터 |
| 데이터 획득 방법 | 앱 작성 기록을 MySQL에서 읽고, OpenRouter로 텍스트 분석, Kakao Local API로 실제 장소 검색, Tavily Search API로 후보 특징 근거 확인 |
| 수집 데이터 | 사용자/기록 ID, 장소명·주소·좌표, 코멘트, 감정 코드·강도, 작성일 정렬값, category, facet 대상·특징·polarity·evidence·confidence, Kakao ID/카테고리/주소/좌표, Tavily 근거 상태 |
| 전처리 과정 | 사용자별 조회, 긍정 감정 필터, 최신순 정렬, 최대 30건 분석, URL/이메일/전화번호 패턴 치환, 공백 정리, 코멘트 최대 500자·장소명/카테고리 최대 120자 제한, 감정코드 변환, 방문 장소 식별 별도 조회 |
| 전처리 데이터 | LLM 입력 record_id, 제한된 장소명/코멘트, place_type_hint, 선택적 trusted_category, emotion. 주소는 지역 추론 및 검색에 활용 |
| 데이터 분석 목표 | 긍정·부정 경험의 실제 원문 근거에서 개인 취향 분야와 세부 facet을 구조화해 장소 검색 및 개인화 ranking에 활용 |
| 데이터 분석 시나리오 | 기록 조회 → 전처리 → LLM 구조화 분석 → 원문 근거 검증 → query 생성 → Kakao 후보 검색 → 지역/유형/방문 필터 → Tavily 동일성·특징 검증 → A/B 점수와 다양성 ranking → 최대 3곳 응답 |
| 데이터 분석 결과 | A/B 각 3개 카드가 표시됐다는 팀원 제공 요약은 있음. 최신 TOP3 상세·분석 결과·실제 DB 기록 및 trace는 미확보이므로 수치·장소는 확인 필요 |
| 모델링 목표 | 사전학습 LLM을 이용해 장소 기록의 category·place type·선호 facet·polarity·근거를 구조화 |
| 학습 모델 | 자체 모델 생성·학습 없음. Provider는 OpenRouter. 코드 기본 모델은 `dots-studio/dots-3-note-preview:free`, 원본 작업 폴더의 로컬 `.env` 설정 모델은 `google/gemini-3.1-flash-lite`; 실제 배포 설정값은 확인 필요 |
| 학습 방법 | Fine-tuning·학습 데이터셋 없음. Prompt 기반 API inference. epoch/loss/train-validation split 없음 |
| 모델 예측 결과 | record_id별 category, place_type, target_kind, target_text, features, polarity, evidence, confidence, emotion_intensity 구조. 실제 계정 모델 출력 예시는 최신 trace 확보 후 삽입 |
| 분석 검증 방안 | Pydantic 스키마 및 원문 근거 검증, Kakao 장소/지역/유형/방문 필터, Tavily 장소 동일성·특징·URL 확인, Mock 회귀 테스트 |
| 분석 평가 결과 | 백엔드 관련 집중 테스트 62 passed. 전체 백엔드 399 passed/11 기존 실패(원본 브랜치 동일 재현). Flutter 156 passed. Flutter analyze는 이전 검증에서 문제없음. A/B 최신 응답 독립 검증과 정확도 정량 평가는 확인 필요 |
