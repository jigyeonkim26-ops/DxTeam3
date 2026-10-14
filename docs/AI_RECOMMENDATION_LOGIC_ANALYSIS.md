# OVERLAP AI 장소 추천 로직 분석

> 분석 범위: 현재 작업 트리의 FastAPI 추천 파이프라인과 Flutter 추천 화면을 코드 기준으로 추적했다. 테스트 결과나 실제 OpenRouter·Tavily·Kakao 계정 호출 결과를 새로 검증한 문서는 아니다. 작업 트리에는 기존 미커밋 변경이 포함되어 있으므로, 아래 내용은 그 변경을 포함한 현재 파일 상태를 설명한다.

## 1. 요약

OVERLAP의 추천 기능은 사용자 기록에서 선호를 추론하고 장소를 새로 생성하는 방식이 아니다. 긍정 감정 기록을 입력으로 OpenRouter가 선호 키워드를 추출하고, Tavily가 장소 후보와 설명을 수집한다. Kakao Local로 실제 장소 ID·주소·좌표를 확인한 뒤, 결정론적 근거 필터를 통과한 장소만 OpenRouter에 순위화를 맡긴다. LLM 응답은 후보 ID와 키워드 근거를 다시 검증하며, 출력이 비거나 걸러지면 근거 기반 fallback을 사용한다. 최종 응답은 최대 3곳이고, 기록 사진 또는 Daum 블로그 검색 이미지를 선택적으로 붙인다.

```text
인증 사용자
  → 긍정 기록 DB 조회 및 DTO 변환
  → OpenRouter 선호 키워드 추출 (실패 시 빈도 기반 fallback)
  → Tavily 장소 후보/설명 검색 (최대 후보 10)
  → Kakao Local 장소 실재성·지역·방문 여부 검증 (요청 최대 6회)
  → 근거 기반 적합성 판정 및 중복 제거 (상위 입력 최대 10)
  → OpenRouter 순위화 및 응답 검증
      ↘ 결과 부족/비정상 → 이미 검증된 장소만 근거 기반 fallback
  → 프로세스 메모리 세션에서 최대 3곳 반환
  → 접근 가능한 기록 사진 우선, 없으면 외부 이미지 보강
```

## 2. 진입점과 입력 데이터

### API와 인증

- 엔드포인트는 `GET /ai/recommendations`이며 인증된 `current_user`와 DB 세션을 사용한다. 라우터 연결은 `overlap/backend-fastapi/app/main.py`, 처리 흐름은 `overlap/backend-fastapi/app/ai_recommendations.py`에 있다.
- 사용자 ID는 요청 파라미터가 아니라 인증 사용자 객체에서 가져온다. 기록 조회는 해당 사용자 ID에 한정된다.
- 쿼리 파라미터로 `exclude_place_ids`, `previous_place_ids`, `refresh`가 선언돼 있다. 현재 구현은 앞의 두 파라미터를 읽지 않는다. `refresh`는 캐시된 후보 풀에서 다음 페이지를 보여주는 용도다.

### 추천에 사용하는 기록

`RecordRecommendationAdapter`는 Record와 Place를 외부 조인하고 `excellent`, `good`, `okay` 감정 기록만 가져온다. 최신 `created_at`, `id` 우선으로 정렬한다. 기록의 본문, 장소명/주소/좌표, Kakao 외부 ID, 감정 정보를 추천 DTO에 복사한다. `visited_on`은 현재 DB에 방문일 컬럼이 없으므로 비워 둔다.

기록 조회 직후 라우터는 `db.rollback()`을 호출해 읽기 트랜잭션을 끝낸다. 외부 API 호출 동안 DB 커넥션을 점유하지 않도록 한 설계다. 기록이 없으면 공급자 API를 호출하지 않고 빈 `recommendations`를 반환한다.

## 3. 단계별 상세 동작

### 3.1 선호 키워드 추출

`OpenRouterPreferenceKeywordService`는 기록의 본문, 감정 코드/표현, 장소명을 OpenRouter에 전달하고 장소 분위기·환경·활동에 관한 선호를 최대 5개 추출하도록 요청한다. 점수 범위는 0~1이며 JSON Schema 형식과 `temperature=0`을 사용한다. 반환값은 DTO 검증, 중복 제거, 점수 내림차순 정렬을 거친다. 기록 장소명과 완전히 일치하는 키워드는 제외한다.

OpenRouter 호출/응답 파싱 실패는 즉시 API 오류가 되지 않는다. 기록 본문을 토큰화해 장소명 토큰과 일부 감정 표현을 제외하고 빈도 상위 최대 5개를 만드는 fallback을 시도한다. 이 fallback은 빈도만 반영하며 의미를 이해하거나 동의어를 병합하지 않는다. 설정 누락은 `AIConfigurationError`로 처리되어 503이 된다.

### 3.2 Tavily 후보 검색

`TavilyPlaceSearchService`는 기록 주소 중 첫 번째 주소의 첫 토큰을 검색 위치로 택하고 키워드 점수 상위 항목으로 최대 3개의 질의를 만든다. 검색당 결과 상한은 10이며, 전체 후보는 중복 장소명 및 이미 기록된 장소명을 제외하고 최대 10개다. 각 후보에는 Tavily 결과의 제목에서 정리한 장소명, `content` 요약(최대 500자), 출처 URL, 문자열 기반 초기 키워드 일치가 들어간다. 주소·좌표·Kakao ID는 아직 없다.

후보 제목/내용이 충분하지 않거나 검색 응답이 올바르지 않으면 후보에서 제외하거나 공급자 응답 오류로 처리한다. HTTP 호출은 검색별 15초 timeout이다.

### 3.3 Kakao Local 검증

`KakaoPlaceVerificationService`는 사용자 기록 주소에서 지역을 추론하고, 기록에 있는 Kakao 장소 ID/장소명을 방문 장소로 수집한다. 먼저 Tavily 힌트 최대 10개를 지역과 정리된 장소명으로 Kakao 검색한다. 힌트 결과가 3곳 미만이면 선호 키워드 기반 보완 검색을 한다. 전체 Kakao 요청은 최대 6회로 제한된다.

검증 단계는 다음을 확인한다.

- Kakao 장소 ID가 숫자 문자열인지, 이름·주소·URL이 존재하는지, 좌표가 유효 범위인지
- 주소 지역이 추론한 사용자 지역과 일치하는지
- 사용자가 이미 기록한 장소 ID 또는 지역 접두어를 제거한 장소명과 중복인지
- Tavily 힌트로 검색한 경우 Kakao 장소명이 정리된 힌트 장소명과 일치하는지
- 후보 ID/검색 질의 중복 여부

검증 장소에는 Kakao의 ID·이름·주소·좌표·장소 URL이 채워진다. Tavily 힌트로 확인한 장소는 Tavily 설명을 보존하지만, 키워드 기반 Kakao 보완 검색은 주로 Kakao 카테고리 텍스트를 설명 근거로 갖는다. Kakao API 실패는 추천 전체에 502를 반환한다. 지역 또는 키워드 입력을 도출할 수 없으면 빈 후보 목록이 된다.

### 3.4 결정론적 적합성 필터

`ai_recommendations.py`의 `_supported_preference_terms`, `_preference_evidence_score`, `_filter_suitable_candidates`가 LLM 순위화 전 안전 필터를 수행한다.

- 선호 용어의 일부 개념 그룹(예: 노을, 산책, 전망)은 사전 정의된 표현 집합과 비교한다.
- 일부 전망/노을 선호에는 장소 유형과 설명 단서가 함께 있을 때 의미적 근거로 인정하는 특례가 있다.
- 후보 이름 또는 제공된 설명에 근거가 있어야 선호를 지원한다고 본다.
- 선호 중요도 점수와 설명에 나타난 근거를 고정식으로 조합하고 0.18 이상만 통과시킨다. 이 점수는 확률이 아니며 OpenRouter의 점수와 별개다.
- ID가 없거나 이름·주소·좌표가 불완전한 후보와 ID 중복도 제거한다.

즉, Kakao에 등록돼 있다는 사실만으로는 추천되지 않는다. 다만 현재 사전 개념군이 한정되어 있어 그 밖의 한국어 표현/동의어는 실제로 관련 있는 장소도 탈락시킬 수 있다.

### 3.5 OpenRouter 순위화와 출력 검증

최대 10개의 적합 후보와 선호, 긍정 기록 내용을 OpenRouter에 보내 후보 ID만 순위화하도록 한다. 이름·주소·좌표는 서버가 검증한 후보에서 복사하므로 LLM이 장소 정보를 새로 만들 수 없다. JSON Schema 검증 및 다음 서버 검증을 수행한다.

- 추천 ID가 제공 후보 목록 안에 있는지
- 반환 키워드가 실제 입력 선호 라벨인지
- 추천 모델의 점수, 필수 필드, ID 중복이 유효한지
- 라우터에서 해당 후보의 근거로 뒷받침되는 키워드만 남기고, 근거 없는 항목/빈 매칭 항목은 제거

OpenRouter 순위화 결과가 비어 있거나 구조 오류인 경우, 이미 Kakao 검증 및 결정론적 적합성 필터를 통과한 후보에 한해 fallback을 만든다. fallback은 근거 점수로 정렬하고 기록에서 확인된 선호 및 후보 설명을 이유 문구에 포함한다. 최종 적합 후보 풀은 최대 10개, 한 번의 응답은 앞에서부터 최대 3개다.

### 3.6 세션 캐시와 새 추천 동작

라우터 내부 `OrderedDict`가 사용자 ID와 긍정 기록 DTO fingerprint(SHA-256)를 키로 20분간 결과 풀을 보관한다. fingerprint가 바뀌면 해당 사용자의 오래된 세션을 제거한다. 최대 128개 세션을 유지하며 오래된 세션부터 제거한다. 빈 추천 결과는 캐시에 저장하지 않아 재시도할 수 있다.

- 첫 요청은 원래 상위 3개를 반환하고, 해당 ID를 이미 보인 것으로 기록한다.
- `refresh=true` 요청은 아직 보여주지 않은 캐시 풀의 다음 최대 3개를 반환한다.
- 후보 풀이 소진되면 원래 상위 3개로 돌아간다.
- Flutter API는 같은 인스턴스에서 진행 중인 요청을 합치고, 첫 성공 이후 재요청에 `refresh=true`를 붙인다.

여기서 “다른 장소 추천”은 새 검색/새 순위화를 요청하지 않는다. 기존 후보 풀에서 페이지를 교체한다. 캐시는 서버 프로세스 메모리 전용이므로 서버 재시작 시 사라지고, 다중 worker에서는 worker별로 달라질 수 있다.

### 3.7 이미지 보강

`RecommendationImageService`는 추천 순위나 장소 데이터를 바꾸지 않고 이미지 필드만 붙인다.

1. 현재 사용자가 볼 수 있는 기록 중 같은 Kakao 장소 ID의 사진을 우선 사용한다.
2. 기록 사진이 없으면 Kakao Daum 블로그 검색을 실행한다. 결과 제목/내용에 정확한 장소명이 포함되고 주소 지역 신호도 확인되며 이미지 URL이 허용되는 경우만 채택한다.
3. 이미지는 1시간 캐시, 검색 실패/미스는 1분 캐시다. 동시 외부 검색은 최대 3개, 검색 timeout은 2.5초다.
4. 적합한 이미지가 없으면 placeholder로 둔다.

이미지 조회 전 DB 트랜잭션을 rollback해 외부 검색 중 커넥션을 붙들지 않는다. 이미지 서비스 예외는 추천 API 성공을 막지 않고 생략된다.

### 3.8 Flutter 화면

`AiRecommendationsApi`가 `GET /ai/recommendations`를 호출하고 응답 JSON을 `AiPlaceRecommendation`으로 변환한다. 외부 공급자 순차 호출을 고려해 클라이언트 응답 timeout은 180초다. 화면은 로딩·오류·빈 결과·추천 카드 상태를 나누고, 재추천 버튼을 제공한다. 추천 카드 탭은 Kakao ID와 좌표가 있는 경우 지도/장소 상세 흐름으로 연결된다. 이미지 URL이 없거나 로딩에 실패하면 카드 placeholder를 표시한다.

## 4. 실패 처리 요약

| 단계 | 동작 |
|---|---|
| 긍정 기록 없음 | 외부 호출 없이 빈 200 응답 |
| OpenRouter 키워드 호출/파싱 실패 | 빈도 기반 키워드 fallback 시도 |
| 키워드 없음 | 빈 200 응답 |
| Tavily/Kakao 설정 누락 | 503 |
| Tavily/Kakao 요청 또는 응답 오류 | 502 |
| Kakao 검증 후 적합 후보 없음 | 빈 200 응답 |
| OpenRouter 순위 응답 오류/형식 문제 | 검증 통과 후보로 evidence fallback |
| 외부 이미지 실패/미발견 | 추천은 유지하고 placeholder 이미지 |

## 5. 발견한 문제점과 개선 제안

### 우선순위 높음

1. **추천 입력에 개인 기록 본문을 외부 LLM으로 전송한다.** 키워드 추출과 순위화 payload에 사용자의 기록 본문이 포함된다. 기록에는 민감한 개인 경험이 담길 수 있다. 전송 전 개인정보 최소화/비식별 처리, 사용자 고지·동의, 보관/학습 사용 조건 확인, 실제 필요한 요약만 전달하는 방안을 제품·정책과 함께 정해야 한다.
2. **OpenRouter가 만든 점수의 기준이 보정되어 있지 않다.** 점수 범위와 출력 DTO는 검증하지만, 점수가 사용자/요청 간 동일한 관련성 의미를 갖는지는 보장되지 않는다. 점수는 순위화 내부 신호로만 취급하고, 일정 기간 추천 클릭·저장·숨김 결과와 비교해 캘리브레이션하거나 결정론적 근거 점수와 결합하는 것이 좋다.
3. **지역 선택이 첫 기록에 의존한다.** Adapter는 최신순이지만, Tavily 및 Kakao 지역 선택은 사실상 첫 기록 주소를 사용한다. 사용자가 여러 지역에서 기록했거나 최근 기록이 여행지라면 개인화 기준과 실제 추천 지역이 엇갈릴 수 있다. 최근 N개 기록의 지역 분포·사용자 현재 위치·명시적 지역 선택을 반영하고, 지역 불확실 시 재질문/대체 정책을 두는 것이 좋다.
4. **캐시가 다중 worker 환경에서 일관되지 않는다.** 세션 캐시가 프로세스 메모리에 있으므로 요청이 다른 worker로 라우팅되면 refresh가 새 추천 생성으로 이어지거나 페이지 순서가 바뀔 수 있다. Redis/DB 기반 공용 캐시와 원자적인 페이지 상태 갱신을 적용하거나, API 의미를 명확히 해 클라이언트가 cursor를 전달하도록 바꾸는 것이 좋다.

### 우선순위 중간

5. **‘다른 장소 추천’이 새 추천 생성처럼 보이지만 실제로는 캐시 풀 순환이다.** 사용자에게 새 검색/재생성인지 다음 후보 보기인지 문구를 맞추고, 실제 새 생성을 원한다면 명시적 refresh 동작과 별도 rate limit을 추가해야 한다.
6. **`exclude_place_ids`와 `previous_place_ids`가 사용되지 않는다.** API 시그니처에 남아 있어 클라이언트가 제외가 적용된다고 오해할 수 있다. 제거하거나 실제 후보 필터링/커서 로직과 연결하고, 이름·ID 기준 동작을 문서화해야 한다.
7. **근거 점수와 사전 개념 목록은 확장성·설명력에 한계가 있다.** 새 선호어가 고정 개념군 밖에 있으면 보수적으로 후보가 전부 탈락할 수 있다. 사전을 설정 데이터로 분리하고, 사용자 로그 기반 false positive/negative 평가셋과 단계별 통과율을 운영해 임계값/동의어를 개선하는 것이 좋다.
8. **LLM 키워드 실패 fallback은 의미 품질이 약하다.** 토큰 빈도는 조사/일반 명사·문장 조각을 선호로 오인할 수 있고, 한글 형태소 단위 처리를 하지 않는다. 빈도 fallback을 검색에 바로 투입하기 전에 최소 빈도·불용어·품사/구문 정리, 또는 로컬 규칙·검증된 별도 추출기를 적용하는 것이 좋다.
9. **후보와 기록 수에 명시적 입력 한도가 없다.** DB의 긍정 기록이 많으면 매 호출마다 기록 전체를 LLM payload에 넣어 토큰 비용·지연·개인정보 노출이 커진다. 최근 N건 제한, 텍스트 길이 제한, 중복/유사 기록 요약, 입력 토큰 예산을 도입하는 편이 낫다.
10. **타임아웃과 사용자 대기 시간이 길 수 있다.** 클라이언트 timeout 180초이며 서버는 OpenRouter 키워드 최대 30초, Tavily 최대 3회×15초, Kakao 여러 회 호출, OpenRouter 순위 최대 45초를 순차 실행할 수 있다. 실제 누적 시간/각 단계 분포를 측정하고, 총 요청 deadline, 병렬화 가능한 검색, 비동기 작업 또는 진행 상태 UX를 설계해야 한다.
11. **Kakao 보완 후보 설명은 빈약할 수 있다.** 검색 힌트 없이 Kakao 키워드 보완 검색으로 얻은 장소는 카테고리 정도의 짧은 설명만 가질 수 있다. 근거 필터가 일부 거를 수 있지만, 출처 설명이 얕은 후보의 이유 문구 품질은 제한적이다. 추가적인 1차 출처를 확인하거나 저근거 후보를 명시적으로 낮은 우선순위로 처리해야 한다.
12. **한 번의 오류가 단계 전체 실패로 전파된다.** Tavily/Kakao 후보를 이미 얻었어도 공급자 오류가 발생하면 전체 요청이 502가 된다. 단계별 부분 성공을 어디까지 허용할지 정의하고, 검색 응답 일부 실패/재시도/회로 차단을 적용하면 가용성이 좋아질 수 있다.

### 운영·관측 개선

13. **현재 진단 로그는 단계별 개수 중심이다.** 개인 기록 전문이나 provider payload를 기록하지 않는 점은 안전하지만, request correlation ID, 단계별 latency, 재시도 횟수, 후보 탈락 사유별 비율, 캐시 hit/miss를 구조화해 연결하면 문제 분석이 쉬워진다. 사용자 식별자는 로그에 직접 남기지 말고 필요 시 회전 가능한 해시를 사용한다.
14. **캐시 키 fingerprint 범위를 명확히 해야 한다.** fingerprint는 adapter DTO 전체를 해시하므로 기록의 생성시각 등 추천 결과에 의미 없는 값 변화도 캐시 무효화를 유발할 수 있다. 실제 추천 입력에 쓰는 필드만 포함하고 버전/모델/정책 버전을 키에 추가하면 불필요한 재생성과 오래된 결과 재사용을 함께 줄일 수 있다.
15. **“상위 3곳”과 사용자 만족의 측정 루프가 없다.** 카드 클릭, 저장, 숨김/관심 없음, 추천 후 기록 생성 같은 피드백을 익명 집계하고, 추천 근거와 노출 버전을 함께 기록해야 품질 개선을 검증할 수 있다.

## 6. 우선 실행 권장 순서

1. 기록 본문 외부 전송 최소화와 사용자 고지 검토
2. 지역 선택 정책 및 “다른 추천” 동작을 제품 기대와 맞추기
3. 다중 worker 세션 캐시를 공용 저장소/cursor 방식으로 정리
4. 단계별 총 deadline·latency·탈락 사유 지표 추가
5. 입력 기록/토큰 상한 및 근거 사전 품질 평가 체계 구축
6. 기존 테스트에 지역 혼합, 캐시 다중 worker, malformed 숫자, 부분 공급자 실패 시나리오 보강

## 7. 주요 코드 위치

| 영역 | 파일 |
|---|---|
| API 파이프라인, 근거 점수, 세션 캐시, fallback | `overlap/backend-fastapi/app/ai_recommendations.py` |
| 긍정 기록 조회 및 DTO 변환 | `overlap/backend-fastapi/app/recommendation_record_adapter.py` |
| 키워드 추출 및 로컬 fallback | `overlap/backend-fastapi/app/openrouter_preference_keyword_service.py` |
| Tavily 검색 | `overlap/backend-fastapi/app/tavily_place_search_service.py` |
| Kakao 장소 검증 | `overlap/backend-fastapi/app/kakao_place_verification_service.py` |
| OpenRouter 순위화/출력 검증 | `overlap/backend-fastapi/app/openrouter_place_recommendation_service.py` |
| 추천/후보 DTO | `overlap/backend-fastapi/app/ai_recommendation_models.py` |
| 이미지 보강 | `overlap/backend-fastapi/app/recommendation_image_service.py` |
| Flutter API 호출/요청 병합 | `overlap/frontend/lib/features/ai/services/ai_recommendations_api.dart` |
| 추천 화면 상태 및 재요청 | `overlap/frontend/lib/features/ai/screens/ai_recommendation_screen.dart` |
| 카드 데이터 변환 | `overlap/frontend/lib/features/ai/models/ai_place_recommendation.dart` |
| 주요 파이프라인 테스트 | `overlap/backend-fastapi/tests/test_ai_recommendations.py`, `overlap/backend-fastapi/tests/test_openrouter_structured_output_and_fallback.py` |
