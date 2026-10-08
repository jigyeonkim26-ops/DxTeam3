import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.record_models import Comment
from test_records import create, world


def comment(world, record_id, user=1, **payload):
    return world[0].post(f"/records/{record_id}/comments", headers=world[3][user],
                         json={"content": "Test comment", **payload})


def test_create_list_and_delete_comment(world):
    record_id = create(world).json()["id"]
    response = comment(world, record_id, content="  Comment text  ")
    assert response.status_code == 201
    item = response.json()
    assert item["content"] == "Comment text"
    assert item["record_id"] == record_id and item["author_id"] == 1
    assert item["parent_comment_id"] is None
    assert item["created_at"] and item["updated_at"]
    client, _, _, headers = world
    listed = client.get(f"/records/{record_id}/comments", headers=headers[2])
    assert listed.status_code == 200
    assert listed.json() == dict(items=[item], total=1, offset=0, limit=20)
    assert client.delete(f"/records/{record_id}/comments/{item['id']}", headers=headers[1]).status_code == 204
    assert client.get(f"/records/{record_id}/comments", headers=headers[1]).json()["total"] == 0


def test_other_author_cannot_delete_even_record_author(world):
    record_id = create(world).json()["id"]
    item = comment(world, record_id, user=2).json()
    response = world[0].delete(f"/records/{record_id}/comments/{item['id']}?user_id=2", headers=world[3][1])
    assert response.status_code == 403
    with Session(world[1]) as db:
        assert db.get(Comment, item["id"]) is not None


def test_replies_and_parent_deletion_preserve_other_authors(world):
    record_id = create(world).json()["id"]
    parent = comment(world, record_id).json()
    response = comment(world, record_id, user=2, parent_comment_id=parent["id"])
    assert response.status_code == 201
    reply = response.json()
    assert reply["parent_comment_id"] == parent["id"]
    client, _, _, headers = world
    listed = client.get(f"/records/{record_id}/comments?limit=1&offset=1", headers=headers[1]).json()
    assert listed == dict(items=[reply], total=2, offset=1, limit=1)
    parent_path = f"/records/{record_id}/comments/{parent['id']}"
    assert client.delete(parent_path, headers=headers[1]).status_code == 409
    assert client.delete(f"/records/{record_id}/comments/{reply['id']}", headers=headers[2]).status_code == 204
    assert client.delete(parent_path, headers=headers[1]).status_code == 204


@pytest.mark.parametrize("parent", [999999, "different_record"])
def test_invalid_parent_rejected(world, parent):
    record_id = create(world).json()["id"]
    if parent == "different_record":
        other_id = create(world).json()["id"]
        parent = comment(world, other_id).json()["id"]
    assert comment(world, record_id, parent_comment_id=parent).status_code == 404
    with Session(world[1]) as db:
        assert db.scalar(select(func.count()).select_from(Comment).where(Comment.record_id == record_id)) == 0


@pytest.mark.parametrize("private,viewer", [(True, 2), (False, 3)])
def test_record_visibility_for_comments(world, private, viewer):
    record_id = create(world, private=private).json()["id"]
    own = comment(world, record_id)
    assert own.status_code == 201
    path = f"/records/{record_id}/comments"
    assert world[0].get(path, headers=world[3][viewer]).status_code == 404
    assert comment(world, record_id, user=viewer).status_code == 404
    assert world[0].delete(path + f"/{own.json()['id']}", headers=world[3][viewer]).status_code == 404


@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer invalid"}])
def test_authentication_required(world, method, headers):
    record_id = create(world).json()["id"]
    path = f"/records/{record_id}/comments" + ("/1" if method == "DELETE" else "")
    assert world[0].request(method, path, headers=headers, json={"content": "Hello"}).status_code == 401


def test_missing_record_and_comment_ids(world):
    client, _, _, headers = world
    assert client.get("/records/999999/comments", headers=headers[1]).status_code == 404
    assert comment(world, 999999).status_code == 404
    record_id = create(world).json()["id"]
    assert client.delete(f"/records/{record_id}/comments/999999", headers=headers[1]).status_code == 404
    other_id = create(world).json()["id"]
    item = comment(world, other_id).json()
    assert client.delete(f"/records/{record_id}/comments/{item['id']}", headers=headers[1]).status_code == 404


@pytest.mark.parametrize("content", ["", "   \n\t", "a" * 1001])
def test_empty_and_oversized_comments_rejected(world, content):
    record_id = create(world).json()["id"]
    assert comment(world, record_id, content=content).status_code == 422
    with Session(world[1]) as db:
        assert db.scalar(select(func.count()).select_from(Comment)) == 0


def test_maximum_length_and_authenticated_author(world):
    record_id = create(world).json()["id"]
    response = world[0].post(f"/records/{record_id}/comments?user_id=2", headers=world[3][1],
                             json={"content": "a" * 1000})
    assert response.status_code == 201
    assert response.json()["author_id"] == 1
    assert comment(world, record_id, user_id=2).status_code == 422
    assert comment(world, record_id, author_id=2).status_code == 422
