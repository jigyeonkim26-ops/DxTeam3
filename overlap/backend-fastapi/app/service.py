"""학습용 메모리 저장소와 서비스 규칙.

프로세스를 종료하면 데이터가 사라집니다. 각 작업을 잠금으로 묶어
동시에 요청이 와도 중복 가입이나 ID 충돌이 생기지 않게 합니다.
MySQL 도입 시 API 형식을 유지하면서 이 계층의 저장 부분을 교체합니다.
"""

from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from threading import RLock
from typing import Literal

from fastapi import HTTPException

from .models import (
    GroupCreated, GroupPublic, MapPin, MemoryInput, MemoryPublic,
    Page, PlaceInput, PlacePublic, RegisterInput, TokenOutput, UserPublic,
)
from .security import hash_password, new_token, token_digest, verify_password


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


@dataclass
class Account:
    public: UserPublic
    password_hash: str


@dataclass
class Session:
    user_id: int
    expires_at: datetime


@dataclass
class Group:
    id: int
    name: str
    owner_id: int
    member_ids: set[int]
    invite_code: str


class MemoryService:
    TOKEN_LIFETIME_SECONDS = 3600

    def __init__(self) -> None:
        self.lock = RLock()
        self.users: dict[int, Account] = {}
        self.usernames: dict[str, int] = {}
        self.sessions: dict[str, Session] = {}
        self.groups: dict[int, Group] = {}
        self.invites: dict[str, int] = {}
        self.places: dict[int, PlacePublic] = {}
        self.memories: dict[int, MemoryPublic] = {}
        self._next_ids: dict[str, int] = defaultdict(int)

    def _next_id(self, kind: str) -> int:
        self._next_ids[kind] += 1
        return self._next_ids[kind]

    def _require_group(self, user_id: int, group_id: int) -> Group:
        group = self.groups.get(group_id)
        if group is None or user_id not in group.member_ids:
            raise HTTPException(404, "가입한 모임을 찾을 수 없습니다.")
        return group

    def _require_place(self, group_id: int, place_id: int) -> PlacePublic:
        place = self.places.get(place_id)
        if place is None or place.group_id != group_id:
            raise HTTPException(404, "이 모임의 장소를 찾을 수 없습니다.")
        return place

    def _require_memory(self, group_id: int, memory_id: int) -> MemoryPublic:
        memory = self.memories.get(memory_id)
        if memory is None or memory.group_id != group_id:
            raise HTTPException(404, "이 모임의 기록을 찾을 수 없습니다.")
        return memory

    def _group_public(self, group: Group) -> GroupPublic:
        return GroupPublic(id=group.id, name=group.name, owner_id=group.owner_id,
                           member_count=len(group.member_ids))

    def register(self, data: RegisterInput) -> UserPublic:
        password_hash = hash_password(data.password.get_secret_value())
        with self.lock:
            if data.username in self.usernames:
                raise HTTPException(409, "이미 사용 중인 아이디입니다.")
            user = UserPublic(id=self._next_id("user"), username=data.username,
                              display_name=data.display_name)
            self.users[user.id] = Account(user, password_hash)
            self.usernames[user.username] = user.id
            return user

    def login(self, username: str, password: str) -> TokenOutput:
        with self.lock:
            account = self.users.get(self.usernames.get(username, -1))
        if not verify_password(account.password_hash if account else None, password):
            raise HTTPException(401, "아이디 또는 비밀번호가 올바르지 않습니다.",
                                headers={"WWW-Authenticate": "Bearer"})
        assert account is not None
        token = new_token()
        with self.lock:
            now = now_utc()
            self.sessions = {key: value for key, value in self.sessions.items()
                             if value.expires_at > now}
            self.sessions[token_digest(token)] = Session(
                account.public.id, now + timedelta(seconds=self.TOKEN_LIFETIME_SECONDS)
            )
        return TokenOutput(access_token=token, expires_in=self.TOKEN_LIFETIME_SECONDS)

    def authenticate(self, token: str) -> UserPublic:
        with self.lock:
            key = token_digest(token)
            session = self.sessions.get(key)
            if session is None or session.expires_at <= now_utc():
                self.sessions.pop(key, None)
                raise HTTPException(401, "로그인이 필요하거나 로그인 시간이 만료되었습니다.",
                                    headers={"WWW-Authenticate": "Bearer"})
            return self.users[session.user_id].public

    def logout(self, token: str) -> None:
        with self.lock:
            self.sessions.pop(token_digest(token), None)

    def create_group(self, user_id: int, name: str) -> GroupCreated:
        with self.lock:
            group_id = self._next_id("group")
            invite_code = new_token()
            group = Group(group_id, name, user_id, {user_id}, invite_code)
            self.groups[group_id] = group
            self.invites[invite_code] = group_id
            return GroupCreated(**self._group_public(group).model_dump(), invite_code=invite_code)

    def join_group(self, user_id: int, invite_code: str) -> GroupPublic:
        with self.lock:
            group_id = self.invites.get(invite_code)
            if group_id is None:
                raise HTTPException(404, "초대 코드를 확인해 주세요.")
            group = self.groups[group_id]
            group.member_ids.add(user_id)
            return self._group_public(group)

    def list_groups(self, user_id: int) -> list[GroupPublic]:
        with self.lock:
            return [self._group_public(group) for group in self.groups.values()
                    if user_id in group.member_ids]

    def get_invite(self, user_id: int, group_id: int) -> str:
        with self.lock:
            group = self._require_group(user_id, group_id)
            if group.owner_id != user_id:
                raise HTTPException(403, "모임장만 초대 코드를 조회할 수 있습니다.")
            return group.invite_code

    def add_place(self, user_id: int, group_id: int, data: PlaceInput) -> PlacePublic:
        with self.lock:
            self._require_group(user_id, group_id)
            for place in self.places.values():
                if (place.group_id == group_id and place.name.casefold() == data.name.casefold()
                        and place.address.casefold() == data.address.casefold()
                        and round(place.latitude, 6) == round(data.latitude, 6)
                        and round(place.longitude, 6) == round(data.longitude, 6)):
                    raise HTTPException(409, f"이미 등록된 장소입니다. place_id={place.id}를 사용하세요.")
            place = PlacePublic(id=self._next_id("place"), group_id=group_id, **data.model_dump())
            self.places[place.id] = place
            return place

    def list_places(self, user_id: int, group_id: int, query: str, offset: int, limit: int) -> Page[PlacePublic]:
        with self.lock:
            self._require_group(user_id, group_id)
            query = query.strip().casefold()
            items = [place for place in self.places.values() if place.group_id == group_id
                     and (query in place.name.casefold() or query in place.address.casefold())]
            return Page(items=items[offset:offset + limit], total=len(items), offset=offset, limit=limit)

    def add_memory(self, user_id: int, group_id: int, data: MemoryInput) -> MemoryPublic:
        with self.lock:
            self._require_group(user_id, group_id)
            self._require_place(group_id, data.place_id)
            now = now_utc()
            memory = MemoryPublic(id=self._next_id("memory"), group_id=group_id,
                                  author=self.users[user_id].public, created_at=now, updated_at=now,
                                  **data.model_dump())
            self.memories[memory.id] = memory
            return memory

    def get_memory(self, user_id: int, group_id: int, memory_id: int) -> MemoryPublic:
        with self.lock:
            self._require_group(user_id, group_id)
            return self._require_memory(group_id, memory_id)

    def update_memory(self, user_id: int, group_id: int, memory_id: int, data: MemoryInput) -> MemoryPublic:
        with self.lock:
            self._require_group(user_id, group_id)
            memory = self._require_memory(group_id, memory_id)
            if memory.author.id != user_id:
                raise HTTPException(403, "작성자만 기록을 수정할 수 있습니다.")
            self._require_place(group_id, data.place_id)
            updated = memory.model_copy(update={**data.model_dump(), "updated_at": now_utc()})
            self.memories[memory_id] = updated
            return updated

    def delete_memory(self, user_id: int, group_id: int, memory_id: int) -> None:
        with self.lock:
            self._require_group(user_id, group_id)
            memory = self._require_memory(group_id, memory_id)
            if memory.author.id != user_id:
                raise HTTPException(403, "작성자만 기록을 삭제할 수 있습니다.")
            del self.memories[memory_id]

    def list_memories(self, user_id: int, group_id: int, place_id: int | None,
                      date_from: date | None, date_to: date | None,
                      order: Literal["oldest", "newest"], offset: int, limit: int) -> Page[MemoryPublic]:
        with self.lock:
            self._require_group(user_id, group_id)
            if place_id is not None:
                self._require_place(group_id, place_id)
            if date_from and date_to and date_from > date_to:
                raise HTTPException(400, "시작 날짜는 종료 날짜보다 늦을 수 없습니다.")
            items = [memory for memory in self.memories.values()
                     if memory.group_id == group_id
                     and (place_id is None or memory.place_id == place_id)
                     and (date_from is None or memory.visited_on >= date_from)
                     and (date_to is None or memory.visited_on <= date_to)]
            items.sort(key=lambda memory: (memory.visited_on, memory.created_at, memory.id),
                       reverse=order == "newest")
            return Page(items=items[offset:offset + limit], total=len(items), offset=offset, limit=limit)

    def map_pins(self, user_id: int, group_id: int, offset: int, limit: int) -> Page[MapPin]:
        with self.lock:
            self._require_group(user_id, group_id)
            by_place: dict[int, list[MemoryPublic]] = defaultdict(list)
            for memory in self.memories.values():
                if memory.group_id == group_id:
                    by_place[memory.place_id].append(memory)
            items = [MapPin(place=self.places[place_id], memory_count=len(memories),
                            contributor_count=len({memory.author.id for memory in memories}),
                            first_visited_on=min(memory.visited_on for memory in memories),
                            last_visited_on=max(memory.visited_on for memory in memories))
                     for place_id, memories in sorted(by_place.items())]
            return Page(items=items[offset:offset + limit], total=len(items), offset=offset, limit=limit)
