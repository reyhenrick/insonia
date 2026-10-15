from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

FIXTURE_GENERATOR = r'''
import CryptoKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let trusted = Curve25519.Signing.PrivateKey()
let untrusted = Curve25519.Signing.PrivateKey()
let archive = Data("PK\u{3}\u{4}Insonia signature fixture\n".utf8)
let archiveSignature = try trusted.signature(for: archive).base64EncodedString()
let otherArchiveSignature = try untrusted.signature(for: archive).base64EncodedString()
let enclosure = """
<enclosure url="https://github.com/reyhenrick/insonia/releases/download/v1.3.0/Insonia-macOS.zip" length="\(archive.count)" type="application/octet-stream" sparkle:edSignature="\(archiveSignature)"/>
"""
let xml = """
<?xml version="1.0" encoding="utf-8"?>
<!-- sparkle-sign-warning: generated public test fixture -->
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
<channel><title>Insonia</title><item>
<title>Insonia 1.3.0</title>
<sparkle:version>4</sparkle:version>
<sparkle:shortVersionString>1.3.0</sparkle:shortVersionString>
<description sparkle:format="plain-text"><![CDATA[Proteção · 更新 · café]]></description>
<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
\(enclosure)
</item></channel></rss>

"""

func write(_ name: String, _ data: Data) throws {
    try data.write(to: directory.appendingPathComponent(name))
}

func signed(_ data: Data, key: Curve25519.Signing.PrivateKey) throws -> Data {
    let signature = try key.signature(for: data).base64EncodedString()
    return data + Data("<!-- sparkle-signatures:\nedSignature: \(signature)\nlength: \(data.count)\n-->\n".utf8)
}

try write("public-key.txt", Data(trusted.publicKey.rawRepresentation.base64EncodedString().utf8))
try write("untrusted-public-key.txt", Data(untrusted.publicKey.rawRepresentation.base64EncodedString().utf8))
try write("Insonia-macOS.zip", archive)
var changedArchive = archive
changedArchive[0] ^= 1
try write("changed.zip", changedArchive)
try write("truncated.zip", Data(archive.dropLast()))
try write("valid.xml", signed(Data(xml.utf8), key: trusted))
try write("unsigned.xml", Data(xml.utf8))
try write("other-feed-key.xml", signed(Data(xml.utf8), key: untrusted))
try write("utf16.xml", signed(xml.data(using: .utf16LittleEndian)!, key: trusted))

let variants = [
    "valid-build-tag": xml.replacingOccurrences(of: "/download/v1.3.0/", with: "/download/v1.3.0-build.4/"),
    "wrong-build-tag": xml.replacingOccurrences(of: "/download/v1.3.0/", with: "/download/v1.3.0-build.5/"),
    "wrong-version-build-tag": xml.replacingOccurrences(of: "/download/v1.3.0/", with: "/download/v1.4.0-build.4/"),
    "noncanonical-build-tag": xml.replacingOccurrences(of: "/download/v1.3.0/", with: "/download/v1.3.0-build.04/"),
    "other-archive-key": xml.replacingOccurrences(of: archiveSignature, with: otherArchiveSignature),
    "wrong-build": xml.replacingOccurrences(of: "<sparkle:version>4", with: "<sparkle:version>5"),
    "wrong-version": xml.replacingOccurrences(of: "<sparkle:shortVersionString>1.3.0", with: "<sparkle:shortVersionString>1.3.1"),
    "wrong-length": xml.replacingOccurrences(of: "length=\"\(archive.count)\"", with: "length=\"\(archive.count + 1)\""),
    "latest-url": xml.replacingOccurrences(of: "/download/v1.3.0/", with: "/latest/download/"),
    "wrong-tag": xml.replacingOccurrences(of: "/download/v1.3.0/", with: "/download/v1.4.0/"),
    "wrong-host": xml.replacingOccurrences(of: "https://github.com/", with: "https://example.invalid/"),
    "insecure-url": xml.replacingOccurrences(of: "https://github.com/", with: "http://github.com/"),
    "missing-archive-signature": xml.replacingOccurrences(of: " sparkle:edSignature=\"\(archiveSignature)\"", with: ""),
    "invalid-archive-signature": xml.replacingOccurrences(of: archiveSignature, with: "not-base64"),
    "duplicate-version": xml.replacingOccurrences(of: "<sparkle:version>4</sparkle:version>", with: "<sparkle:version>4</sparkle:version><sparkle:version>5</sparkle:version>"),
    "nested-version": xml.replacingOccurrences(of: "<sparkle:version>4</sparkle:version>", with: "<sparkle:version><value>4</value></sparkle:version>"),
    "duplicate-enclosure": xml.replacingOccurrences(of: enclosure, with: enclosure + enclosure),
    "duplicate-item": xml.replacingOccurrences(of: "</channel>", with: "<item/></channel>"),
    "duplicate-channel": xml.replacingOccurrences(of: "</rss>", with: "<channel/></rss>"),
    "delta": xml.replacingOccurrences(of: "</item>", with: "<sparkle:deltas/></item>"),
    "delta-attribute": xml.replacingOccurrences(of: "<enclosure ", with: "<enclosure sparkle:deltaFrom=\"3\" "),
    "enclosure-build": xml.replacingOccurrences(of: "<enclosure ", with: "<enclosure sparkle:version=\"5\" "),
    "enclosure-version": xml.replacingOccurrences(of: "<enclosure ", with: "<enclosure sparkle:shortVersionString=\"1.3.1\" "),
    "external-notes": xml.replacingOccurrences(of: "</item>", with: "<sparkle:releaseNotesLink>https://example.invalid/notes</sparkle:releaseNotesLink></item>"),
    "wrong-namespace": xml.replacingOccurrences(of: "http://www.andymatuschak.org/xml-namespaces/sparkle", with: "https://example.invalid/sparkle"),
    "rebound-namespace": xml.replacingOccurrences(of: "<item>", with: "<item xmlns:sparkle=\"https://example.invalid/sparkle\">"),
    "doctype": xml.replacingOccurrences(of: "<rss ", with: "<!DOCTYPE rss [<!ENTITY external SYSTEM \"file:///nonexistent-insonia-external-entity\">]><rss "),
    "broken-xml": xml.replacingOccurrences(of: "</item>", with: "</not-item>"),
    "wrong-content-type": xml.replacingOccurrences(of: "application/octet-stream", with: "text/html"),
]
for (name, value) in variants {
    try write(name + ".xml", signed(Data(value.utf8), key: trusted))
}
'''


class UpdateSignatureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (ROOT / 'build').mkdir(exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix='update-signature-tests-', dir=ROOT / 'build')
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)
        cls.verifier = cls.directory / 'verify-update'
        subprocess.run(['xcrun', 'swiftc', str(ROOT / 'scripts/verify-update.swift'), '-o', str(cls.verifier)],
                       check=True, capture_output=True, text=True)
        generator = cls.directory / 'fixtures.swift'
        generator.write_text(FIXTURE_GENERATOR)
        subprocess.run(['xcrun', 'swift', str(generator), str(cls.directory)],
                       check=True, capture_output=True, text=True)
        cls.public_key = (cls.directory / 'public-key.txt').read_text()

    def verify(self, feed='valid.xml', archive='Insonia-macOS.zip', key=None, build='4', version='1.3.0'):
        return subprocess.run([str(self.verifier), str(self.directory / feed), str(self.directory / archive),
                               self.public_key if key is None else key, build, version],
                              capture_output=True, text=True)

    def rejected(self, expected, **arguments):
        result = self.verify(**arguments)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(expected, result.stderr)
        self.assertNotIn('Verified signed update:', result.stdout)

    def test_valid_feed_and_archive(self):
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Verified signed update: Insonia 1.3.0, build 4', result.stdout)

    def test_interpreted_cli(self):
        result = subprocess.run(['xcrun', 'swift', str(ROOT / 'scripts/verify-update.swift'),
                                 str(self.directory / 'valid.xml'), str(self.directory / 'Insonia-macOS.zip'),
                                 self.public_key, '4', '1.3.0'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_changed_archive(self):
        self.rejected('Archive signature verification failed', archive='changed.zip')

    def test_truncated_archive(self):
        self.rejected('Archive length mismatch', archive='truncated.zip')

    def test_changed_feed(self):
        original = (self.directory / 'valid.xml').read_bytes()
        (self.directory / 'changed-feed.xml').write_bytes(original.replace(b'<title>Insonia</title>', b'<title>INSONIA</title>'))
        self.rejected('Feed signature verification failed', feed='changed-feed.xml')

    def test_unknown_public_key(self):
        self.rejected('Feed signature verification failed', key=(self.directory / 'untrusted-public-key.txt').read_text())

    def test_feed_signed_with_unknown_key(self):
        self.rejected('Feed signature verification failed', feed='other-feed-key.xml')

    def test_archive_signed_with_unknown_key(self):
        self.rejected('Archive signature verification failed', feed='other-archive-key.xml')

    def test_invalid_public_key(self):
        for key in ('', 'not-base64', self.public_key[:-1], self.public_key + '\n'):
            with self.subTest(key_length=len(key)):
                self.rejected('Invalid public key', key=key)

    def test_unsigned_feed(self):
        self.rejected('Missing signed-feed trailer', feed='unsigned.xml')

    def test_signed_feed_length(self):
        original = (self.directory / 'valid.xml').read_bytes()
        prefix = original.split(b'<!-- sparkle-signatures:\n')[0]
        altered = original.replace(f'\nlength: {len(prefix)}\n'.encode(), b'\nlength: 1\n')
        (self.directory / 'wrong-feed-length.xml').write_bytes(altered)
        self.rejected('Signed-feed length mismatch', feed='wrong-feed-length.xml')

    def test_signature_trailer_must_be_last(self):
        original = (self.directory / 'valid.xml').read_bytes()
        (self.directory / 'trailing.xml').write_bytes(original + b'<!-- unsigned -->\n')
        self.rejected('Malformed signed-feed trailer or unsigned trailing data', feed='trailing.xml')

    def test_duplicate_signature_trailer(self):
        original = (self.directory / 'valid.xml').read_bytes()
        marker = b'<!-- sparkle-signatures:\n'
        trailer = marker + original.split(marker)[1]
        (self.directory / 'duplicate-trailer.xml').write_bytes(original + trailer)
        self.rejected('Multiple signed-feed trailers', feed='duplicate-trailer.xml')

    def test_malformed_signature_trailer(self):
        original = (self.directory / 'valid.xml').read_bytes()
        (self.directory / 'invalid-trailer.xml').write_bytes(original.replace(b'edSignature: ', b'edSignature: !'))
        self.rejected('Malformed signed-feed trailer', feed='invalid-trailer.xml')

    def test_versions_match_release_metadata(self):
        self.rejected('Feed build number does not match the application', feed='wrong-build.xml')
        self.rejected('Feed version does not match the application', feed='wrong-version.xml')
        self.rejected('Feed build number does not match the application', build='5')
        self.rejected('Feed version does not match the application', version='1.3.1')

    def test_invalid_expected_versions(self):
        self.rejected('Invalid expected build number', build='0')
        self.rejected('Invalid expected version', version='../1.3.0')

    def test_enclosure_cannot_shadow_item_versions(self):
        self.rejected('Enclosure version attributes are not allowed', feed='enclosure-build.xml')
        self.rejected('Enclosure version attributes are not allowed', feed='enclosure-version.xml')

    def test_archive_url_is_immutable_matching_github_tag(self):
        for feed in ('latest-url', 'wrong-tag', 'wrong-host', 'insecure-url',
                     'wrong-build-tag', 'wrong-version-build-tag', 'noncanonical-build-tag'):
            with self.subTest(feed=feed):
                self.rejected('Update URL must use the matching immutable release tag', feed=feed + '.xml')

    def test_build_tag_matches_the_signed_bundle(self):
        result = self.verify(feed='valid-build-tag.xml')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Verified signed update: Insonia 1.3.0, build 4', result.stdout)

    def test_invalid_archive_signature_and_length(self):
        self.rejected('Archive length mismatch', feed='wrong-length.xml')
        self.rejected('Missing or invalid archive signature and length', feed='missing-archive-signature.xml')
        self.rejected('Invalid archive signature', feed='invalid-archive-signature.xml')

    def test_ambiguous_release_structure(self):
        for feed, error in (('duplicate-version', 'Expected one sparkle:version'),
                            ('nested-version', 'Invalid sparkle:version'),
                            ('duplicate-enclosure', 'Expected one update enclosure'),
                            ('duplicate-item', 'Expected one release item'),
                            ('duplicate-channel', 'Expected one release channel')):
            with self.subTest(feed=feed):
                self.rejected(error, feed=feed + '.xml')

    def test_no_delta_updates(self):
        self.rejected('Delta updates are not allowed', feed='delta.xml')
        self.rejected('Delta archives are not allowed', feed='delta-attribute.xml')

    def test_release_notes_must_be_embedded(self):
        self.rejected('Release notes must be embedded', feed='external-notes.xml')

    def test_namespace_identity(self):
        self.rejected('Unexpected Sparkle namespace', feed='wrong-namespace.xml')
        self.rejected('Expected one sparkle:version', feed='rebound-namespace.xml')

    def test_no_external_entities(self):
        self.rejected('Feed document types and entities are not allowed', feed='doctype.xml')

    def test_strict_xml_and_encoding(self):
        self.rejected('Update verification failed:', feed='broken-xml.xml')
        self.rejected('Feed must be UTF-8 XML', feed='utf16.xml')

    def test_archive_content_type(self):
        self.rejected('Unexpected archive content type', feed='wrong-content-type.xml')

    def test_cli_usage(self):
        result = subprocess.run([str(self.verifier)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Usage:', result.stderr)

    def test_signing_rejects_ci_before_accessing_keychain(self):
        result = subprocess.run([str(ROOT / 'scripts/sign-release.sh')], env={**os.environ, 'CI': 'true'},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Sign releases locally with the private key in Keychain.', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
