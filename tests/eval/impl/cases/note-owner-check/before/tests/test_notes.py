import pytest

from app.notes import Forbidden, delete_note, get_note, update_note


def make_store():
    return {"n1": {"owner_id": "alice", "text": "hello"}}


def test_owner_can_read_update_and_delete():
    store = make_store()
    assert get_note(store, "alice", "n1")["text"] == "hello"
    assert update_note(store, "alice", "n1", "bye")["text"] == "bye"
    delete_note(store, "alice", "n1")
    assert "n1" not in store


def test_other_user_cannot_read():
    with pytest.raises(Forbidden):
        get_note(make_store(), "bob", "n1")
