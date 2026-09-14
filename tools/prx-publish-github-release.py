#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Purpose: Publish GitHub release assets with immutable-tag and checksum guards.
# Usage: python3 tools/prx-publish-github-release.py --dist dist --notes CHANGELOG.md
# Args: --repo OWNER/REPO, --tag vX.Y.Z, --commit SHA override GITHUB_* defaults.
# Output: Release DEB and SHA256SUMS; downloads are SHA-256 verified.
# Environment: GH_TOKEN is required; GITHUB_REPOSITORY, GITHUB_REF_NAME, GITHUB_SHA.
# Example: GH_TOKEN=... python3 tools/prx-publish-github-release.py --dist dist
# Safety: Use the job's contents:write token, never log it. No tag creation/moves,
# asset replacement, release edits, or draft promotion. Requires GitHub CLI.
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys
import tempfile


class Gh:
    def __init__(self, repo):
        if not os.environ.get('GH_TOKEN', '').strip():
            raise ValueError('GH_TOKEN is required')
        self.repo = repo

    def run(self, *args):
        env = dict(os.environ, GH_HOST='github.com', GH_PROMPT_DISABLED='1')
        env.pop('GH_DEBUG', None)
        result = subprocess.run(['gh', *args], capture_output=True, env=env, timeout=180)
        if result.returncode:
            # Vendor stderr may contain request details; do not expose it.
            raise RuntimeError('GitHub CLI command failed; no automatic retry')
        return result.stdout

    def get(self, suffix):
        return json.loads(self.run('api', '--hostname', 'github.com',
                                   f'repos/{self.repo}/{suffix}'))

    def releases(self):
        # All pages, without hiding authentication/network errors as "not found".
        pages = json.loads(self.run('api', '--hostname', 'github.com', '--paginate',
                                   '--slurp', f'repos/{self.repo}/releases?per_page=100'))
        return [release for page in pages for release in page]

    def create(self, tag, notes):
        with tempfile.TemporaryDirectory(prefix='pgcc-github-notes-') as directory:
            path = Path(directory) / 'notes.md'
            path.write_text(notes, encoding='utf-8')
            self.run('release', 'create', tag, '--repo', self.repo, '--verify-tag',
                     '--title', tag, '--notes-file', str(path))

    def download(self, tag, name):
        return self.run('release', 'download', tag, '--repo', self.repo,
                        '--pattern', name, '--output', '-')

    def upload(self, tag, path):
        self.run('release', 'upload', tag, str(path), '--repo', self.repo)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def prepare(args):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repo or ''):
        raise ValueError('Expected OWNER/REPO')
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', args.tag or ''):
        raise ValueError('Expected tag vX.Y.Z')
    if not re.fullmatch(r'[0-9a-fA-F]{40}', args.commit or ''):
        raise ValueError('Expected full commit SHA')
    paths = [Path(args.dist) / f'claster-creator-{args.tag[1:]}.deb',
             Path(args.dist) / 'SHA256SUMS']
    for path in paths:
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 128 * 1024 * 1024:
            raise ValueError('Expected regular release file, at most 128 MiB')
    files = {path.name: (path, path.read_bytes()) for path in paths}
    expected = f'{digest(files[paths[0].name][1])}  {paths[0].name}\n'.encode()
    if files['SHA256SUMS'][1] != expected:
        raise ValueError('SHA256SUMS does not match this DEB')
    # Reuse the existing version-specific changelog extraction, not a second parser.
    notes = runpy.run_path(str(Path(__file__).with_name('prx-publish-gitflic-release.py')))
    return files, notes['release_notes'](args.notes, args.tag[1:])


def publish(args, client, files, notes):
    if client.get(f'commits/{args.tag}').get('sha', '').lower() != args.commit.lower():
        raise ValueError('Remote tag does not match the build commit')
    found = [r for r in client.releases() if r.get('tag_name') == args.tag]
    if len(found) > 1:
        raise ValueError('Duplicate release tag')
    if found:
        release = found[0]
        if release.get('draft') or release.get('prerelease'):
            raise ValueError('Refusing to modify an existing draft/prerelease')
    else:
        client.create(args.tag, notes)
    release = client.get(f'releases/tags/{args.tag}')
    names = [asset['name'] for asset in release.get('assets', [])]
    # Check ALL collisions before adding any missing file; no --clobber ever.
    for name, (_, data) in files.items():
        if names.count(name) > 1:
            raise ValueError('Duplicate release asset name')
        if name in names and digest(client.download(args.tag, name)) != digest(data):
            raise ValueError(f'Existing asset differs: {name}; refusing overwrite')
    for name, (path, data) in files.items():
        if name not in names:
            client.upload(args.tag, path)
        if digest(client.download(args.tag, name)) != digest(data):
            raise ValueError(f'Downloaded asset differs: {name}')
        print(f'PASS: {name}: downloaded SHA-256 verified')
    print(f'Release ready: https://github.com/{args.repo}/releases/tag/{args.tag}')


def main():
    parser = argparse.ArgumentParser(description=__doc__ or 'Publish verified GitHub release assets')
    parser.add_argument('--repo', default=os.environ.get('GITHUB_REPOSITORY'))
    parser.add_argument('--tag', default=os.environ.get('GITHUB_REF_NAME'))
    parser.add_argument('--commit', default=os.environ.get('GITHUB_SHA'))
    parser.add_argument('--dist', default='dist')
    parser.add_argument('--notes', default='CHANGELOG.md')
    args = parser.parse_args()
    try:
        files, notes = prepare(args)
        publish(args, Gh(args.repo), files, notes)
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
