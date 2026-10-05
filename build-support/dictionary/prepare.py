#!/usr/bin/env python3
"""Stage an offline, indexed WordNet 3.0 lexicon; no network in the guest."""
# SPDX-License-Identifier: GPL-2.0-or-later
import argparse
import hashlib
import os
from pathlib import Path
import struct
import tarfile
import tempfile
import urllib.request

URL = "https://wordnetcode.princeton.edu/3.0/WordNet-3.0.tar.gz"
SHA256 = "640db279c949a88f61f851dd54ebbb22d003f8b90b85267042ef85a3781d3a52"
MAGIC = b"VNXDICT1"
MAX_ENTRIES = 200_000
MAX_KEY = 128
MAX_DEFINITION = 64 * 1024
MAX_FILE = 64 * 1024 * 1024


def encode(entries):
    """24-byte header, 16-byte records, sorted UTF-8 keys, definitions."""
    if not entries or len(entries) > MAX_ENTRIES:
        raise ValueError("invalid lexicon entry count")
    table, keys, definitions = bytearray(), bytearray(), bytearray()
    for word, definition in sorted(entries.items()):
        key, text = word.encode("utf-8"), definition.encode("utf-8")
        if not key or len(key) > MAX_KEY or not text or len(text) > MAX_DEFINITION:
            raise ValueError("lexicon entry exceeds bounds")
        if any(ord(char) < 32 or 127 <= ord(char) <= 159 for char in word):
            raise ValueError("invalid headword")
        if any((ord(char) < 32 and char != "\n") or 127 <= ord(char) <= 159 for char in definition):
            raise ValueError("invalid definition text")
        table.extend(struct.pack("<IIII", len(keys), len(key), len(definitions), len(text)))
        keys.extend(key)
        definitions.extend(text)
    header = MAGIC + struct.pack("<IIII", len(entries), len(keys), len(definitions), 0)
    result = header + table + keys + definitions
    if len(result) > MAX_FILE:
        raise ValueError("lexicon exceeds file bound")
    return result


def parse_wordnet(archive):
    entries = {}
    with tarfile.open(archive, "r:gz") as source:
        license_member = source.getmember("WordNet-3.0/LICENSE")
        if not license_member.isfile() or license_member.size > 16384:
            raise ValueError("missing WordNet license")
        license_text = source.extractfile(license_member).read()
        for suffix, label in (("noun", "noun"), ("verb", "verb"),
                              ("adj", "adjective"), ("adv", "adverb")):
            member = source.getmember("WordNet-3.0/dict/data." + suffix)
            if not member.isfile() or member.size > MAX_FILE:
                raise ValueError("invalid WordNet member")
            for raw in source.extractfile(member):
                if raw.startswith(b" ") or not raw.strip():
                    continue
                metadata, gloss = raw.decode("utf-8").split(" | ", 1)
                fields = metadata.split()
                count = int(fields[3], 16)
                words = [fields[4 + index * 2] for index in range(count)]
                # Adjective syntactic markers are metadata, not headwords.
                words = [word.removesuffix("(a)").removesuffix("(p)")
                         .removesuffix("(ip)").replace("_", " ").lower() for word in words]
                related = ", ".join(dict.fromkeys(words))
                definition = f"[{label}] {gloss.strip()}\nRelated: {related}"
                for word in dict.fromkeys(words):
                    entries.setdefault(word, []).append(definition)
    return {word: "\n\n".join(dict.fromkeys(senses)) for word, senses in entries.items()}, license_text


def verified_archive(path):
    return path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == SHA256


def atomic_write(path, data):
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
        os.chmod(temporary, 0o444)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--cache", type=Path, default=Path(__file__).resolve().parents[2] / "build/dictionary")
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    archive = args.archive or args.cache / "WordNet-3.0.tar.gz"
    if not verified_archive(archive):
        if args.archive:
            parser.error("archive does not match the pinned WordNet 3.0 SHA-256")
        with urllib.request.urlopen(URL, timeout=60) as response:
            contents = response.read(16 * 1024 * 1024 + 1)
        if len(contents) > 16 * 1024 * 1024 or hashlib.sha256(contents).hexdigest() != SHA256:
            raise ValueError("download does not match the pinned WordNet archive")
        atomic_write(archive, contents)
    entries, license_text = parse_wordnet(archive)
    data = encode(entries)
    args.destination.mkdir(parents=True, exist_ok=True)
    atomic_write(args.destination / "dictionary.vnd", data)
    atomic_write(args.destination / "LICENSE.WordNet", license_text)
    print(f"Dictionary: staged {len(entries)} offline headwords ({len(data)} bytes)")


if __name__ == "__main__":
    main()
