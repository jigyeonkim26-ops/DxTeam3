# OVERLAP 개발 작업 로그

> 이 문서는 날짜별 작업 기록을 누적한다. 비밀값·개인정보·토큰·`.env` 값은 기록하지 않는다.

## 2026-10-08 — 통합본 모임 상태 및 인증 세션 오류 수정

### 구현

- `GroupListStore`에 생성·가입 모임의 즉시 upsert와 동시 새로고침 병합을 추가했다.
- 기록 작성 화면이 공용 모임 목록을 구독하도록 변경해 IndexedStack 상태 유지 중에도 생성·가입·탈퇴 결과를 즉시 반영한다. 유효한 공유 선택은 유지하고 탈퇴 모임 선택은 제거한다.
- 초대코드 시트의 `공유하기` 버튼을 제거하고 초대코드 조회·클립보드 복사만 유지했다.
- HTTP 401에서만 메모리 Access Token을 idempotent하게 무효화하고 앱 네비게이션 스택을 로그인 화면으로 초기화했다. 로그인 401은 비밀번호 오류로 구분한다.
- Refresh Token, 평문 토큰 저장, 백엔드 API·MySQL 스키마·NCP 설정 변경은 하지 않았다.

### 수정 파일

- Flutter 공통 인증: `api_client.dart`, `api_transport.dart`, `main.dart`, `login_screen.dart`, `auth_api_service.dart`
- 모임·기록 작성: `group_list_store.dart`, `create_group_screen.dart`, `join_group_screen.dart`, `groups_screen.dart`, `record_compose_screen.dart`, `record_api.dart`
- 테스트: `auth_session_test.dart`, `group_integration_test.dart`, `record_compose_test.dart`
- 개발 문서: `DEVELOPMENT_STATUS.md`, `DEVELOPMENT_LOG.md`

### 검증

- Flutter analyze 통과
- 세션 만료 로그인 전환, 반복 401 단일 무효화, 잘못된 비밀번호 401 구분, 생성·가입·탈퇴 공용 모임 캐시, 기록 작성 화면 구독, 초대코드 복사 UI 대상 테스트 통과
- 전체 Flutter 테스트는 77 통과. 수정하지 않은 `map_places_api_test.dart` 3건이 단독 실행에서도 기존 `MapPlacesApiException`으로 실패한다.

### Git 및 충돌 주의

- 기준 브랜치 `feature/fullstack-frontend-ui-test`에서 `feature/fix-group-auth`를 생성했다. Merge/Rebase는 하지 않았다.
- 공통 인증·모임 상태 파일은 다른 팀원 변경과 충돌 가능성이 높다. 스테이지 시 실제 수정 파일만 선택한다.
- Commit: `44e95f1` (`fix: refresh group state and handle auth session expiration`)
- Push: `origin/feature/fix-group-auth`에 non-force Push 완료
- PR/Merge: 수행하지 않음.

## 2026-10-08 — 개발 현황 문서 체계 초기화

### 작업 범위

- 프로젝트 루트와 상위 경로에서 `AGENTS.md`, `AGENTS.override.md`를 확인했다. 적용 가능한 파일은 없었다.
- `DEVELOPMENT_STATUS.md`, `DEVELOPMENT_LOG.md`가 없음을 확인하고 새로 만들었다.
- 로컬 Codex 작업 규칙을 `AGENTS.md`에 작성했다.
- `.git/info/exclude`에 프로젝트 루트의 `AGENTS.md` 및 `AGENTS.override.md` 제외 규칙을 추가했다. 개발 현황·로그 문서는 제외하지 않는다.

### 코드·Git 현황 스냅샷

- 브랜치: `feature/mypage-group-ui`
- HEAD: `f6be04b` (`merge: integrate completed frontend`)
- 기존 미커밋 변경: 추적 변경 17개, 미추적 코드·테스트 5개, 미추적 `CODEX_HANDOFF.md` 1개
- 기존 변경은 마이페이지·모임 API 연동, 프로필 사진 API 및 Flutter UI를 포함한다.
- `.env.example` 삭제는 이번 문서 작업의 변경이 아니며, 출처 확인 전 복원하지 않는다.

### 확인한 구현·검증 기록

- 프로필 사진 API: `POST/GET/DELETE /auth/me/photo` 구현 확인
- DB·저장소: `profile_image_key` Object Key 저장과 private Object Storage 경로 사용 확인
- 최근 인수인계 기준 대상 백엔드 테스트 `9 passed`, Flutter 분석 `No issues found`
- 전체 백엔드·Flutter 테스트와 사진 수동 플로우는 사진 변경 후 재검증이 남아 있다.

### 이번 작업의 실제 변경 파일

- `AGENTS.md` — 로컬 Codex 작업·기록 지침 추가
- `DEVELOPMENT_STATUS.md` — 현재 개발 현황 초안 추가
- `DEVELOPMENT_LOG.md` — 작업 로그 초기화
- `.git/info/exclude` — 다음 단계에서 로컬 전용 `AGENTS` 파일 제외 규칙 추가

### Git 작업

- commit: 하지 않음
- push: 하지 않음
- PR: 생성하지 않음
- merge: 하지 않음

### 후속 작업

- `AGENTS.md`가 실제로 Git 제외되는지 확인한다.
- 이후 개발 작업 종료 시 상태 문서를 최신화하고 이 로그에 날짜별 기록을 추가한다.

## 2026-10-08 — 마이페이지 내 기록 수정·삭제

### 작업 범위

- 마이페이지의 내 기록 상세에 작성자용 수정·삭제 메뉴를 추가했다.
- 수정 화면은 기존 글, 감정, 공개 범위, 공유 모임을 초기값으로 표시하고 장소·사진은 변경하지 않는다.
- 수정 성공 시 `RecordApi.revision`과 상세 화면 결과를 이용해 마이페이지 목록을 즉시 갱신한다.
- 삭제는 확인 다이얼로그에서 사용자가 확정할 때만 요청하며, 실패 시 상세 화면·목록을 유지한다.

### 백엔드 API·DB

- `PATCH /records/{record_id}` 추가: 인증 토큰의 작성자 본인만 글 내용·감정·공유 범위를 부분 수정할 수 있다.
- `DELETE /records/{record_id}` 추가: 인증 토큰의 작성자 본인만 삭제할 수 있으며, `record_groups`와 `record_photos` 관계 행을 명시적으로 정리한다.
- 공유 모임을 요청으로 선택할 때는 실제 가입 여부를 검사한다. 비공개 기록은 빈 `group_ids`만 허용하고, 공유 기록은 최소 한 모임을 요구한다.
- 새 MySQL 스키마 변경은 없다. 장소 행은 다른 기록에서 사용할 수 있어 삭제하지 않는다.
- 사진 Object Key가 다른 기록에서 참조되는지 확인한 뒤 독점 키만 MySQL commit 이후 best-effort로 정리한다. 저장소 실패는 private orphan 정리 대상이지만 사진만 먼저 삭제되고 DB 기록이 남는 순서는 만들지 않는다.

### 실제 변경 파일

- `overlap/backend-fastapi/app/records.py`
- `overlap/backend-fastapi/tests/test_records.py`
- `overlap/frontend/lib/features/memory/services/record_api.dart`
- `overlap/frontend/lib/features/memory/screens/record_detail_screen.dart`
- `overlap/frontend/lib/features/memory/screens/record_edit_screen.dart` (새 파일)
- `overlap/frontend/lib/features/user/screens/profile_screen.dart`
- `overlap/frontend/test/record_management_test.dart` (새 파일)
- `overlap/frontend/test/profile_update_api_test.dart` (기존 multipart HTTP 테스트 더블 보완)
- `DEVELOPMENT_STATUS.md`, `DEVELOPMENT_LOG.md`

### 검증

- 격리 SQLite·Mock Storage 대상 기록 수정·삭제 테스트 5건 통과
- 백엔드 전체 `python -m pytest` → `63 passed`
- Flutter 대상 기록 API·관리 화면 테스트 통과
- `flutter analyze --no-pub` → `No issues found`
- 로그인 로고는 분리된 `RichText` span으로 렌더링된다. `widget_test.dart`의 기본 텍스트 탐색을 `findRichText: true`로 최소 수정했고, Flutter 전체 테스트가 통과했다.
- 실제 공통 MySQL·NCP를 사용한 수정·삭제 수동 검증은 실행하지 않았다.

### 통합 및 Git

- 충돌 가능성 높음: `app/records.py`, `record_api.dart`, `record_detail_screen.dart`, `profile_screen.dart`, `tests/test_records.py`
- 공통 DB의 기존 기록을 테스트로 삭제하지 않았고, 테스트는 격리 SQLite·Mock Storage만 사용했다.
- commit, push, PR, merge: 하지 않음

## 2026-10-08 — 커밋·푸시 전 최종 검증 및 통합 브랜치 확인

### 원격·통합 상태

- 원격 `feature/mypage-group-ui` 브랜치는 아직 없으며, 첫 non-force push가 새 원격 작업 브랜치를 생성한다.
- 새 PR 대상 `feature/fullstack-frontend-ui-test`의 확인 시점 HEAD는 `61bf32a`이다.
- 현재 작업 브랜치와 새 통합 브랜치를 merge·rebase하지 않았다.
- 변경 파일 9개 중 직접 겹침은 `overlap/frontend/lib/features/group/services/group_api_service.dart` 하나다. 통합 브랜치의 해당 변경은 포맷이고, 현재 작업은 모임 통계 기능을 추가한다.

### 검증

- 백엔드 전체 `python -m pytest` → `63 passed` (Starlette deprecation, 기존 pytest cache 경고 2건)
- `flutter analyze --no-pub` → `No issues found`
- `flutter test --no-pub` → `70 passed`
- `git diff --check` → 공백 오류 없음; LF→CRLF 경고만 출력
- 로그인 UI는 `RichText`로 `OVERLAP`을 조합한다. 테스트의 `find.text`에 `findRichText: true`를 지정해 UI와 기대값을 정렬했으며, UI 코드는 수정하지 않았다.

### 커밋 범위

- 실제 소스·테스트·개발 문서만 개별 stage한다.
- 추적된 `overlap/backend-fastapi/.env.example` 삭제는 이번 기능 구현의 의도가 확인되지 않아 stage하지 않는다.
- 로컬 전용 `AGENTS.md`와 `CODEX_HANDOFF.md`는 stage하지 않는다.
- commit, push는 사용자 승인에 따라 이 검증 직후 진행한다. PR 생성·merge는 하지 않는다.

### 결과

- 구현 커밋: `415461f` — `feat: complete my page and group management features`
- 원격 push: `origin/feature/mypage-group-ui`에 non-force push 완료 및 upstream 설정 완료
- PR 생성·merge: 하지 않음
