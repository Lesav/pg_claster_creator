#!/usr/bin/env python3
# Purpose: Exercise release-token isolation and publishing guards with an in-memory API fixture.
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
from unittest.mock import MagicMock, Mock, patch

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

    def run_main(self, environment):
        output = io.StringIO()
        argv = ['publisher', '--artifact', self.args.artifact[0], '--notes', self.args.notes]
        with patch.dict(publisher.os.environ, environment, clear=True), \
                patch.object(sys, 'argv', argv), \
                patch.object(publisher, 'publish') as publish_mock, \
                contextlib.redirect_stderr(output):
            status = publisher.main()
            self.assertEqual(dict(publisher.os.environ), environment)
        return status, publish_mock, output.getvalue()

    def test_release_token_without_job_token(self):
        status, called, error = self.run_main({'GITFLIC_RELEASE_TOKEN': 'user-test-secret'})
        self.assertEqual(status, 0)
        self.assertEqual(called.call_args[0][1].token, 'user-test-secret')
        self.assertEqual(error, '')

    def test_release_token_selected_without_mutating_job_token(self):
        status, called, error = self.run_main({
            'GITFLIC_RELEASE_TOKEN': 'user-test-secret', 'CI_JOB_TOKEN': 'job-test-secret'})
        self.assertEqual(status, 0)
        self.assertEqual(called.call_args[0][1].token, 'user-test-secret')
        self.assertEqual(error, '')

    def test_job_token_alone_is_not_a_fallback(self):
        status, called, error = self.run_main({'CI_JOB_TOKEN': 'job-test-secret'})
        self.assertEqual(status, 1)
        called.assert_not_called()
        self.assertIn('GITFLIC_RELEASE_TOKEN', error)
        self.assertNotIn('job-test-secret', error)

    def test_invalid_release_token_does_not_fall_back_or_leak(self):
        for token in ('', ' ', 'user-test-secret\n', 'user-test-secret\r',
                      'user test secret', 'user-test-secret\u2603'):
            with self.subTest(token_kind=repr(token[-1:])):
                status, called, error = self.run_main({
                    'GITFLIC_RELEASE_TOKEN': token, 'CI_JOB_TOKEN': 'job-test-secret'})
                self.assertEqual(status, 1)
                called.assert_not_called()
                self.assertIn('GITFLIC_RELEASE_TOKEN', error)
                self.assertNotIn('user-test-secret', error)
                self.assertNotIn('job-test-secret', error)

    def test_null_byte_rejected_by_client(self):
        # Real process environments cannot contain NUL; test validation directly.
        with self.assertRaisesRegex(ValueError, 'GITFLIC_RELEASE_TOKEN'):
            publisher.Client('user-test-secret\x00')

    def test_user_token_authorization_header(self):
        client = publisher.Client('user-test-secret')
        response = Mock()
        response.read.return_value = b'{}'
        client.opener = MagicMock()
        client.opener.open.return_value.__enter__.return_value = response
        self.assertEqual(client.get('http://example.invalid'), {})
        request = client.opener.open.call_args[0][0]
        self.assertEqual(request.get_header('Authorization'), 'token user-test-secret')

    def test_multipart_checksum_content_type_and_bytes(self):
        client = publisher.Client('user-test-secret')
        contents = b'a' * 64 + b'  claster-creator-2.5.6.deb\n'
        for name, mime in [('claster-creator-2.5.6.sha256', 'text/plain'),
                           ('SHA256SUMS', 'text/plain'),
                           ('package.deb', 'application/octet-stream'),
                           ('note.txt', 'application/octet-stream')]:
            with self.subTest(name=name), patch.object(client, 'request') as request:
                client.upload('http://example.invalid/file', name, contents)
                url, body, content_type = request.call_args[0]
                self.assertTrue(content_type.startswith('multipart/form-data; boundary='))
                boundary = content_type.split('boundary=', 1)[1]
                expected = (f'--{boundary}\r\nContent-Disposition: form-data; name="files"; '
                            f'filename="{name}"\r\nContent-Type: {mime}\r\n\r\n').encode()
                self.assertEqual(body, expected + contents + f'\r\n--{boundary}--\r\n'.encode())

    def test_help_documents_secret_environment_without_values(self):
        output = io.StringIO()
        with patch.dict(publisher.os.environ, {'GITFLIC_RELEASE_TOKEN': 'user-test-secret'}, clear=True), \
                patch.object(sys, 'argv', ['publisher', '--help']), \
                contextlib.redirect_stdout(output), self.assertRaises(SystemExit) as caught:
            publisher.main()
        self.assertEqual(caught.exception.code, 0)
        self.assertIn('GITFLIC_RELEASE_TOKEN', output.getvalue())
        self.assertIn('no credential fallback', output.getvalue())
        self.assertNotIn('user-test-secret', output.getvalue())

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
