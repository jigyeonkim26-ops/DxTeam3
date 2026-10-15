
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

실행 중인 Uvicorn 프로세스는 이미 import한 모듈을 계속 사용할 수 있으므로, 변경을 적용하려면 프로세스를 재시작해야 합니다. Windows에서 포트 8002를 잡은 PID와 실행 경로는 PowerShell에서 `Get-NetTCPConnection -LocalPort 8002 -State Listen | Select-Object -ExpandProperty OwningProcess -Unique`로 PID를 확인하고, `Get-CimInstance Win32_Process -Filter "ProcessId = <PID>" | Select-Object ProcessId, ExecutablePath, CommandLine`으로 실행 파일 및 `uvicorn`의 working directory/module 경로를 확인합니다. 명령 줄의 `app.main:app`이 가리키는 프로젝트 루트가 이 체크아웃의 `overlap/backend-fastapi`인지 함께 대조해야 합니다.\n