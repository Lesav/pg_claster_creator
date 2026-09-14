#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Purpose: Exercise GitHub release guards offline without credentials or API writes.
# Usage: python3 tools/prx-test-github-publisher.py [PUBLISHER]
# Args: PUBLISHER defaults to tools/prx-publish-github-release.py.
# Output: unittest results; nonzero on failure. Temporary fixtures are removed.
# Example: python3 tools/prx-test-github-publisher.py
import argparse
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

path = Path(sys.argv.pop(1) if len(sys.argv) > 1 else 'tools/prx-publish-github-release.py')
spec = importlib.util.spec_from_file_location('publisher', path)
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class Fake:
    def __init__(self, assets=None, exists=True, draft=False, sha='a' * 40):
        self.assets = assets or {}
        self.exists, self.draft, self.sha = exists, draft, sha
        self.created = self.uploaded = 0

    def get(self, suffix):
        if suffix.startswith('commits/'):
            return {'sha': self.sha}
        return {'assets': [{'name': name} for name in self.assets]}

    def releases(self):
        return [{'tag_name': 'v2.5.5', 'draft': self.draft}] if self.exists else []

    def create(self, tag, notes):
        self.created += 1

    def download(self, tag, name):
        return self.assets[name]

    def upload(self, tag, path):
        self.uploaded += 1
        self.assets[path.name] = path.read_bytes()


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.deb = root / 'claster-creator-2.5.5.deb'
        self.deb.write_bytes(b'fixture-deb')
        self.sums = root / 'SHA256SUMS'
        self.sums.write_bytes(f'{publisher.digest(self.deb.read_bytes())}  {self.deb.name}\n'.encode())
        self.notes = root / 'CHANGELOG.md'
        self.notes.write_text('## 2.5.5\n\nRelease notes.\n')
        self.args = argparse.Namespace(repo='owner/repo', tag='v2.5.5', commit='a' * 40,
                                       dist=str(root), notes=str(self.notes))
        self.files = {p.name: (p, p.read_bytes()) for p in [self.deb, self.sums]}

    def run_publish(self, client):
        publisher.publish(self.args, client, self.files, 'Release notes.')

    def test_create_upload_verify(self):
        c = Fake(exists=False)
        self.run_publish(c)
        self.assertEqual((c.created, c.uploaded), (1, 2))

    def test_retry_reuses_equal_assets(self):
        c = Fake({k: v[1] for k, v in self.files.items()})
        self.run_publish(c)
        self.assertEqual((c.created, c.uploaded), (0, 0))

    def test_conflict_before_any_upload(self):
        c = Fake({'SHA256SUMS': b'wrong'})
        with self.assertRaisesRegex(ValueError, 'Existing asset differs'):
            self.run_publish(c)
        self.assertEqual(c.uploaded, 0)

    def test_other_commit_refused(self):
        c = Fake(sha='b' * 40)
        with self.assertRaisesRegex(ValueError, 'Remote tag'):
            self.run_publish(c)
        self.assertEqual(c.created + c.uploaded, 0)

    def test_draft_not_promoted(self):
        c = Fake(draft=True)
        with self.assertRaisesRegex(ValueError, 'draft'):
            self.run_publish(c)

    def test_bad_download(self):
        c = Fake()
        c.download = lambda *args: b'corrupt'
        with self.assertRaisesRegex(ValueError, 'Downloaded asset differs'):
            self.run_publish(c)

    def test_bad_checksum(self):
        self.sums.write_text('wrong')
        with self.assertRaisesRegex(ValueError, 'SHA256SUMS'):
            publisher.prepare(self.args)

    def test_prepare_valid_files_and_reused_notes_parser(self):
        files, notes = publisher.prepare(self.args)
        self.assertEqual(set(files), {self.deb.name, 'SHA256SUMS'})
        self.assertEqual(notes, 'Release notes.')

    def test_listing_failure_does_not_create_release(self):
        c = Fake(exists=False)
        c.releases = lambda: (_ for _ in ()).throw(RuntimeError('API unavailable'))
        with self.assertRaisesRegex(RuntimeError, 'API unavailable'):
            self.run_publish(c)
        self.assertEqual(c.created + c.uploaded, 0)

    def test_bad_tag(self):
        self.args.tag = 'v2.5.5;echo bad'
        with self.assertRaisesRegex(ValueError, 'Expected tag'):
            publisher.prepare(self.args)

    def test_token_required(self):
        with patch.dict(os.environ, {'GH_TOKEN': ''}):
            with self.assertRaisesRegex(ValueError, 'GH_TOKEN'):
                publisher.Gh('owner/repo')

    def test_cli_error_does_not_leak_stderr(self):
        with patch.dict(os.environ, {'GH_TOKEN': 'test-secret'}):
            with patch.object(publisher.subprocess, 'run') as run:
                run.return_value = argparse.Namespace(returncode=1, stderr=b'test-secret', stdout=b'')
                with self.assertRaisesRegex(RuntimeError, '^GitHub CLI command failed; no automatic retry$'):
                    publisher.Gh('owner/repo').get('releases')


unittest.main()
