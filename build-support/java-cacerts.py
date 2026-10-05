#!/usr/bin/env python3
"""Build a deterministic JKS trust store from a directory of PEM certificates."""

from __future__ import annotations

import argparse
import base64
import hashlib
import re
import struct
from pathlib import Path


PEM_CERTIFICATE = re.compile(
    rb"-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----",
    re.DOTALL,
)


def java_utf(value: str) -> bytes:
    encoded = value.encode("utf-8")
    if len(encoded) > 0xFFFF:
        raise ValueError("JKS string is too long")
    return struct.pack(">H", len(encoded)) + encoded


def read_certificates(directory: Path) -> list[bytes]:
    certificates: list[bytes] = []
    for certificate_path in sorted(directory.glob("*.crt")):
        for match in PEM_CERTIFICATE.finditer(certificate_path.read_bytes()):
            certificates.append(base64.b64decode(re.sub(rb"\s+", b"", match.group(1))))
    if not certificates:
        raise SystemExit(f"no PEM certificates found in {directory}")
    return certificates


def build_jks(certificates: list[bytes], password: str) -> bytes:
    body = bytearray(struct.pack(">III", 0xFEEDFEED, 2, len(certificates)))
    for certificate in certificates:
        alias = hashlib.sha256(certificate).hexdigest()
        body += struct.pack(">I", 2)  # trusted-certificate entry
        body += java_utf(alias)
        body += struct.pack(">Q", 0)  # deterministic creation timestamp
        body += java_utf("X.509")
        body += struct.pack(">I", len(certificate))
        body += certificate

    checksum = hashlib.sha1()
    checksum.update(password.encode("utf-16-be"))
    checksum.update(b"Mighty Aphrodite")
    checksum.update(body)
    return bytes(body) + checksum.digest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("certificates", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--password", default="changeit")
    args = parser.parse_args()

    certificates = read_certificates(args.certificates)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(build_jks(certificates, args.password))
    print(f"wrote {len(certificates)} certificates to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
