import unittest

from textutil import slugify


class SlugifyTest(unittest.TestCase):
    def test_lowercases_and_replaces_a_space(self):
        self.assertEqual(slugify("Hello World"), "hello-world")


if __name__ == "__main__":
    unittest.main()
