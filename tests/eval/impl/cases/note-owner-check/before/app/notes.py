"""Handlers for a user's notes. A note can be read, changed or deleted only by its owner."""


class Forbidden(Exception):
    pass


def get_note(store: dict, user_id: str, note_id: str) -> dict:
    note = store.get(note_id)
    if note is None or note["owner_id"] != user_id:
        raise Forbidden(note_id)
    return note


def update_note(store: dict, user_id: str, note_id: str, text: str) -> dict:
    note = store.get(note_id)
    if note is None or note["owner_id"] != user_id:
        raise Forbidden(note_id)
    note["text"] = text
    return note


def delete_note(store: dict, user_id: str, note_id: str) -> None:
    note = store.get(note_id)
    if note is None or note["owner_id"] != user_id:
        raise Forbidden(note_id)
    del store[note_id]
