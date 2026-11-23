# /// script
# requires-python = ">=3.11"
# dependencies = ["alibabacloud-oss-v2==1.4.1", "joserfc==1.8.0"]
# ///
"""Upload one explicitly selected local file; OAuth stays in the native OUO connection."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import logging
import os
from pathlib import Path
import re
import stat
import sys
import time
from urllib.parse import unquote, urlsplit

from joserfc import jwe
from joserfc.jwk import ECKey


MAX_BYTES = 5 * 1024**3
FORMATS = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".webp": "image/webp", ".heic": "image/heic", ".heif": "image/heif",
    ".mp4": "video/mp4", ".mov": "video/quicktime", ".mp3": "audio/mpeg", ".wav": "audio/wav"}


def manifest(stream, name):
    info = os.fstat(stream.fileno())
    if (not stat.S_ISREG(info.st_mode) or not 1 <= info.st_size <= MAX_BYTES
            or not 1 <= len(name) <= 200 or name.strip() != name
            or any(ord(char) < 32 or char in "/\\:" for char in name)):
        raise ValueError
    media_type = FORMATS[Path(name).suffix.lower()]
    checksum, size = hashlib.sha256(), 0
    stream.seek(0)
    while chunk := stream.read(1024**2):
        checksum.update(chunk)
        size += len(chunk)
        if size > MAX_BYTES:
            raise ValueError
    stream.seek(0)
    if size != info.st_size:
        raise ValueError
    return {"file_name": name, "file_size": size, "content_type": media_type, "file_sha256": checksum.hexdigest()}


def validate_destination(value):
    allowed = {"url", "needUpload", "objectKey", "uploadOrigin", "expires", "expiresAt",
        "accessKeyId", "accessKeySecret", "securityToken", "bucket", "endpoint", "region"}
    if not isinstance(value, dict) or set(value) - allowed or type(value["needUpload"]) is not bool:
        raise ValueError
    url = value["url"]
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.port not in (None, 443) or parsed.query or parsed.fragment
            or any(ord(char) < 33 or char == "\\" for char in url)):
        raise ValueError
    if not value["needUpload"]:
        if set(value) != {"url", "needUpload"}:
            raise ValueError
        return
    bucket, key = value["bucket"], value["objectKey"]
    region = value["region"].removeprefix("oss-")
    if (not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]", bucket)
            or not re.fullmatch(r"[a-z]{2,4}(?:-[a-z0-9]+){1,4}", region)
            or not 1 <= len(key.encode()) <= 1024 or "\\" in key
            or any(part in {"", ".", ".."} for part in key.split("/"))
            or any(ord(char) < 32 for char in key)):
        raise ValueError
    if (value["endpoint"] != "https://oss-" + region + ".aliyuncs.com"
            or value["uploadOrigin"] != "https://" + bucket + ".oss-" + region + ".aliyuncs.com"
            or unquote(parsed.path) != "/" + key
            or not time.time() + 15 < value["expiresAt"] <= time.time() + 86400):
        raise ValueError
    for field in ("accessKeyId", "accessKeySecret", "securityToken"):
        secret = value[field]
        if not isinstance(secret, str) or not 1 <= len(secret) <= 8192 or any(ord(char) < 32 for char in secret):
            raise ValueError
    if not value["accessKeyId"].startswith("STS"):
        raise ValueError


def decrypt_ticket(ticket, private_key, params):
    if not isinstance(ticket, str) or not 1 <= len(ticket) <= 65536:
        raise ValueError
    result = jwe.decrypt_compact(ticket, private_key, algorithms=["ECDH-ES", "A256GCM"])
    if (set(result.protected) != {"alg", "enc", "typ", "epk"}
            or result.protected["typ"] != "ouo-local-media+jwe"):
        raise ValueError
    value = json.loads(result.plaintext)
    if (set(value) != {"contract", "uploadId", "requestId", "manifest", "expiresAt", "destination"}
            or value["contract"] != "ouo-local-media-v1" or value["requestId"] != params["request_id"]
            or value["manifest"] != params["manifest"] or not re.fullmatch(r"upload_[a-f0-9]{32}", value["uploadId"])
            or not time.time() < value["expiresAt"] <= time.time() + 1800):
        raise ValueError
    validate_destination(value["destination"])
    return value


class UploadBody(io.RawIOBase):
    def __init__(self, stream, size):
        self.stream, self.size = stream, size
        self.checksum, self.transferred = hashlib.sha256(), 0

    def __len__(self):
        return self.size

    def readable(self):
        return True

    def read(self, size=-1):
        chunk = self.stream.read(1024**2 if size is None or size < 0 else min(size, 1024**2))
        self.transferred += len(chunk)
        if self.transferred > self.size:
            raise ValueError
        self.checksum.update(chunk)
        return chunk


def put_object(destination, stream, file_manifest):
    import alibabacloud_oss_v2 as oss
    import requests
    from alibabacloud_oss_v2.transport import RequestsHttpClient

    validate_destination(destination)
    provider = oss.credentials.StaticCredentialsProvider(destination["accessKeyId"],
        destination["accessKeySecret"], destination["securityToken"])
    session = requests.Session()
    session.trust_env = False
    transport = RequestsHttpClient(session=session, connect_timeout=10, readwrite_timeout=60,
        enabled_redirect=False, insecure_skip_verify=False)
    client = oss.Client(oss.Config(region=destination["region"].removeprefix("oss-"), endpoint=destination["endpoint"],
        http_client=transport, credentials_provider=provider, signature_version="v4", retry_max_attempts=1,
        connect_timeout=10, readwrite_timeout=60, enabled_redirect=False, disable_ssl=False, insecure_skip_verify=False))
    body = UploadBody(stream, file_manifest["file_size"])
    try:
        result = client.put_object(oss.PutObjectRequest(bucket=destination["bucket"], key=destination["objectKey"],
            body=body, content_length=file_manifest["file_size"], content_type=file_manifest["content_type"],
            metadata={"ouo-sha256": file_manifest["file_sha256"]}))
        if (result.status_code != 200 or body.transferred != file_manifest["file_size"]
                or body.checksum.hexdigest() != file_manifest["file_sha256"]):
            raise ValueError
    finally:
        session.close()


def read_ticket_file(path):
    deadline, incomplete_since = time.monotonic() + 1200, None
    while time.monotonic() < deadline:
        if path.exists():
            with path.open("r", encoding="utf-8") as stream:
                text = stream.read(65537)
            if len(text) > 65536:
                raise ValueError
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                incomplete_since = incomplete_since or time.monotonic()
                if time.monotonic() - incomplete_since > 2:
                    raise ValueError from None
        time.sleep(0.1)
    raise TimeoutError


def run(file, request_id, name, *, source=None, sink=None, handoff=None):
    source, sink = source or sys.stdin, sink or sys.stdout
    handoff = Path(handoff) if handoff is not None else None
    upload_id, file_manifest, started = None, None, False

    def emit(value):
        if handoff is not None and value["phase"] in {"prepare", "complete"}:
            with (handoff / (value["phase"] + ".json")).open("x", encoding="utf-8") as stream:
                json.dump(value, stream, ensure_ascii=True)
            value = {"phase": value["phase"], "handoff_saved": True}
        print(json.dumps(value, ensure_ascii=True, separators=(",", ":")), file=sink, flush=True)

    try:
        if (not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", request_id)
                or not 1 <= len(name) <= 200):
            raise ValueError
        if handoff is not None:
            handoff.mkdir(exist_ok=False)
        with Path(file).open("rb") as stream:
            file_manifest = manifest(stream, Path(file).name)
            private_key = ECKey.generate_key("P-256")
            public = private_key.as_dict(private=False)
            params = {"request_id": request_id, "name": name, "manifest": file_manifest,
                "public_key": {field: public[field] for field in ("kty", "crv", "x", "y")}}
            emit({"phase": "prepare", "params": params})
            # Only an encrypted native tool result crosses the model-visible channel.
            if handoff is not None:
                reply = read_ticket_file(handoff / "ticket.json")
            else:
                line = source.readline(65537)
                reply = json.loads(line) if len(line) <= 65536 else None
            if not isinstance(reply, dict) or set(reply) != {"ticket"}:
                raise ValueError
            envelope = decrypt_ticket(reply["ticket"], private_key, params)
            upload_id = envelope["uploadId"]
            if manifest(stream, Path(file).name) != file_manifest:
                raise ValueError
            outcome = "already_present"
            if envelope["destination"]["needUpload"]:
                started = True
                put_object(envelope["destination"], stream, file_manifest)
                outcome = "transferred"
            emit({"phase": "complete", "params": {"upload_id": upload_id,
                "file_sha256": file_manifest["file_sha256"], "outcome": outcome}})
            return 0
    except (Exception, KeyboardInterrupt):
        if upload_id:
            emit({"phase": "complete", "params": {"upload_id": upload_id,
                "file_sha256": file_manifest["file_sha256"],
                "outcome": "needs_reconciliation" if started else "cancelled"}})
        else:
            emit({"phase": "stopped", "code": "LOCAL_UPLOAD_INPUT_OR_TICKET_INVALID"})
        return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", required=True, type=Path)
    parser.add_argument("--request-id", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--handoff", type=Path, help="New task directory for public request, encrypted ticket and receipt.")
    options = parser.parse_args()
    logging.disable(logging.CRITICAL)
    return run(options.file, options.request_id, options.name, handoff=options.handoff)


if __name__ == "__main__":
    sys.exit(main())
