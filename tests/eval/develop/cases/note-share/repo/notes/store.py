"""In-memory note store used by the notes service."""


class NoteStore:
    def __init__(self):
        self._notes = {}
        self._next_id = 1

    def add(self, owner, body):
        note_id = self._next_id
        self._next_id += 1
        self._notes[note_id] = {"id": note_id, "owner": owner, "body": body}
        return note_id

    def get(self, note_id):
        return self._notes.get(note_id)
