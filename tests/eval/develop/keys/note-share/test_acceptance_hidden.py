"""Held-out acceptance tests for the note-share case. Never copied into the run before the freeze."""
import unittest

from notes.service import NotFound, NoteService, PermissionDenied


class AcceptanceTest(unittest.TestCase):
    def setUp(self):
        self.service = NoteService()
        self.note = self.service.create("alice", "plan")

    def test_ac1_owner_reads(self):
        self.assertEqual(self.service.read("alice", self.note), "plan")

    def test_ac2_shared_user_reads(self):
        self.service.share("alice", self.note, "bob")
        self.assertEqual(self.service.read("bob", self.note), "plan")

    def test_ac3_stranger_cannot_read(self):
        with self.assertRaises(PermissionDenied):
            self.service.read("carol", self.note)
        self.service.share("alice", self.note, "bob")
        with self.assertRaises(PermissionDenied):
            self.service.read("carol", self.note)

    def test_ac4_only_owner_shares(self):
        with self.assertRaises(PermissionDenied):
            self.service.share("carol", self.note, "dave")
        self.service.share("alice", self.note, "bob")
        with self.assertRaises(PermissionDenied):
            self.service.share("bob", self.note, "dave")
        with self.assertRaises(PermissionDenied):
            self.service.read("dave", self.note)

    def test_ac5_missing_note_is_not_found(self):
        with self.assertRaises(NotFound):
            self.service.read("alice", 99)
        with self.assertRaises(NotFound):
            self.service.share("alice", 99, "bob")

    def test_ac5_shares_are_per_note(self):
        other = self.service.create("alice", "diary")
        self.service.share("alice", self.note, "bob")
        with self.assertRaises(PermissionDenied):
            self.service.read("bob", other)


if __name__ == "__main__":
    unittest.main()
