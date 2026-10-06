# 다음 단계: MySQL 연결

이 문서는 후속 구현 설계안입니다. 현재 프로젝트에는 SQLAlchemy·MySQL 연결·테이블 생성 SQL이 포함되지 않습니다. 우선 기존 API를 실행한 뒤 이 단계로 넘어갑니다.

## 첫 테이블 초안

| 테이블 | 주요 컬럼 | 규칙 |
|---|---|---|
| `users` | id, username, display_name, password_hash, created_at | username 고유, 비밀번호 해시 저장 |
| `memory_groups` | id, name, owner_id, created_at | owner_id가 회원을 참조 |
| `group_members` | group_id, user_id, joined_at | 두 ID 조합 중복 방지 |
| `group_invites` | id, group_id, token_hash, expires_at, revoked_at | 코드 만료·폐기 지원, 초대 원문 저장 최소화 |
| `places` | id, group_id, name, address, latitude, longitude | 첫 버전은 모임별 장소 |
| `memories` | id, group_id, place_id, author_id, content, visited_on, created_at, updated_at | 날짜와 작성 시각 분리 |
| `auth_sessions` | token_hash, user_id, expires_at | 토큰 원문 대신 해시 저장, 로그아웃 시 폐기 |
| `memory_photos` | id, memory_id, storage_key, sort_order | 사진 단계에서 추가 |

`groups` 대신 `memory_groups`처럼 SQL 예약어와 겹치지 않는 이름을 사용합니다. 세부 컬럼 자료형·길이·인덱스는 실제 구현 때 확정합니다.

## 기존 API를 유지하는 연결 순서

1. DB 담당자와 테이블·외래키·중복 방지 규칙을 확정.
2. MySQL과 SQLAlchemy 연결, 앱 전용 DB 계정과 환경변수 구성.
3. `app/service.py`의 메모리 저장 부분을 DB 저장·조회로 바꾸기. API 입출력 모델은 유지.
4. 모임 생성과 모임장 가입을 하나의 트랜잭션으로 처리.
5. 기록이 참조하는 장소가 같은 모임에 속하는지 서버와 DB 설계에서 보장. 예를 들어 `places`의 `(group_id, id)` 고유키를 `memories(group_id, place_id)`에서 함께 참조.
6. 회원 중복 가입은 `(group_id, user_id)` 고유 제약으로 방지.
7. 현재 테스트를 DB 환경에도 적용하고 서버 재시작 후에도 기록이 남는 테스트 추가.
8. 테이블 생성·변경 이력은 마이그레이션 도구로 관리하고 GitHub에 함께 보관.

메모리 저장소의 잠금을 DB에서 그대로 흉내 내는 대신 트랜잭션·고유 제약·필요한 행 잠금으로 동시 요청을 처리합니다.

## 함께 결정할 항목

- 한 기록을 여러 모임에 공유할 것인지. 허용 시 공유 연결 테이블과 조회 권한 규칙 추가.
- 장소를 모임별로 유지할지, 지도 제공자의 장소 ID를 사용해 공통 장소와 모임 연결로 나눌지.
- 모임 탈퇴·회원 내보내기·계정 삭제 시 기존 기록과 사진의 처리.
- 반복 등록 버튼이나 네트워크 재시도에 따른 중복 생성 방지.
- 초대 코드 만료·재발급 정책과 로그인 시도 제한.
- 사진 접근 권한, 업로드 실패 정리, DB와 사진 각각의 백업·복원.

MySQL DB 트랜잭션은 외부 파일 저장소의 업로드까지 함께 되돌려주지 않습니다. 사진 업로드와 기록 저장의 실패 처리·미사용 파일 정리 절차가 별도로 필요합니다.

## 참고

- [SQLAlchemy MySQL 지원](https://docs.sqlalchemy.org/en/20/dialects/mysql.html)
- [MySQL 외래키](https://dev.mysql.com/doc/refman/8.4/en/create-table-foreign-keys.html)
- [MySQL 트랜잭션](https://dev.mysql.com/doc/refman/8.4/en/commit.html)
