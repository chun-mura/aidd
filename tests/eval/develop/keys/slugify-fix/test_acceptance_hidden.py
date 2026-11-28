"""Held-out acceptance tests for the slugify-fix case. Never copied into the run before the freeze."""
import unittest

from textutil import slugify


class AcceptanceTest(unittest.TestCase):
    def test_ac1_collapses_runs_of_separators(self):
        self.assertEqual(slugify("Hello,  World!"), "hello-world")
        self.assertEqual(slugify("a -- b"), "a-b")

    def test_ac2_strips_leading_and_trailing_hyphens(self):
        self.assertEqual(slugify("  -Draft- "), "draft")

    def test_ac3_no_alphanumerics_gives_empty(self):
        self.assertEqual(slugify("!!!"), "")
        self.assertEqual(slugify(""), "")

    def test_ac4_keeps_lowercasing(self):
        self.assertEqual(slugify("Hello World"), "hello-world")
        self.assertEqual(slugify("ABC123"), "abc123")


if __name__ == "__main__":
    unittest.main()
