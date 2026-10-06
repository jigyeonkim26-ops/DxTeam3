# ===== 오버랩 백엔드 실행 방법 =====
#
# 1. VS Code에서 overlap-backend 폴더 열기
#    app 폴더와 requirements.txt가 함께 보이는 위치여야 함.
#
# 2. 상단 메뉴에서 [터미널] → [새 터미널] 클릭
#    터미널 위치도 overlap-backend 폴더인지 확인.
#
# 3. 터미널에 아래 명령어 입력
#    앞의 #은 빼고 명령어만 복사해서 실행!
#
#    .\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
#
# 4. 터미널에 아래 메시지가 나오면 서버 실행 완료
#    Application startup complete.
#
# 5. 브라우저에서 아래 주소 열기
#    http://127.0.0.1:8000/docs
#    → 회원가입, 로그인, 장소 검색 등을 테스트하는 화면
#
#    http://127.0.0.1:8000/health
#    → {"status":"ok","storage":"memory"}가 나오면 응답 정상
#
# 6. 서버를 사용하는 동안 실행 중인 터미널을 유지하기
#    서버 종료: 해당 터미널에서 Ctrl + C
#    다시 실행: 3번 명령어 입력
#
# 참고:
# - 현재 버전은 MySQL 연결 전이며 데이터를 메모리에 저장함.
# - 서버 종료 또는 코드 수정에 따른 재시작 시 데이터가 초기화됨.
# - /docs는 백엔드 테스트 화면이며 실제 안드로이드 앱 화면은 아님.

"""요청을 받는 API 입구. 실행: python -m uvicorn app.main:app --reload"""

from datetime import date
from typing import Annotated, Literal

from fastapi import Depends, FastAPI, HTTPException, Query, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .kakao import search_places
from .models import (
    GroupCreated,
    GroupInput,
    GroupPublic,
    InviteOutput,
    JoinInput,
    LoginInput,
    MapPin,
    MemoryInput,
    MemoryPublic,
    Page,
    PlaceInput,
    PlacePublic,
    RegisterInput,
    TokenOutput,
    UserPublic,
)
from .service import MemoryService


Offset = Annotated[int, Query(ge=0)]
Limit = Annotated[int, Query(ge=1, le=100)]


def create_app(service: MemoryService | None = None) -> FastAPI:
    service = service if service is not None else MemoryService()

    api = FastAPI(
        title="오버랩 Backend — 시작 프로젝트",
        version="0.1.0",
        description=(
            "모임 사람들의 장소별 기억을 모아보는 API입니다. "
            "**학습용 메모리 저장: 서버 종료·코드 수정에 따른 재시작 시 데이터가 사라집니다.** "
            "회원가입 → 로그인 → access_token 인증 → 모임 생성 순서로 시작하세요. "
            "카카오 장소 검색은 /places/search에서 제공합니다. "
            "MySQL·사진 업로드는 다음 단계입니다."
        ),
    )

    api.state.service = service
    bearer = HTTPBearer(auto_error=False)

    def current_token(
        credentials: Annotated[
            HTTPAuthorizationCredentials | None,
            Depends(bearer),
        ],
    ) -> str:
        if credentials is None or credentials.scheme.lower() != "bearer":
            raise HTTPException(
                status_code=401,
                detail="먼저 로그인해 주세요.",
                headers={"WWW-Authenticate": "Bearer"},
            )

        return credentials.credentials

    def current_user(
        token: Annotated[str, Depends(current_token)],
    ) -> UserPublic:
        return service.authenticate(token)

    @api.exception_handler(RequestValidationError)
    async def invalid_request(_request, exc: RequestValidationError):
        # 입력 원문, 특히 비밀번호가 오류 응답에 포함되지 않도록 필요한 정보만 전달
        errors = [
            {
                "loc": list(error["loc"]),
                "msg": error["msg"],
                "type": error["type"],
            }
            for error in exc.errors()
        ]

        return JSONResponse(
            status_code=422,
            content={"detail": errors},
        )

    @api.get("/", tags=["0. 실행 확인"])
    def root():
        return {
            "service": "overlap",
            "version": "0.1.0",
            "docs": "/docs",
            "storage": "memory",
            "notice": "서버를 재시작하면 데이터가 초기화됩니다.",
        }

    @api.get("/health", tags=["0. 실행 확인"])
    def health():
        return {
            "status": "ok",
            "storage": "memory",
        }

    @api.get(
        "/places/search",
        tags=["3. 장소"],
        summary="카카오 장소 검색",
    )
    def search_kakao_places(
        query: Annotated[
            str,
            Query(min_length=1, max_length=120),
        ],
        _: Annotated[
            UserPublic,
            Depends(current_user),
        ],
    ):
        return search_places(query)

    @api.post(
        "/auth/register",
        response_model=UserPublic,
        status_code=201,
        tags=["1. 회원"],
        summary="회원가입",
    )
    def register(data: RegisterInput):
        return service.register(data)

    @api.post(
        "/auth/login",
        response_model=TokenOutput,
        tags=["1. 회원"],
        summary="로그인",
    )
    def login(data: LoginInput):
        return service.login(
            data.email,
            data.password.get_secret_value(),
        )

    @api.get(
        "/auth/me",
        response_model=UserPublic,
        tags=["1. 회원"],
        summary="로그인한 사용자",
    )
    def me(
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
    ):
        return user

    @api.post(
        "/auth/logout",
        status_code=204,
        tags=["1. 회원"],
        summary="현재 로그인 해제",
    )
    def logout(
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
        token: Annotated[
            str,
            Depends(current_token),
        ],
    ):
        service.logout(token)
        return Response(status_code=204)

    @api.post(
        "/groups",
        response_model=GroupCreated,
        status_code=201,
        tags=["2. 모임"],
        summary="모임 만들기 — 만든 사람은 자동 가입",
    )
    def create_group(
        data: GroupInput,
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
    ):
        return service.create_group(user.id, data.name)

    @api.post(
        "/groups/join",
        response_model=GroupPublic,
        tags=["2. 모임"],
        summary="초대 코드로 모임 가입",
    )
    def join_group(
        data: JoinInput,
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
    ):
        return service.join_group(user.id, data.invite_code)

    @api.get(
        "/groups",
        response_model=list[GroupPublic],
        tags=["2. 모임"],
        summary="내 모임 목록",
    )
    def list_groups(
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
    ):
        return service.list_groups(user.id)

    @api.get(
        "/groups/{group_id}/invite",
        response_model=InviteOutput,
        tags=["2. 모임"],
        summary="모임장만 초대 코드 조회",
    )
    def get_invite(
        group_id: int,
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
    ):
        return InviteOutput(
            invite_code=service.get_invite(user.id, group_id),
        )

    @api.post(
        "/groups/{group_id}/places",
        response_model=PlacePublic,
        status_code=201,
        tags=["3. 장소"],
        summary="모임에 장소 수동 등록",
    )
    def add_place(
        group_id: int,
        data: PlaceInput,
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
    ):
        return service.add_place(user.id, group_id, data)

    @api.get(
        "/groups/{group_id}/places",
        response_model=Page[PlacePublic],
        tags=["3. 장소"],
        summary="우리 모임에 등록된 장소 검색",
    )
    def list_places(
        group_id: int,
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
        query: Annotated[
            str,
            Query(max_length=120),
        ] = "",
        offset: Offset = 0,
        limit: Limit = 20,
    ):
        return service.list_places(
            user.id,
            group_id,
            query,
            offset,
            limit,
        )

    @api.post(
        "/groups/{group_id}/memories",
        response_model=MemoryPublic,
        status_code=201,
        tags=["4. 기록"],
        summary="장소에 추억 기록 — 과거 날짜 지원",
    )
    def add_memory(
        group_id: int,
        data: MemoryInput,
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
    ):
        return service.add_memory(user.id, group_id, data)

    @api.get(
        "/groups/{group_id}/memories",
        response_model=Page[MemoryPublic],
        tags=["4. 기록"],
        summary="모임 기록 조회·장소 및 날짜 필터",
    )
    def list_memories(
        group_id: int,
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
        place_id: Annotated[
            int | None,
            Query(gt=0),
        ] = None,
        date_from: date | None = None,
        date_to: date | None = None,
        order: Literal["oldest", "newest"] = "newest",
        offset: Offset = 0,
        limit: Limit = 20,
    ):
        return service.list_memories(
            user.id,
            group_id,
            place_id,
            date_from,
            date_to,
            order,
            offset,
            limit,
        )

    @api.get(
        "/groups/{group_id}/memories/{memory_id}",
        response_model=MemoryPublic,
        tags=["4. 기록"],
        summary="기록 하나 조회",
    )
    def get_memory(
        group_id: int,
        memory_id: int,
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
    ):
        return service.get_memory(
            user.id,
            group_id,
            memory_id,
        )

    @api.put(
        "/groups/{group_id}/memories/{memory_id}",
        response_model=MemoryPublic,
        tags=["4. 기록"],
        summary="내 기록 수정 — 세 항목 모두 보내기",
    )
    def update_memory(
        group_id: int,
        memory_id: int,
        data: MemoryInput,
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
    ):
        return service.update_memory(
            user.id,
            group_id,
            memory_id,
            data,
        )

    @api.delete(
        "/groups/{group_id}/memories/{memory_id}",
        status_code=204,
        tags=["4. 기록"],
        summary="내 기록 삭제",
    )
    def delete_memory(
        group_id: int,
        memory_id: int,
        user: Annotated[
            UserPublic,
            Depends(current_user,
            ),
        ],
    ):
        service.delete_memory(
            user.id,
            group_id,
            memory_id,
        )
        return Response(status_code=204)

    @api.get(
        "/groups/{group_id}/places/{place_id}/timeline",
        response_model=Page[MemoryPublic],
        tags=["5. 오버랩 모아보기"],
        summary="같은 장소의 여러 사람 기억을 추억 날짜순으로 보기",
    )
    def timeline(
        group_id: int,
        place_id: int,
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
        offset: Offset = 0,
        limit: Limit = 20,
    ):
        return service.list_memories(
            user.id,
            group_id,
            place_id,
            None,
            None,
            "oldest",
            offset,
            limit,
        )

    @api.get(
        "/groups/{group_id}/map",
        response_model=Page[MapPin],
        tags=["5. 오버랩 모아보기"],
        summary="지도 핀용 장소·기록 수·작성자 수·날짜 범위",
    )
    def map_pins(
        group_id: int,
        user: Annotated[
            UserPublic,
            Depends(current_user),
        ],
        offset: Offset = 0,
        limit: Limit = 20,
    ):
        return service.map_pins(
            user.id,
            group_id,
            offset,
            limit,
        )

    return api


app = create_app()
