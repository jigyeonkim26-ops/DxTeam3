# 프론트 담당자와 공유할 API 안내

현재 버전: 0.1.0. 실행하면 `/docs`에서 요청·응답 형식과 예시를 확인할 수 있습니다. `/openapi.json`이 코드에서 생성한 상세 명세입니다.

## 공통 규칙

- 본문은 JSON, 헤더는 `Content-Type: application/json`입니다.
- 회원가입·로그인·실행 확인을 제외하면 `Authorization: Bearer <access_token>`이 필요합니다.
- 토큰은 로그인 응답으로 받은 값입니다. 유효 시간 1시간, 현재 로그인만 로그아웃 가능합니다.
- 계정·로그인 정보를 포함한 모든 상태는 서버 재시작 시 사라집니다.
- 기록 작성자와 소속은 서버가 인증 정보와 API 경로를 통해 결정합니다.
- 현재 명세의 영문 항목 이름을 프론트에서 그대로 사용합니다.

## API 목록

| 메서드 | 주소 | 기능 |
|---|---|---|
| GET | `/health` | 서버 실행 확인 |
| POST | `/auth/register` | 아이디·표시 이름·비밀번호로 가입 |
| POST | `/auth/login` | 토큰 발급 |
| GET | `/auth/me` | 내 정보 |
| POST | `/auth/logout` | 현재 토큰 폐기 |
| POST | `/groups` | 모임 생성, 모임장 자동 가입, 초대 코드 반환 |
| GET | `/groups` | 내가 가입한 모임 목록 |
| POST | `/groups/join` | 초대 코드로 가입, 중복 가입 시 기존 상태 반환 |
| GET | `/groups/{group_id}/invite` | 모임장의 초대 코드 조회 |
| POST | `/groups/{group_id}/places` | 모임에 장소 수동 등록 |
| GET | `/groups/{group_id}/places` | 등록한 장소 검색 |
| POST | `/groups/{group_id}/memories` | 추억 기록 등록 |
| GET | `/groups/{group_id}/memories` | 목록, 날짜/장소 필터, 정렬 |
| GET | `/groups/{group_id}/memories/{memory_id}` | 상세 조회 |
| PUT | `/groups/{group_id}/memories/{memory_id}` | 작성자가 장소·내용·추억 날짜를 모두 보내 수정 |
| DELETE | `/groups/{group_id}/memories/{memory_id}` | 작성자가 삭제 |
| GET | `/groups/{group_id}/places/{place_id}/timeline` | 해당 장소의 모든 작성자 기억, 추억 날짜 오름차순 |
| GET | `/groups/{group_id}/map` | 기록이 있는 장소별 지도 핀 정보 |

`/groups` 목록은 배열입니다. 장소·기록·타임라인·지도 목록은 아래의 페이지 형식을 사용합니다.

```json
{"items": [], "total": 0, "offset": 0, "limit": 20}
```

- 페이지 크기: `limit=1~100`, 기본 20. 시작 위치: `offset=0`부터.
- 장소 검색: `query=검색어`. 이름·주소에서 검색하며 외부 지도 검색이 아닙니다.
- 기록 목록: `place_id`, `date_from=YYYY-MM-DD`, `date_to=YYYY-MM-DD`, `order=newest|oldest`.
- 날짜 범위는 양끝을 포함하며 `visited_on` 기준입니다. 기본 정렬은 `newest`입니다.
- 같은 추억 날짜에서는 작성 시각과 ID를 차례로 사용하여 순서를 정합니다.
- 지도는 `place` 안에 장소 ID·이름·주소·위도·경도를, 바깥에 `memory_count`, `contributor_count`, `first_visited_on`, `last_visited_on`을 반환합니다.
- 사진·대표 이미지 필드는 아직 없습니다.

## 상태 코드

| 코드 | 의미 |
|---|---|
| 200 | 성공 |
| 201 | 회원·모임·장소·기록 생성 |
| 204 | 로그아웃 또는 삭제 성공, 응답 본문 없음 |
| 400 | 시작 날짜가 종료 날짜보다 늦음 |
| 401 | 로그인 누락·잘못된 로그인·토큰 만료 |
| 403 | 작성자 전용 작업 또는 모임장 전용 작업 권한 없음 |
| 404 | 존재하지 않거나 접근할 수 없는 모임·장소·기록·초대 |
| 409 | 아이디 또는 같은 모임의 정확히 일치하는 장소 중복 |
| 422 | 입력 항목·자료형·범위 오류, 허용되지 않은 추가 항목 |

일반 오류는 `{"detail":"설명"}`, 입력 오류는 `{"detail":[{"loc":["body","필드"],"msg":"설명","type":"유형"}]}`입니다. 비밀번호 등 입력 원문은 오류 응답에 담지 않습니다.

## 안드로이드 연결 시

아직 API 테스트만 하는 단계입니다. 이후 실제 기기 연결 시에는 실행 위치에 맞는 서버 주소, 네트워크 접근 설정, 앱의 네트워크 권한을 함께 설정합니다. 현재 127.0.0.1 주소는 개발 PC 자신을 가리킵니다. 앱에 DB 접속 계정이나 비밀번호를 넣지 않습니다.
