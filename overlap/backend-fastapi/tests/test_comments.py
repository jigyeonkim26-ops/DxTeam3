import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.record_models import Comment
from test_records import create, world


def comment(world, record_id, user=1, group_id=10, **payload):
    body = {"content": "Test comment", "group_id": group_id, **payload}
    return world[0].post(
        f"/records/{record_id}/comments",
        headers=world[3][user],
        json=body,
    )


def comments(world, record_id, user=1, **params):
    query = "&".join(
        f"{key}={value}" for key, value in params.items() if value is not None
    )
    suffix = f"?{query}" if query else ""
    return world[0].get(
        f"/records/{record_id}/comments{suffix}", headers=world[3][user]
    )


def create_multi_group_record(world):
    response = create(world, groups=[10, 20])
    assert response.status_code == 201, response.text
    return response.json()["id"]


def test_group_context_returns_only_that_groups_comments(world):
    record_id = create_multi_group_record(world)
    group_a = comment(world, record_id, user=2, group_id=10, content="A comment")
    group_b = comment(world, record_id, user=3, group_id=20, content="B comment")
    assert group_a.status_code == 201 and group_b.status_code == 201

    listed_a = comments(world, record_id, user=2, group_id=10)
    listed_b = comments(world, record_id, user=3, group_id=20)
    assert [item["content"] for item in listed_a.json()["items"]] == ["A comment"]
    assert [item["content"] for item in listed_b.json()["items"]] == ["B comment"]
    assert listed_a.json()["items"][0]["group_id"] == 10
    assert listed_a.json()["items"][0]["group"]["id"] == 10


def test_group_context_rejects_nonmembers_for_read_and_write(world):
    record_id = create_multi_group_record(world)
    assert comments(world, record_id, user=2, group_id=20).status_code == 403
    assert comment(world, record_id, user=2, group_id=20).status_code == 403


def test_author_scope_all_returns_all_contexts_and_legacy_null(world):
    record_id = create_multi_group_record(world)
    assert comment(world, record_id, user=2, group_id=10, content="A comment").status_code == 201
    assert comment(world, record_id, user=3, group_id=20, content="B comment").status_code == 201
    with Session(world[1]) as db:
        db.add(Comment(record_id=record_id, group_id=None, author_id=1, content="Legacy"))
        db.commit()

    listed = comments(world, record_id, user=1, scope="all")
    assert listed.status_code == 200
    by_content = {item["content"]: item for item in listed.json()["items"]}
    assert by_content["A comment"]["group_id"] == 10
    assert by_content["B comment"]["group_id"] == 20
    assert by_content["Legacy"]["group_id"] is None
    assert by_content["Legacy"]["group"] is None
    assert comments(world, record_id, user=2, scope="all").status_code == 403


def test_shared_records_require_a_group_context(world):
    record_id = create(world).json()["id"]
    assert comments(world, record_id, user=1).status_code == 422
    assert comment(world, record_id, user=1, group_id=None).status_code == 422


def test_reply_must_use_the_parents_group_context(world):
    record_id = create_multi_group_record(world)
    parent = comment(world, record_id, user=2, group_id=10)
    assert parent.status_code == 201
    assert comment(
        world,
        record_id,
        user=1,
        group_id=20,
        parent_comment_id=parent.json()["id"],
    ).status_code == 422
    reply = comment(
        world,
        record_id,
        user=1,
        group_id=10,
        parent_comment_id=parent.json()["id"],
    )
    assert reply.status_code == 201


def test_private_records_allow_only_null_group_context(world):
    record_id = create(world, private=True).json()["id"]
    created = comment(world, record_id, user=1, group_id=None, content="Private")
    assert created.status_code == 201
    assert created.json()["group_id"] is None
    assert created.json()["group"] is None
    assert [item["content"] for item in comments(world, record_id).json()["items"]] == ["Private"]
    assert comment(world, record_id, user=1, group_id=10).status_code == 422
    assert comments(world, record_id, group_id=10).status_code == 422


def test_legacy_null_comments_are_hidden_from_group_context(world):
    record_id = create_multi_group_record(world)
    with Session(world[1]) as db:
        db.add(Comment(record_id=record_id, group_id=None, author_id=1, content="Legacy"))
        db.commit()
    assert comments(world, record_id, user=2, group_id=10).json()["items"] == []
    assert comments(world, record_id, user=1, scope="all").json()["total"] == 1


def test_delete_still_requires_comment_author(world):
    record_id = create(world).json()["id"]
    item = comment(world, record_id, user=2).json()
    assert world[0].delete(
        f"/records/{record_id}/comments/{item['id']}", headers=world[3][1]
    ).status_code == 403
    assert world[0].delete(
        f"/records/{record_id}/comments/{item['id']}", headers=world[3][2]
    ).status_code == 204


@pytest.mark.parametrize("private,viewer", [(True, 2), (False, 3)])
def test_record_visibility_for_comments(world, private, viewer):
    record_id = create(world, private=private).json()["id"]
    own = comment(world, record_id, group_id=None if private else 10)
    assert own.status_code == 201
    assert comments(world, record_id, user=viewer, group_id=None if private else 10).status_code == 404
    assert comment(world, record_id, user=viewer, group_id=None if private else 10).status_code == 404


@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer invalid"}])
def test_authentication_required(world, method, headers):
    record_id = create(world).json()["id"]
    path = f"/records/{record_id}/comments?group_id=10"
    if method == "DELETE":
        path = f"/records/{record_id}/comments/1"
    assert world[0].request(method, path, headers=headers, json={"content": "Hello", "group_id": 10}).status_code == 401


def test_invalid_parent_and_invalid_input_are_rejected(world):
    record_id = create(world).json()["id"]
    assert comment(world, record_id, parent_comment_id=999999).status_code == 404
    assert comment(world, record_id, content="").status_code == 422
    assert comment(world, record_id, content="a" * 1001).status_code == 422
    assert comment(world, record_id, author_id=2).status_code == 422
    with Session(world[1]) as db:
        assert db.scalar(select(func.count()).select_from(Comment).where(Comment.record_id == record_id)) == 0
