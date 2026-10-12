import pytest
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.record_models import Comment, CommentGroup
from test_records import create, world


def comment(world, record_id, user=1, group_id=None, **payload):
    body = {"content": "Test comment", "group_id": group_id, **payload}
    return world[0].post(f"/records/{record_id}/comments", headers=world[3][user], json=body)


def comments(world, record_id, user=1, **params):
    query = "&".join(f"{key}={value}" for key, value in params.items() if value is not None)
    return world[0].get(
        f"/records/{record_id}/comments" + (f"?{query}" if query else ""),
        headers=world[3][user],
    )


def multi_record(world):
    result = create(world, groups=[10, 20])
    assert result.status_code == 201, result.text
    return result.json()["id"]


def add_user_2_to_group_20(world):
    from app.record_models import GroupMember
    with Session(world[1]) as db:
        if db.get(GroupMember, (20, 2)) is None:
            db.add(GroupMember(group_id=20, user_id=2))
            db.commit()


def test_non_author_top_level_uses_all_common_groups_and_ignores_client_group(world):
    record_id = multi_record(world)
    add_user_2_to_group_20(world)

    created = comment(world, record_id, user=2, group_id=10, content="multi")
    assert created.status_code == 201, created.text
    assert created.json()["group_id"] is None
    assert created.json()["group_ids"] == [10, 20]
    assert created.json()["is_global"] is False
    with Session(world[1]) as db:
        assert db.scalars(select(CommentGroup.group_id).where(
            CommentGroup.comment_id == created.json()["id"]
        ).order_by(CommentGroup.group_id)).all() == [10, 20]


def test_non_author_top_level_with_one_common_group_keeps_compat_group_id(world):
    record_id = multi_record(world)
    created = comment(world, record_id, user=3, group_id=10, content="single")
    assert created.status_code == 201, created.text
    assert created.json()["group_id"] == 20
    assert created.json()["group_ids"] == [20]
    assert created.json()["is_global"] is False


def test_non_author_without_a_common_group_is_forbidden(world):
    record_id = multi_record(world)
    from app.record_models import GroupMember
    with Session(world[1]) as db:
        db.execute(delete(GroupMember).where(GroupMember.group_id == 10, GroupMember.user_id == 2))
        db.commit()
    assert comment(world, record_id, user=2, content="forbidden").status_code == 403


def test_explicit_group_and_bare_shared_get_use_comment_groups_without_duplicates(world):
    record_id = multi_record(world)
    add_user_2_to_group_20(world)
    multi = comment(world, record_id, user=2, content="multi")
    only_20 = comment(world, record_id, user=3, content="only-20")
    global_comment = comment(world, record_id, user=1, content="global")
    assert all(response.status_code == 201 for response in (multi, only_20, global_comment))
    with Session(world[1]) as db:
        db.add(Comment(record_id=record_id, group_id=None, is_global=False, author_id=1, content="legacy"))
        db.commit()

    group_10 = comments(world, record_id, user=2, group_id=10)
    group_20 = comments(world, record_id, user=2, group_id=20)
    assert {item["content"] for item in group_10.json()["items"]} == {"multi", "global"}
    assert {item["content"] for item in group_20.json()["items"]} == {"multi", "only-20", "global"}
    assert comments(world, record_id, user=2, group_id=999).status_code == 404

    bare = comments(world, record_id, user=2)
    assert bare.status_code == 200
    assert {item["content"] for item in bare.json()["items"]} == {"multi", "only-20", "global"}
    assert len([item for item in bare.json()["items"] if item["content"] == "multi"]) == 1


def test_author_scope_all_includes_legacy_and_response_keeps_group_ids_contract(world):
    record_id = multi_record(world)
    add_user_2_to_group_20(world)
    assert comment(world, record_id, user=2, content="multi").status_code == 201
    global_comment = comment(world, record_id, user=1, content="global")
    assert global_comment.status_code == 201
    with Session(world[1]) as db:
        db.add(Comment(record_id=record_id, group_id=None, author_id=1, content="legacy"))
        db.commit()

    response = comments(world, record_id, user=1, scope="all")
    assert response.status_code == 200
    by_content = {item["content"]: item for item in response.json()["items"]}
    assert by_content["multi"]["group_id"] is None
    assert by_content["multi"]["group_ids"] == [10, 20]
    assert by_content["global"]["group_ids"] == [] and by_content["global"]["is_global"] is True
    assert by_content["legacy"]["group_ids"] == [] and by_content["legacy"]["is_global"] is False
    assert comments(world, record_id, user=2, scope="all").status_code == 403


def test_reply_scopes_follow_parent_associations_and_membership(world):
    record_id = multi_record(world)
    add_user_2_to_group_20(world)
    parent = comment(world, record_id, user=2, content="parent").json()

    both = comment(world, record_id, user=2, parent_comment_id=parent["id"], content="both")
    single = comment(world, record_id, user=3, parent_comment_id=parent["id"], content="single")
    author = comment(world, record_id, user=1, parent_comment_id=parent["id"], content="author")
    assert both.status_code == single.status_code == author.status_code == 201
    assert both.json()["group_id"] is None and both.json()["group_ids"] == [10, 20]
    assert single.json()["group_id"] == 20 and single.json()["group_ids"] == [20]
    assert author.json()["group_id"] is None and author.json()["group_ids"] == [10, 20]
    assert author.json()["is_global"] is False


def test_global_and_legacy_parent_reply_policies(world):
    record_id = multi_record(world)
    add_user_2_to_group_20(world)
    global_parent = comment(world, record_id, user=1, content="global parent").json()
    viewer_reply = comment(world, record_id, user=2, parent_comment_id=global_parent["id"], content="viewer reply")
    author_reply = comment(world, record_id, user=1, parent_comment_id=global_parent["id"], content="author reply")
    assert viewer_reply.status_code == author_reply.status_code == 201
    assert viewer_reply.json()["group_ids"] == [10, 20] and viewer_reply.json()["is_global"] is False
    assert author_reply.json()["group_ids"] == [] and author_reply.json()["is_global"] is True

    with Session(world[1]) as db:
        legacy = Comment(record_id=record_id, group_id=None, is_global=False, author_id=1, content="legacy parent")
        db.add(legacy)
        db.commit()
        db.refresh(legacy)
        legacy_id = legacy.id
    legacy_reply = comment(world, record_id, user=1, parent_comment_id=legacy_id, content="legacy reply")
    assert legacy_reply.status_code == 201
    assert legacy_reply.json()["group_id"] is None
    assert legacy_reply.json()["group_ids"] == []
    assert legacy_reply.json()["is_global"] is False
    assert comment(world, record_id, user=2, parent_comment_id=legacy_id).status_code == 403


def test_private_comments_stay_unscoped(world):
    record_id = create(world, private=True).json()["id"]
    created = comment(world, record_id, user=1, content="private")
    assert created.status_code == 201
    assert created.json()["group_id"] is None
    assert created.json()["group_ids"] == []
    assert created.json()["is_global"] is False
    assert comment(world, record_id, user=1, group_id=10).status_code == 422


def test_comment_delete_cascades_comment_group_rows(world):
    record_id = multi_record(world)
    add_user_2_to_group_20(world)
    created = comment(world, record_id, user=2, content="delete me")
    assert created.status_code == 201
    comment_id = created.json()["id"]
    with Session(world[1]) as db:
        assert db.scalar(select(func.count()).select_from(CommentGroup).where(
            CommentGroup.comment_id == comment_id
        )) == 2
        # SQLite disables FK enforcement by default; enable it only for this
        # disposable test connection so the production ON DELETE CASCADE
        # contract is exercised without changing the real DB.
        db.connection().exec_driver_sql("PRAGMA foreign_keys=ON")
    assert world[0].delete(f"/records/{record_id}/comments/{comment_id}", headers=world[3][2]).status_code == 204
    with Session(world[1]) as db:
        assert db.scalar(select(func.count()).select_from(CommentGroup).where(
            CommentGroup.comment_id == comment_id
        )) == 0


@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
def test_comment_authentication_is_required(world, method):
    record_id = multi_record(world)
    path = f"/records/{record_id}/comments"
    if method == "DELETE":
        path += "/1"
    response = world[0].request(method, path, json={"content": "Hello"})
    assert response.status_code == 401
