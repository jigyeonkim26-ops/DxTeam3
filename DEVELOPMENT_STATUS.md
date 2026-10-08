# OVERLAP 개발 현황

> 기준 시각: 2026-10-08
> 근거: 현재 작업 트리, 코드 diff, 최신 인수인계(`CODEX_HANDOFF.md`)를 확인해 작성했다. 검증 결과는 실행 시점이 명시된 항목만 검증 완료로 취급한다.

## 2026-10-08 — 통합본 모임·인증 오류 수정

- 작업 브랜치: `feature/fix-group-auth` (기준: `feature/fullstack-frontend-ui-test`의 `2cfb287`)
- 모임 생성·초대코드 가입 성공 응답을 `GroupListStore`에 즉시 upsert하고, 기록 작성 화면은 해당 `ValueNotifier`를 구독한다.
- 기록 작성 화면은 유효한 기존 공유 모임 선택을 유지하고, 탈퇴로 목록에서 제거된 ID는 선택값에서도 제거한다.
- `GroupListStore`는 동시 새로고침을 합쳐 중복 목록 호출을 줄이며, 통계가 필요한 요청은 기존 목록 요청 이후 한 번만 추가로 수행한다.
- 초대코드 시트에는 `코드 복사`만 남기고 미구현 `공유하기` 버튼을 제거했다.
- 인증된 API 요청이 실제 HTTP 401을 받으면 메모리 Access Token을 한 번만 폐기하고 로그인 화면으로 스택을 초기화한다. 네트워크·시간 초과·일반 서버 오류는 세션을 폐기하지 않는다.
- 로그인 API의 401은 기존 토큰이 없으므로 잘못된 비밀번호 메시지로 유지한다. Refresh Token, 토큰 영속 저장, MySQL 스키마·백엔드 API 변경은 없다.
- 앱 재시작 시 토큰을 저장·복원하지 않아 로그인 화면에서 시작한다. 백엔드 재시작 또는 1시간 세션 만료는 401 후 동일한 재로그인 안내로 처리한다.

### 이번 작업 검증

- `C:\flutter\bin\flutter.bat analyze --no-pub` → 통과 (`No issues found`)
- 대상 테스트 `auth_session_test.dart`, `group_integration_test.dart`, `record_compose_test.dart` → 통과
- 전체 `flutter test --no-pub` → 77 통과, `map_places_api_test.dart` 기존 3건 실패. 지도 소스·테스트는 이번 diff에 포함하지 않았고, 해당 테스트 단독 실행에서도 같은 `MapPlacesApiException`이 발생한다.
- 백엔드 파일을 변경하지 않아 pytest는 이번 작업에서 실행하지 않았다.

### 통합 주의

- 충돌 가능성 높음: `api_client.dart`, `api_transport.dart`, `main.dart`, `login_screen.dart` — 공통 인증 및 앱 진입 흐름
- 충돌 가능성 높음: `group_list_store.dart`, `create_group_screen.dart`, `join_group_screen.dart`, `groups_screen.dart`, `record_compose_screen.dart` — 모임 상태와 공유 UI
- 지도·피드·장소 상세·알림·AI 추천 기능 및 DB/NCP 설정은 수정하지 않았다.

## 저장소 상태

- 프로젝트: `DxTeam3-team4`
- 현재 브랜치: `feature/mypage-group-ui`
- PR 대상 통합 브랜치: `feature/fullstack-frontend-ui-test`
- 구현 커밋: `415461f` — `feat: complete my page and group management features`
- `415461f`는 원격 `feature/mypage-group-ui`에 non-force push 완료했다. PR 생성·merge는 하지 않았다.
- `.env.example` 삭제를 포함한 기존 미커밋 변경이 있으므로, 출처를 확인하기 전에는 되돌리거나 삭제하지 않는다.
- 이번 문서 설정으로 `AGENTS.md`는 로컬 Git 제외 대상이며, 이 문서와 `DEVELOPMENT_LOG.md`는 향후 PR 포함 여부를 별도로 결정한다.
- 새 통합 브랜치 최신 확인값은 `61bf32a`이며, 현재 작업 브랜치와 merge·rebase하지 않았다.

## 기능별 상태

| 영역 | 구현 상태 | 검증 상태 | 비고 |
| --- | --- | --- | --- |
| 내 프로필 조회·수정 | 구현됨 | 닉네임 변경 및 MySQL 저장 수동 확인 기록 있음 | `GET/PATCH /auth/me`, 닉네임·생년월일·성별 부분 수정 |
| 내 기록·가입 모임 표시 | 구현됨 | 전체 회귀 테스트 미실행 | 내 기록은 `/feed?mine=true`, 모임은 상태 저장소 사용 |
| 모임 관리 | 구현됨 | 전체 회귀 테스트 미실행 | 생성, 초대코드 가입, 탈퇴, 설정, 초대코드 표시·복사, 로딩·오류·빈 상태 연결 |
| 모임 장소 수 | 구현됨 | API 응답 기준 확인 필요 | 그룹 공유 기록의 중복 없는 장소 수로 계산. 새 기록 수는 API 정의 부재로 임의 표시하지 않음 |
| 프로필 사진 API | 구현됨 | 대상 백엔드 테스트 통과 | 업로드·조회·삭제 및 NCP Object Storage 연동 |
| 프로필 사진 Flutter UI | 구현됨 | 분석 통과, 전체 테스트·수동 검증 미완료 | 갤러리 선택, 미리보기, 교체·삭제, 기본 아이콘 폴백 |
| 내 기록 수정·삭제 | 구현됨 | 백엔드 전체 테스트·Flutter 대상 테스트 통과, 실제 공통 DB 수동 검증 미완료 | 마이페이지 상세 메뉴에서 글·감정·공유 범위를 수정하거나 삭제 |
| 지도·메인 피드·기록 작성·AI 추천 | 이번 작업 범위 아님 | 해당 없음 | 새로 수정하지 않는 범위 |

## API 및 DB 변경

### API

- 기존 프로필 연동: `GET /auth/me`, `PATCH /auth/me`
- 프로필 사진 추가:
  - `POST /auth/me/photo` — 로그인한 사용자의 사진 업로드·교체, 성공 시 `204`
  - `GET /auth/me/photo` — 로그인한 사용자의 사진만 조회
  - `DELETE /auth/me/photo` — 로그인한 사용자의 사진 삭제, 성공 시 `204`
- 기록 수정·삭제 추가:
  - `PATCH /records/{record_id}` — 작성자 본인이 글 내용·감정·공개 범위를 부분 수정하고 수정된 기록을 반환
  - `DELETE /records/{record_id}` — 작성자 본인의 기록·연결된 `record_groups`·`record_photos` 행을 삭제하고 성공 시 `204`
- 사진 업로드는 실제 이미지 포맷을 확인해 JPEG/PNG/WebP만 허용하며, 최대 5MB다. 사용자 ID를 요청값으로 받지 않고 Access Token의 사용자만 처리한다.
- 모임 연동은 `/groups`, `/groups/{id}`, `/groups/{id}/preferences`, `/groups/{id}/members/me`, `/groups/join`, `/groups/{id}/invite` 및 그룹 피드 조회를 사용한다.

### DB·저장소

- `users.profile_image_key VARCHAR(500) NULL`을 Object Key 저장용으로 사용한다. 바이너리·Base64는 DB에 저장하지 않는다.
- 코드상 모델에 해당 컬럼이 있다. 공유 MySQL에 자동 마이그레이션은 실행하지 않았다.
- 실제 공유 DB 반영 전에는 승인된 관리자가 컬럼 존재 여부를 확인해야 한다. 컬럼이 없다는 확인 없이 `ALTER TABLE`을 실행하지 않는다.
- 프로필 사진은 Object Storage의 `profiles/{user_id}/...` 경로에 private ACL로 저장하며, 기존 기록 사진 경로는 변경하지 않는다.
- 기록 수정·삭제에는 새 테이블·컬럼·마이그레이션이 필요 없다. 기존 `records`, `record_groups`, `record_photos`만 사용하고 장소 행은 삭제하지 않는다.
- 기록 삭제는 MySQL 관계 행과 기록을 먼저 한 트랜잭션으로 확정한 뒤, 다른 `record_photos` 행이 참조하지 않는 Object Key만 Object Storage에서 best-effort로 삭제한다. 저장소 삭제가 실패하면 DB 기록은 이미 안전하게 삭제되어 사진이 없는 기록이 남지 않으며, private orphan 객체는 운영 정리 정책 대상이다.

## 현재 미커밋 코드 범위

기준 확인 시점의 기존 변경은 추적 파일 17개와 미추적 코드·테스트 5개였다. `CODEX_HANDOFF.md`도 미추적 상태였으며, 본 문서 두 개는 이번 문서 설정으로 새로 추가된다.

- 백엔드: `.env.example` 삭제(출처 미확인), `main.py`, `models.py`, `object_storage.py`, `service.py`, `test_records.py`
- Flutter 인증·프로필: `auth_api_service.dart`, `profile_edit_screen.dart`, `profile_screen.dart`, `profile_summary_card.dart`, 새 `user_profile.dart`, 새 `profile_photo_avatar.dart`
- Flutter 모임: `group_list_item_data.dart`, `group_detail_management_screen.dart`, `groups_screen.dart`, `group_api_service.dart`, `group_list_store.dart`, `group_list_item.dart`, `group_management_screen.dart`
- Flutter 테스트: 새 `group_list_item_data_test.dart`, `profile_update_api_test.dart`, `user_profile_test.dart`

### 이번 기록 관리 작업 추가·수정

- 백엔드: `app/records.py`, `tests/test_records.py`
- Flutter: `record_api.dart`, `record_detail_screen.dart`, 새 `record_edit_screen.dart`, `profile_screen.dart`, 새 `record_management_test.dart`
- 기존 프로필 사진 테스트: `profile_update_api_test.dart`의 multipart HTTP 테스트 더블을 보완했다. 앱 기능 코드는 변경하지 않았다.

## 검증 현황

### 확인됨

- 사진 API 대상 테스트: `python -m pytest tests/test_records.py -k "profile_photo or profile_update"` → `9 passed` (Starlette 제3자 deprecation warning 1건)
- 수정한 Dart 파일에 `dart format` 실행 기록 있음
- `C:\flutter\bin\flutter.bat analyze --no-pub` → `No issues found`
- 이번 문서 작성 전 `git diff --check` 실행 결과: 공백 오류는 없고 LF→CRLF 경고만 출력됨
- 기록 관리 변경 후 백엔드 전체 `python -m pytest` → `63 passed` (Starlette 제3자 deprecation warning, 기존 `.pytest_cache` 경고 1건)
- 기록 관리 Flutter 대상 `flutter test --no-pub test\\record_api_test.dart test\\record_management_test.dart` → 통과
- 프로필 사진 API 테스트 `flutter test --no-pub test\\profile_update_api_test.dart` → 통과
- 로그인 위젯 테스트 기대값을 현재 `RichText` 로고 구조에 맞춰 `findRichText: true`로 최소 수정했다.
- 최종 `flutter test --no-pub` → `70 passed`

### 미검증·재실행 필요

1. 에뮬레이터에서 내 기록 수정(나만 보기↔가입 모임 공유), 재진입·재로그인 후 유지, 삭제 확인·취소·성공·실패 메시지를 수동 검증
2. 실제 공유 DB의 `profile_image_key` 컬럼 존재 여부 확인
3. 프로필 사진 업로드·교체·삭제·재로그인 유지와 5MB 초과·비이미지 오류를 수동 검증

### 테스트 기대값 정렬

- 로그인 화면은 시각적 색상 구분을 위해 `OVER`·`LAP`을 하나의 `RichText`에 렌더링한다.
- 기존 테스트의 기본 `find.text('OVERLAP')` 탐색은 RichText span을 찾지 못했다. UI 코드는 변경하지 않고 `find.text('OVERLAP', findRichText: true)`로 기대값만 정렬했으며 전체 Flutter 테스트가 통과했다.

## 통합 주의 및 충돌 위험

- 높음: `app/main.py`, `app/models.py`, `app/service.py`, `app/object_storage.py` — 인증·DB·Object Storage·기존 기록 사진 흐름과 겹침
- 높음: `auth_api_service.dart` — 로그인·세션 처리와 겹침
- 높음: `profile_screen.dart`, `profile_edit_screen.dart`, `profile_summary_card.dart` — 마이페이지 UI와 겹침
- 높음: `group_list_store.dart`, `groups_screen.dart`, `group_detail_management_screen.dart`, `group_api_service.dart` — 모임 상태·관리 UI와 겹침
- 높음: `app/records.py`, `tests/test_records.py` — 실제 기록 API·권한·사진 저장소 정리와 겹침
- 높음: `record_api.dart`, `record_detail_screen.dart`, `profile_screen.dart` — 피드·기록 상세·마이페이지에서 공용으로 사용하는 흐름과 겹침
- 새 통합 브랜치와 직접 겹침: `group_api_service.dart`. 통합 브랜치는 같은 메서드의 포맷 변경, 현재 작업은 모임 기록·장소 통계 기능을 추가했다. PR 병합 시 이 파일의 hunk를 수동 확인한다.
- 통합 전에는 각 파일을 개별 검토하고, 범위 밖 기존 변경을 포함하지 않도록 선택 stage한다. `git add .`은 사용하지 않는다.

## 다음 작업

1. 에뮬레이터에서 내 기록 수정·삭제 플로우를 실제 로그인 계정으로 확인한다. 공통 DB의 기존 기록은 삭제 테스트에 사용하지 않는다.
2. 수동 사진 플로우와 DB 컬럼 존재 여부를 확인한다.
3. 검증 결과와 실제 변경 파일을 이 문서·로그에 갱신한다.
4. GitHub에서 `feature/fullstack-frontend-ui-test`를 대상으로 PR을 생성하기 전, `group_api_service.dart`의 통합 hunk를 확인한다. PR 생성·merge는 사용자와 팀 확인 후에만 수행한다.
