# 기록 작성·개인 맞춤 피드 구현 결과

작업 저장소: DxTeam3-fullstack. Frontend와 Backend는 같은 Git 저장소이며 브랜치는 `feature/fullstack-integration-test`, HEAD는 `71fc066eee35b9f5f865fe753aa471427a62652b`입니다. 시작 시 존재한 현재 위치/ANR 수정과 미추적 파일을 유지했습니다. Commit, push, reset, clean, restore, rebase, stash drop, 서버 재시작은 수행하지 않았습니다.

## 동작

기존 주황색 + 버튼에서 사진 선택, 감정 선택, 실제 Kakao 장소 선택, 선택 입력인 한 줄 기록(최대 300자), 나만 보기 또는 실제 가입 모임 공유를 지원합니다. 사진·감정·장소는 필수입니다. 저장 성공 후 피드로 이동하고 피드를 갱신합니다. 실패하면 작성 내용은 유지합니다.

피드는 본인 기록과 실제 가입 모임에 공유된 기록만 조회합니다. 나만 보기 기록과 사진은 작성자에게만 허용합니다. 샘플 피드·모임·댓글·사진·저장 기록·알림 데이터를 제거했으며 실제 사용자 정보는 인증 API에서 읽습니다. 모임 목록은 DB 기반이며 기존 모임 생성/가입 화면의 가짜 성공 동작은 비활성화했습니다. 실제 모임 생성/가입 API 연결은 이번 구현 범위에 포함하지 않습니다.

댓글·좋아요·알림·저장 장소 DB 테이블은 연결하거나 변경하지 않았습니다. 기존 지도/+ 버튼/피드 카드 배치를 유지했습니다. 지도 샘플 기록 핀은 제거했지만 검색 핀·현재 위치 핀과 기존 위치 권한/Android 채널/ANR 우회 구현은 유지했습니다.

## API·DB·환경

추가 API: `POST /records`, `GET /records/groups`, `GET /feed`, `GET /records/{record_id}/photos/{photo_id}`. 요청·응답과 설정 계약은 [records-api.md](records-api.md)에 있습니다.

실제 MySQL 스키마를 확인한 뒤 `record_photos.photo_url VARCHAR(500) NULL` 컬럼만 추가했습니다. 기존 `object_key`, 기존 데이터와 모든 테이블을 보존했습니다. 실제 MySQL에서 모든 새 모델과 회원/피드 조회 쿼리를 읽기 전용으로 검증했습니다. 사진 바이너리는 DB에 넣지 않습니다. NCP 객체는 비공개로 저장하고 FastAPI가 권한 검사 후 사진을 전달합니다.

Backend `.env`에 `NCP_ACCESS_KEY`, `NCP_SECRET_KEY`, `NCP_BUCKET_NAME`, `NCP_ENDPOINT` 설정이 필요합니다. 작업 시 네 값 모두 없었으므로 실제 NCP 업로드는 검증하지 않았습니다. 임의 값은 만들지 않았습니다. `.env`는 기존 `.gitignore`로 제외되며 Git 추적 대상이 아님을 확인했습니다. 키 값을 출력하지 않았습니다.

## 이번 작업의 변경 파일

Backend:
- `.env.example`, `requirements.txt`, `app/main.py`
- `app/record_models.py`, `app/records.py`, `app/object_storage.py`
- `scripts/add_record_photo_url.py`, `tests/test_records.py`
- `docs/records-api.md`, `docs/record-integration-result.md`

Frontend:
- `pubspec.yaml`, `pubspec.lock` (image_picker)
- `lib/shared/models/record.dart`
- `lib/features/home/screens/app_shell_screen.dart`
- `lib/features/memory/services/record_api.dart`
- `lib/features/memory/screens/record_compose_screen.dart`, `feed_screen.dart`, `record_detail_screen.dart`
- `lib/features/memory/widgets/photo_placeholder_picker.dart`, `record_photo.dart`, `record_card.dart`, `feed_filter_sheet.dart`
- `lib/features/memory/models/feed_filter.dart`, `lib/features/memory/data/mock_feed_data.dart`
- `lib/features/group/screens/groups_screen.dart`
- `lib/features/group/services/mock_group_repository.dart` → `group_repository.dart`
- `lib/features/map/screens/map_screen.dart`, `place_detail_screen.dart`, `lib/features/map/widgets/map_filter_sheet.dart` (샘플 데이터/모임 제거)
- `lib/features/user/screens/profile_screen.dart`, `profile_edit_screen.dart`, `group_management_screen.dart`
- `lib/features/user/models/profile_summary_data.dart`
- `lib/features/user/services/mock_profile_repository.dart`, `mock_saved_repository.dart`, `mock_share_card_repository.dart`
- `lib/features/notification/services/mock_notification_repository.dart`
- `test/record_api_test.dart`, `test/record_compose_test.dart`

Git 상태에 보이는 기존 Android 위치 채널, 권한, Kakao WebView, 위치 서비스와 위치 테스트 변경도 보존되어 있습니다.

## 검증

- Backend pytest: **32 passed**, 기존 Starlette TestClient 관련 경고 1건.
- dart format: 완료.
- flutter analyze: **No issues found**.
- flutter test: **38 passed**.
- Android debug APK 빌드: 성공, `frontend/build/app/outputs/flutter-apk/app-debug.apk`.
- 기록 저장, 사진 URL/객체 키 저장, 선택 입력 내용, 개인 맞춤 피드, 나만 보기/사진 접근 차단, 실제 회원 목록, 탈퇴 후 접근 차단, 가상 데이터 미노출, 잘못된 입력, 저장 실패 및 부분 업로드 정리를 검증했습니다.
- 현재 위치 A → 검색 B → 동일 위치 A 재요청 시 재중앙화와 두 오버레이 유지 테스트가 통과했습니다. Android 위치 권한/서비스 테스트도 통과했습니다.
- APK를 에뮬레이터에 설치해 수동 재현하거나 실제 NCP로 업로드하지는 않았습니다.
