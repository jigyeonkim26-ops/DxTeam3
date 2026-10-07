# 오버랩 백엔드 시작 프로젝트

Python + FastAPI로 만든 첫 개발용 백엔드입니다. Swarm의 장소 기록·지도 탐색 흐름을 참고하고, 오버랩의 **모임별 공유**와 **같은 장소의 서로 다른 날짜·작성자 기억 모아보기**를 구현했습니다.

**현재 저장 방식은 메모리입니다. 서버를 종료하거나 코드 수정으로 서버가 재시작되면 회원·모임·기록·로그인이 모두 초기화됩니다.** MySQL은 아직 연결하지 않았습니다. 연습용 데이터를 사용하세요. 실제 서비스 배포 전 단계입니다.

> 이 백엔드의 저장소 위치는 `overlap/backend-fastapi/`입니다. VS Code에서 이 폴더를 열고 아래 명령을 실행하세요.
>
> **저장 방식은 현재 메모리입니다.** 서버를 종료하거나 재시작하면 데이터가 초기화됩니다.

## 1. 오늘 목표

첫 목표는 서버 실행과 API 테스트 화면 열기입니다. 다음으로 회원가입 → 로그인 → 모임 → 장소 → 기록 순서로 직접 요청해봅니다.

현재 구현:

- 회원가입, 로그인, 내 정보, 로그아웃. 비밀번호는 Argon2id 해시로 처리.
- 모임 생성, 초대 코드 가입, 내 모임 목록.
- 모임 안에서 장소 수동 등록·검색.
- 추억 날짜를 지정한 기록 등록·조회·수정·삭제.
- 같은 장소의 여러 사람 기록을 추억 날짜순으로 조회.
- 지도용 좌표·장소별 기록 수·작성자 수·날짜 범위 반환.
- 모임 회원만 열람/등록, 작성자만 수정/삭제.

다음 단계: MySQL 저장, 실제 사진 업로드, 안드로이드 화면 연결. 카카오 장소 검색은 `/places/search`에서 제공하며 `KAKAO_REST_API_KEY`가 필요합니다. `/map`은 지도에 쓸 **데이터 API**이며 지도 화면은 없습니다. `/groups/{group_id}/places`는 모임에 등록한 장소를 검색합니다. GPS 방문 인증과 실시간 위치 수집은 구현하지 않았습니다.

## 2. 준비

1. [Python 공식 다운로드](https://www.python.org/downloads/)에서 Python을 준비합니다. **Python 3.12에서 테스트했습니다.** 가능하면 같은 계열로 시작하세요.
2. VS Code에서 팀 저장소 안의 `overlap/backend-fastapi` 폴더를 엽니다. `app` 폴더와 `requirements.txt`가 보이는 위치입니다.
3. VS Code 상단 **터미널 → 새 터미널**을 누릅니다.

가상환경 `.venv`는 이 프로젝트에서만 사용하는 Python 패키지 보관 장소입니다. 아래 명령은 가상환경 활성화 없이 해당 Python을 직접 실행합니다.

### Windows PowerShell

먼저 `py --version`으로 설치 여부를 확인합니다. 여러 버전이 설치됐다면 첫 줄의 `py -3`을 `py -3.12`로 바꿀 수 있습니다.

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```

`py` 명령이 없지만 `python --version`이 정상으로 나온다면 첫 줄은 `python -m venv .venv`로 실행하세요. 둘 다 없으면 Python 설치 후 VS Code를 다시 엽니다.

### macOS / Linux

먼저 `python3 --version`을 확인합니다.

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
test -f .env || cp .env.example .env
.venv/bin/python -m uvicorn app.main:app --reload
```

Linux에서 가상환경 생성이 실패하면 해당 OS의 Python venv 패키지가 필요할 수 있습니다.

## 3. 실행 확인

터미널에 `Uvicorn running on http://127.0.0.1:8000`이 표시되면 브라우저에서 다음 주소를 엽니다.

- 실행 확인: <http://127.0.0.1:8000/health>
- API 테스트 화면: <http://127.0.0.1:8000/docs>

실행 확인 응답은 `{"status":"ok","storage":"memory"}`입니다. 서버를 끄려면 터미널에서 `Ctrl+C`를 누릅니다. 사용 중인 8000 포트 때문에 실행이 안 되면 명령 뒤에 `--port 8001`을 추가하고 브라우저 주소도 8001로 바꾸세요.

카카오 장소 검색을 사용하려면 `.env.example`을 `.env`로 복사한 뒤 `KAKAO_REST_API_KEY`에 본인의 키를 로컬에서 입력하세요. `.env`는 Git에서 제외됩니다. 키 없이도 나머지 메모리 기반 API를 실행하고 테스트할 수 있습니다.

현재 기본 실행은 내 컴퓨터에서만 접속할 수 있습니다. 여러 프로세스를 띄우는 `--workers` 옵션은 사용하지 마세요. 메모리 저장 상태를 서로 공유하지 않습니다.

## 4. 첫 기록 직접 올리기

API 테스트 화면에서 각 항목을 펼친 다음 **Try it out → 입력 → Execute** 순서로 실행합니다.

### 4-1. 회원가입: POST /auth/register

```json
{
  "email": "segeon@example.com",
  "password": "overlap-demo-123!",
  "nickname": "세건",
  "birth_date": "1995-05-17",
  "gender": "female",
  "terms_accepted": true
}
```

예시 비밀번호는 테스트용입니다. 가입 성공은 HTTP 201입니다. 이메일은 앞뒤 공백 제거 후 소문자로 정규화하며, 닉네임은 공백 제거 후 1~50자, 비밀번호는 8~128자입니다. 생년월일은 실제 날짜이며 미래일 수 없고, 필수 약관 동의가 필요합니다.

### 4-2. 로그인: POST /auth/login

```json
{
  "email": "segeon@example.com",
  "password": "overlap-demo-123!"
}
```

응답의 `access_token` 값만 복사합니다. 화면 위쪽 **Authorize**를 누르고 Value에 붙여넣어 Authorize → Close를 누릅니다. 따옴표나 `Bearer ` 글자는 붙이지 않습니다. 이후 요청에는 테스트 화면이 인증 정보를 자동으로 넣습니다.

이 토큰은 로그인 상태를 나타내는 임의의 문자열이며 JWT가 아닙니다. 유효 시간은 1시간입니다. 다시 로그인하면 새 토큰을 받습니다. 서버 재시작 시 모든 토큰이 무효화됩니다.

### 4-3. 모임 생성: POST /groups

```json
{"name": "대학교 친구"}
```

응답의 `id`가 모임 번호이고 `invite_code`는 가입 초대 코드입니다. 아래 예시는 첫 모임의 `id`가 1인 상황입니다. **실제 응답으로 받은 번호를 사용하세요.**

### 4-4. 장소 등록: POST /groups/{group_id}/places

`group_id`에 받은 모임 번호를 넣습니다.

```json
{
  "name": "오버랩 연습 장소",
  "address": "대전 테스트용 주소 — 실제 상호 아님",
  "latitude": 36.3504,
  "longitude": 127.3845
}
```

좌표와 이름은 개발용 예시입니다. 응답의 `id`가 장소 번호입니다. 동일 장소의 다음 기록에는 새 장소를 만들지 않고 이 번호를 사용합니다. 장소 이름의 오타나 유사 장소를 자동으로 합치는 기능은 아직 없습니다.

### 4-5. 기록 등록: POST /groups/{group_id}/memories

```json
{
  "place_id": 1,
  "content": "친구들과 처음 모여 오버랩을 기획했던 날!",
  "visited_on": "2024-09-01"
}
```

`place_id`는 실제로 받은 장소 번호로 바꿉니다. 작성자는 로그인 정보로 결정됩니다. 본문에 `author_id`나 `user_id`는 보내지 않습니다.

`visited_on`은 추억이 생긴 날짜, `created_at`은 서버에 등록한 시각입니다. 추억 날짜는 한국 시간 기준 오늘 또는 이전 날짜를 받으며, 작성 시각은 UTC로 반환합니다. 글 내용은 공백을 제외하고 1~2,000자입니다.

### 4-6. 오버랩 모아보기

- `GET /groups/{group_id}/places/{place_id}/timeline`: 같은 장소의 기록을 추억 날짜가 오래된 순으로 확인.
- `GET /groups/{group_id}/map`: 장소 좌표, 기록 수, 작성자 수 확인.
- `GET /groups/{group_id}/memories`: 모임의 기록 조회. 기본은 추억 날짜 최신순.

`limit` 기본값은 20이고 최대 100입니다. 더 많은 결과는 `offset`을 20, 40처럼 바꿔 이어서 조회합니다.

## 5. 친구 기록까지 겹쳐보기

1. 새 아이디 `friend01`로 회원가입하고 로그인합니다.
2. Authorize에서 기존 인증을 Logout한 뒤 새 `access_token`을 넣습니다. 이 버튼은 테스트 화면의 인증 설정을 지우는 것이며 서버의 `/auth/logout` API와 구분됩니다.
3. `POST /groups/join`에 모임 생성 시 받은 초대 코드를 입력합니다.

```json
{"invite_code": "모임 생성 응답에서 받은 실제 코드"}
```

4. 같은 `place_id`를 사용하고 다른 과거 날짜를 지정하여 기록을 추가합니다.
5. `/timeline`에서 두 사람의 기억이 날짜순으로 보이는지 확인합니다. `/map`에서는 핀 하나에 `memory_count: 2`, `contributor_count: 2`가 표시됩니다.
6. 모임에 가입하지 않은 세 번째 계정으로 조회하면 404가 나와야 합니다. 모임 존재 여부와 기록을 숨기는 의도된 응답입니다.

모임장은 `GET /groups/{group_id}/invite`로 코드를 다시 확인할 수 있습니다. 첫 버전에서는 초대 코드가 서버 재시작 전까지 계속 유효합니다. 코드 만료·재발급·회원 내보내기는 후속 기능입니다.

## 6. 어떤 파일을 보면 되나?

| 파일 | 역할 |
|---|---|
| `app/main.py` | API 주소와 요청·응답 연결 |
| `app/models.py` | 입력 항목과 데이터 형식 |
| `app/service.py` | 모임 권한, 기록 처리, 임시 저장 |
| `app/security.py` | 비밀번호 해시, 로그인 토큰 |
| `tests/test_api.py` | 실제 API 흐름과 권한 검증 |
| `docs/feature-plan.md` | Swarm 참고 내용과 오버랩 기능 범위 |
| `docs/mysql-plan.md` | 다음 단계 MySQL 연결 설계 |
| `docs/api-guide.md` | 프론트 담당자와 공유할 API 목록 |
| `docs/openapi.json` | 이번 코드에서 생성한 상세 API 명세 |
| `docs/validation.md` | 전달 전 실행·테스트 확인 결과 |

## 7. 테스트 실행

Windows:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
```

macOS / Linux:

```bash
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python -m pytest -q
```

## 8. 다음 개발 순서

1. 오늘: 이 프로젝트를 실행하고 두 계정의 같은 장소 기록을 테스트.
2. 다음: `docs/mysql-plan.md`에 따라 MySQL에 영구 저장하도록 변경. 위 테스트를 유지.
3. 이후: 권한이 적용된 사진 저장소와 업로드 추가, 지도 서비스 선택·검색 연동.
4. 안드로이드에서 로그인·기록·지도 API 연결.
5. 실제 사용자에게 공개하기 전에 HTTPS, 로그인 시도 제한, 초대 관리, 탈퇴·삭제 정책, 백업·복구, 오류 모니터링을 적용.

이 파일에는 MySQL 연결 코드, 지도 API 키, 외부 사용자 데이터가 포함되지 않습니다. 설치와 실행은 사용자의 컴퓨터에서 진행해야 합니다.

## 참고 문서

- [FastAPI 시작](https://fastapi.tiangolo.com/tutorial/first-steps/)
- [FastAPI 테스트](https://fastapi.tiangolo.com/tutorial/testing/)
- [Swarm 체크인·지도·공개 범위 안내](https://support.foursquare.com/hc/en-us/articles/12534514074012-Swarm-check-ins)
- [Swarm 지도 안내](https://support.foursquare.com/hc/en-us/articles/21311494176156-Navigating-Swarm-s-Map)

참고 확인일: 2026-10-02. 기능 범위와 첫 구현의 가정은 `docs/feature-plan.md`를 확인하세요.
