import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.record_models import Comment, CommentGroup, GroupMember
from test_records import create, world


def comment(world, record_id, user=1, **payload):
    return world[0].post(f"/records/{record_id}/comments", headers=world[3][user],
                         json={"content": "Test comment", **payload})


def comments(world, record_id, user=1, **params):
    query = "&".join(f"{key}={value}" for key, value in params.items() if value is not None)
    return world[0].get(f"/records/{record_id}/comments" + (f"?{query}" if query else ""),
                        headers=world[3][user])


def multi_record(world):
    response = create(world, groups=[10, 20])
    assert response.status_code == 201
    return response.json()["id"]


def join_20(world, user_id=2):
    with Session(world[1]) as db:
        if db.get(GroupMember, (20, user_id)) is None:
            db.add(GroupMember(group_id=20, user_id=user_id))
            db.commit()


def test_multi_group_top_level_and_group_ids(world):
    record_id = multi_record(world)
    join_20(world)
    response = comment(world, record_id, user=2, group_id=10, content="multi")
    assert response.status_code == 201
    item = response.json()
    assert item["group_id"] is None and item["group_ids"] == [10, 20]
    with Session(world[1]) as db:
        assert db.scalars(select(CommentGroup.group_id).where(CommentGroup.comment_id == item["id"])
                          .order_by(CommentGroup.group_id)).all() == [10, 20]


def test_bare_get_is_distinct_and_excludes_legacy(world):
    record_id = multi_record(world)
    join_20(world)
    assert comment(world, record_id, user=2, content="multi").status_code == 201
    assert comment(world, record_id, user=3, content="only20").status_code == 201
    assert comment(world, record_id, user=1, content="global").status_code == 201
    with Session(world[1]) as db:
        db.add(Comment(record_id=record_id, group_id=None, author_id=1, content="legacy"))
        db.commit()
    response = comments(world, record_id, user=2)
    assert {item["content"] for item in response.json()["items"]} == {"multi", "only20", "global"}


def test_reply_policy_and_author_scope_all(world):
    record_id = multi_record(world)
    join_20(world)
    parent = comment(world, record_id, user=2, content="parent").json()
    reply = comment(world, record_id, user=3, parent_comment_id=parent["id"], content="reply")
    assert reply.status_code == 201 and reply.json()["group_ids"] == [20]
    author_reply = comment(world, record_id, user=1, parent_comment_id=parent["id"], content="author")
    assert author_reply.json()["group_ids"] == [10, 20] and not author_reply.json()["is_global"]
    assert comments(world, record_id, user=1, scope="all").status_code == 200


def test_global_and_legacy_reply_policy(world):
    record_id = multi_record(world)
    join_20(world)
    global_parent = comment(world, record_id, user=1, content="global").json()
    assert comment(world, record_id, user=2, parent_comment_id=global_parent["id"]).json()["group_ids"] == [10, 20]
    assert comment(world, record_id, user=1, parent_comment_id=global_parent["id"]).json()["is_global"]
    with Session(world[1]) as db:
        legacy = Comment(record_id=record_id, group_id=None, author_id=1, content="legacy")
        db.add(legacy); db.commit(); db.refresh(legacy)
    assert comment(world, record_id, user=1, parent_comment_id=legacy.id).status_code == 201
    assert comment(world, record_id, user=2, parent_comment_id=legacy.id).status_code == 403


def test_delete_cascades_comment_groups(world):
    record_id = multi_record(world)
    join_20(world)
    item = comment(world, record_id, user=2).json()
    with Session(world[1]) as db:
        db.connection().exec_driver_sql("PRAGMA foreign_keys=ON")
        assert db.scalar(select(func.count()).select_from(CommentGroup).where(CommentGroup.comment_id == item["id"])) == 2
    assert world[0].delete(f"/records/{record_id}/comments/{item['id']}", headers=world[3][2]).status_code == 204
    with Session(world[1]) as db:
        assert db.scalar(select(func.count()).select_from(CommentGroup).where(CommentGroup.comment_id == item["id"])) == 0


@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
def test_authentication_required(world, method):
    record_id = multi_record(world)
    path = f"/records/{record_id}/comments" + ("/1" if method == "DELETE" else "")
    assert world[0].request(method, path, json={"content": "x"}).status_code == 401
