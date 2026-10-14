"""Validate shipping catalogs and prevent silent missing translations."""
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ('en', 'pt', 'es', 'fr', 'de', 'it')


def catalog(language):
    path = ROOT / 'Resources' / f'{language}.lproj' / 'Localizable.strings'
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)],
                            check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


class LocalizationTests(unittest.TestCase):
    def test_complete_catalogs_and_placeholders(self):
        english = catalog('en')
        for language in LANGUAGES:
            with self.subTest(language=language):
                translated = catalog(language)
                self.assertEqual(set(translated), set(english))
                for key, value in translated.items():
                    self.assertTrue(value.strip(), key)
                    self.assertEqual(re.findall(r'\{\d+\}', value),
                                     re.findall(r'\{\d+\}', english[key]), key)
                    self.assertNotIn('Insônia', value, key)

    def test_runtime_keys_are_translated(self):
        english = catalog('en')
        for path in [*ROOT.glob('*.swift'), *ROOT.joinpath('guardian').glob('*.swift')]:
            for key in re.findall(r'"((?:ui|status|error|recovery|safety)\.[A-Za-z]+)"', path.read_text()):
                self.assertIn(key, english, f'{path.name}: {key}')

    def test_no_duplicate_keys(self):
        for language in LANGUAGES:
            text = (ROOT / 'Resources' / f'{language}.lproj' / 'Localizable.strings').read_text()
            keys = re.findall(r'^"([^"]+)"\s*=', text, re.M)
            self.assertEqual(len(keys), len(set(keys)), language)


if __name__ == '__main__':
    unittest.main(verbosity=2)
