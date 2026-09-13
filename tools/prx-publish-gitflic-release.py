#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Purpose: Publish verified files as a GitFlic release using a job-scoped token.
# Usage: python3 tools/prx-publish-gitflic-release.py --artifact FILE [--artifact FILE] --notes CHANGELOG.md
# Args: --project-url URL, --tag vX.Y.Z, --commit SHA override their CI_* defaults.
#   --api-url URL overrides the derived API root but must use the same origin
#   (gitflic.ru -> api.gitflic.ru is the only cross-origin exception).
# Output: A release with SHA-256-verified attachments; existing equal files are reused.
# Environment: CI_PROJECT_URL, CI_COMMIT_TAG, CI_COMMIT_SHA, CI_JOB_TOKEN.
#   CI_JOB_TOKEN is required and is never accepted as a CLI argument or printed.
# Example: python3 tools/prx-publish-gitflic-release.py --artifact dist/package.deb --notes CHANGELOG.md
# Safety: No tag moves, release/file deletions, overwrites or HTTP redirects; retries reuse matching files.
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def release_notes(path, version):
    text = Path(path).read_text(encoding="utf-8")
    match = re.search(r"^## " + re.escape(version) + r"(?:\s[^\n]*)?\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not match:
        raise ValueError("Release version has no changelog entry")
    return match.group(1).strip()


def endpoints(project_url, api_url=None):
    parsed = urllib.parse.urlsplit(project_url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc or parsed.username or parsed.password:
        raise ValueError("Invalid project URL")
    if parsed.query or parsed.fragment:
        raise ValueError("Project URL must not contain query/fragment")
    match = re.fullmatch(r"/project/([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+)/?", parsed.path)
    if not match:
        raise ValueError("Expected /project/OWNER/PROJECT URL")
    origin = f"{parsed.scheme}://{parsed.netloc}"
    base = api_url or ("https://api.gitflic.ru" if origin == "https://gitflic.ru" else origin + "/rest-api")
    api = urllib.parse.urlsplit(base)
    allowed = (api.scheme, api.netloc) == (parsed.scheme, parsed.netloc)
    allowed |= origin == "https://gitflic.ru" and base.rstrip("/") == "https://api.gitflic.ru"
    if not allowed or api.username or api.password or api.query or api.fragment:
        raise ValueError("Refusing to send job token to a different origin")
    return base.rstrip("/") + match.group(0).rstrip("/") + "/release"


class Client:
    def __init__(self, token):
        if not token or "\n" in token or "\r" in token:
            raise ValueError("CI_JOB_TOKEN is required")
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, url, data=None, content_type=None):
        headers = {"Authorization": "token " + self.token, "Accept": "application/json"}
        if content_type:
            headers["Content-Type"] = content_type
        req = urllib.request.Request(url, data=data, headers=headers)
        try:
            with self.opener.open(req, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            # Do not echo response bodies, headers or token-bearing request objects.
            raise RuntimeError(f"GitFlic API HTTP {error.code}; request was not retried") from None
        except urllib.error.URLError:
            raise RuntimeError("GitFlic API connection failed; request was not retried") from None

    def get(self, url):
        return json.loads(self.request(url))

    def post(self, url, data):
        return json.loads(self.request(url, json.dumps(data).encode(), "application/json"))

    def upload(self, url, name, contents):
        boundary = "pgcc-" + uuid.uuid4().hex
        body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"files\"; filename=\"{name}\"\r\n"
                "Content-Type: application/octet-stream\r\n\r\n").encode()
        body += contents + f"\r\n--{boundary}--\r\n".encode()
        self.request(url, body, "multipart/form-data; boundary=" + boundary)


def publish(args, client):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", args.tag or ""):
        raise ValueError("Expected release tag vX.Y.Z")
    if not re.fullmatch(r"[0-9a-fA-F]{40}", args.commit or ""):
        raise ValueError("Expected full CI_COMMIT_SHA")
    base = endpoints(args.project_url, args.api_url)
    notes = release_notes(args.notes, args.tag[1:])
    files = {}
    for value in args.artifact:
        path = Path(value)
        if path.is_symlink() or not path.is_file() or not re.fullmatch(r"[a-zA-Z0-9_.-]+", path.name):
            raise ValueError("Expected regular artifact with a safe basename")
        if path.stat().st_size > 128 * 1024 * 1024 or path.name in files:
            raise ValueError("Oversized artifact or duplicate basename")
        files[path.name] = path.read_bytes()
    found = []
    page = 0
    while True:
        listing = client.get(f"{base}?size=100&page={page}")
        found.extend(item for item in listing.get("_embedded", {}).get("releaseTagModelList", [])
                     if item.get("tagName") == args.tag)
        if page + 1 >= listing.get("page", {}).get("totalPages", 1):
            break
        page += 1
        if page > 1000:
            raise ValueError("Unexpected release pagination")
    if len(found) > 1:
        raise ValueError("Multiple releases already use this tag")
    release = found[0] if found else client.post(base, {
        "title": args.tag, "description": notes, "tagName": args.tag, "preRelease": False,
    })
    if release.get("commitId", "").lower() != args.commit.lower():
        raise ValueError("Release tag points to another commit; refusing modification")
    release_id = str(uuid.UUID(release["id"]))
    detail_url = f"{base}/{release_id}"
    # Retry-safe: never delete or replace an existing attachment with different bytes.
    for name, contents in files.items():
        detail = client.get(detail_url)
        existing = [item for item in detail.get("attachmentFiles") or [] if item.get("name") == name]
        if len(existing) > 1:
            raise ValueError("Duplicate attachment names on server")
        if not existing:
            client.upload(detail_url + "/file", name, contents)
            detail = client.get(detail_url)
            existing = [item for item in detail.get("attachmentFiles") or [] if item.get("name") == name]
        if len(existing) != 1:
            raise ValueError("Attachment not found after upload")
        attachment = existing[0]
        digest = hashlib.sha256(contents).hexdigest()
        if attachment.get("hashSha256", "").lower() != digest:
            raise ValueError("Existing/uploaded attachment SHA-256 differs; refusing overwrite")
        file_id = str(uuid.UUID(attachment["uuid"]))
        downloaded = client.request(detail_url + "/file/" + file_id)
        if hashlib.sha256(downloaded).hexdigest() != digest:
            raise ValueError("Downloaded attachment SHA-256 differs")
        print(f"PASS: release attachment {name}: SHA-256 verified")
    print(f"Release ready: {args.project_url.rstrip('/')}/release/{release_id}")


def main():
    parser = argparse.ArgumentParser(description=__doc__ or "Publish a GitFlic release from a tag pipeline")
    parser.add_argument("--project-url", default=os.environ.get("CI_PROJECT_URL"))
    parser.add_argument("--tag", default=os.environ.get("CI_COMMIT_TAG"))
    parser.add_argument("--commit", default=os.environ.get("CI_COMMIT_SHA"))
    parser.add_argument("--api-url")
    parser.add_argument("--artifact", action="append", required=True)
    parser.add_argument("--notes", required=True)
    args = parser.parse_args()
    try:
        publish(args, Client(os.environ.get("CI_JOB_TOKEN")))
    except (ValueError, RuntimeError, OSError, KeyError, TypeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
