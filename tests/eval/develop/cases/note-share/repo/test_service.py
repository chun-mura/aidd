import unittest

from notes.service import NotFound, NoteService


class NoteServiceTest(unittest.TestCase):
    def test_owner_reads_own_note(self):
        service = NoteService()
        note_id = service.create("alice", "shopping list")
        self.assertEqual(service.read("alice", note_id), "shopping list")

    def test_missing_note_is_not_found(self):
        with self.assertRaises(NotFound):
            NoteService().read("alice", 99)


if __name__ == "__main__":
    unittest.main()
