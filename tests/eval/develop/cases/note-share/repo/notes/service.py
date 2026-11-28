"""Note operations called by the HTTP handlers of the internal notes app."""
from notes.store import NoteStore


class NotFound(Exception):
    pass


class NoteService:
    def __init__(self, store=None):
        self.store = store or NoteStore()

    def create(self, user, body):
        return self.store.add(user, body)

    def read(self, user, note_id):
        note = self.store.get(note_id)
        if note is None:
            raise NotFound(note_id)
        return note["body"]
