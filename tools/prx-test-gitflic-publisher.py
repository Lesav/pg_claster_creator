#!/usr/bin/env python3
# Purpose: Exercise release publishing guards with an in-memory GitFlic API fixture.
# Usage: python3 -B tools/prx-test-gitflic-publisher.py PATH_TO_PUBLISHER
# Args: PATH_TO_PUBLISHER is the release publisher script under test.
# Output: unittest results; no network, Git writes or cluster operations.
# Example: python3 -B tools/prx-test-gitflic-publisher.py tools/prx-publish-gitflic-release.py
import argparse
import contextlib
import hashlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
import urllib.error
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location('publisher', sys.argv.pop(1))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
RID = '11111111-1111-1111-1111-111111111111'
FID = '22222222-2222-2222-2222-222222222222'
COMMIT = 'a' * 40


class Api:
    def __init__(self):
        self.release = None
        self.contents = b''
        self.posts = 0
        self.uploads = 0

    def get(self, url):
        if '?' in url:
            return {'_embedded': {'releaseTagModelList': [self.release] if self.release else []}}
        return self.release

    def post(self, url, body):
        self.posts += 1
        self.release = dict(body, id=RID, commitId=COMMIT, attachmentFiles=[])
        return self.release

    def upload(self, url, name, contents):
        self.uploads += 1
        self.contents = contents
        self.release['attachmentFiles'].append(dict(name=name, uuid=FID, hashSha256=hashlib.sha256(contents).hexdigest()))

    def request(self, url):
        return self.contents


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pgcc-publisher-test-')
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        (root / 'package.deb').write_bytes(b'harmless package fixture')
        (root / 'CHANGELOG.md').write_text('## 2.5.4 — date\n\n- Test release.\n\n## 2.5.3\nOlder\n', encoding='utf-8')
        self.args = argparse.Namespace(project_url='http://example.invalid/project/owner/repo', api_url=None,
            tag='v2.5.4', commit=COMMIT, artifact=[str(root / 'package.deb')], notes=str(root / 'CHANGELOG.md'))
        self.api = Api()

    def run_publish(self):
        with contextlib.redirect_stdout(io.StringIO()):
            publisher.publish(self.args, self.api)

    def test_create_and_retry(self):
        self.run_publish()
        self.run_publish()
        self.assertEqual((self.api.posts, self.api.uploads), (1, 1))

    def test_conflicting_attachment(self):
        self.run_publish()
        Path(self.args.artifact[0]).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            self.run_publish()
        self.assertEqual(self.api.uploads, 1)

    def test_wrong_commit(self):
        self.run_publish()
        self.args.commit = 'b' * 40
        with self.assertRaisesRegex(ValueError, 'another commit'):
            self.run_publish()
        self.assertEqual(self.api.uploads, 1)

    def test_invalid_tag_before_writes(self):
        self.args.tag = 'master'
        with self.assertRaises(ValueError):
            self.run_publish()
        self.assertEqual(self.api.posts, 0)

    def test_missing_notes_before_writes(self):
        self.args.tag = 'v2.5.5'
        with self.assertRaises(ValueError):
            self.run_publish()
        self.assertEqual(self.api.posts, 0)

    def test_missing_artifact_before_writes(self):
        self.args.artifact = [str(Path(self.temp.name) / 'missing.deb')]
        with self.assertRaises(ValueError):
            self.run_publish()
        self.assertEqual(self.api.posts, 0)

    def test_cross_origin_rejected(self):
        self.args.api_url = 'https://other.invalid/rest-api'
        with self.assertRaisesRegex(ValueError, 'different origin'):
            self.run_publish()
        self.assertEqual(self.api.posts, 0)

    def test_missing_token(self):
        with self.assertRaises(ValueError):
            publisher.Client(None)

    def test_redirects_disabled(self):
        self.assertIsNone(publisher.NoRedirect().redirect_request(None, None, 302, '', {}, 'http://other.invalid'))

    def test_deb_media_policy_diagnostic(self):
        client = publisher.Client('private-test-token')
        client.opener = Mock()
        body = b'{"type":"org.springframework.web.HttpMediaTypeNotSupportedException.type","detail":"application/x-debian-package private-test-token"}'
        client.opener.open.side_effect = urllib.error.HTTPError('http://example.invalid', 415, '', {}, io.BytesIO(body))
        with self.assertRaisesRegex(RuntimeError, 'server rejects application/x-debian-package') as caught:
            client.upload('http://example.invalid', 'package.deb', b'fixture')
        self.assertNotIn(client.token, str(caught.exception))
        self.assertEqual(client.opener.open.call_count, 1)

    def test_server_error_type_redacts_token(self):
        client = publisher.Client('private-test-token')
        client.opener = Mock()
        body = b'{"type":"private-test-token","detail":"private-test-token"}'
        client.opener.open.side_effect = urllib.error.HTTPError('http://example.invalid', 500, '', {}, io.BytesIO(body))
        with self.assertRaisesRegex(RuntimeError, r'HTTP 500.*REDACTED') as caught:
            client.post('http://example.invalid', {})
        self.assertNotIn(client.token, str(caught.exception))

    def test_non_json_error_does_not_echo_body(self):
        client = publisher.Client('private-test-token')
        client.opener = Mock()
        client.opener.open.side_effect = urllib.error.HTTPError('http://example.invalid', 500, '', {}, io.BytesIO(b'private-test-token'))
        with self.assertRaisesRegex(RuntimeError, 'HTTP 500') as caught:
            client.get('http://example.invalid')
        self.assertNotIn(client.token, str(caught.exception))


unittest.main()
