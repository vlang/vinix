#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Verify or recover byte-exact historical allocation benchmark source evidence.

The manifest retains immutable Git provenance instead of maintaining frozen
first-party C or generated C artifacts. Recovery always writes outside this
checkout; it does not translate, regenerate, or replace an independent fixture.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).resolve().parent / "results/source-archive.json"
CAMPAIGNS = ("2026-10-02-userspace", "2026-10-03-userspace-v5", "2026-10-03-userspace-v6")


def git(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=ROOT)


def manifest():
    data = json.loads(MANIFEST.read_text())
    if data.get("schema") != 1 or data.get("translation_credit") != 0:
        raise ValueError("Unsupported source archive manifest")
    paths = set()
    for record in data["files"]:
        path = record["path"]
        canonical = PurePosixPath(path)
        if canonical.is_absolute() or ".." in canonical.parts or str(canonical) != path:
            raise ValueError("Noncanonical evidence path: " + path)
        if path in paths:
            raise ValueError("Duplicate evidence path: " + path)
        paths.add(path)
    return data


def checked(record, content):
    if len(content) != record["bytes"] or hashlib.sha256(content).hexdigest() != record["sha256"]:
        raise ValueError("Historical source bytes differ: " + record["path"])
    return content


def read_source(path):
    """Return the exact archived bytes, checking commit/path, blob and SHA256."""
    records = {entry["path"]: entry for entry in manifest()["files"]}
    if path not in records:
        raise ValueError("Source is absent from the evidence manifest: " + path)
    record = records[path]
    reference = record["source_commit"] + ":" + path
    blob = git("rev-parse", reference).decode().strip()
    if blob != record["blob_sha1"]:
        raise ValueError("Historical source blob differs: " + path)
    return checked(record, git("show", reference))


class BlobReader:
    """One Git process reads immutable objects without an archive extraction."""
    def __enter__(self):
        self.process = subprocess.Popen(["git", "cat-file", "--batch"], cwd=ROOT,
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        return self

    def read(self, reference):
        self.process.stdin.write(reference.encode() + b"\n")
        self.process.stdin.flush()
        header = self.process.stdout.readline().decode().strip().split()
        if len(header) != 3 or header[1] != "blob":
            raise ValueError("Cannot recover historical blob: " + reference)
        size = int(header[2])
        content = self.process.stdout.read(size)
        if len(content) != size or self.process.stdout.read(1) != b"\n":
            raise ValueError("Incomplete Git object: " + reference)
        return header[0], content

    def __exit__(self, kind, value, traceback):
        self.process.stdin.close()
        self.process.stdout.close()
        code = self.process.wait()
        if kind is None and code:
            raise ValueError("Git source reader failed")


def verify(data):
    with BlobReader() as reader:
        for record in data["files"]:
            blob, content = reader.read(record["source_commit"] + ":" + record["path"])
            if blob != record["blob_sha1"]:
                raise ValueError("Historical source blob differs: " + record["path"])
            checked(record, content)
            if record["storage"] == "checkout-third-party":
                checked(record, (ROOT / record["path"]).read_bytes())
    print(f"Historical source archive PASS: {len(data['files'])} immutable blobs verified")


def destination_path(output, relative):
    output = output.resolve()
    destination = output / relative
    resolved = destination.resolve()
    if output != resolved and output not in resolved.parents:
        raise ValueError("Evidence destination escapes output: " + str(destination))
    if resolved == ROOT or ROOT in resolved.parents:
        raise ValueError("Historical source must be recovered outside the checkout")
    return destination


def write_source(output, relative, content, mode):
    destination = destination_path(output, relative)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if destination.read_bytes() != content:
            raise ValueError("Refusing to overwrite changed evidence: " + str(destination))
    else:
        with destination.open("xb") as stream:
            stream.write(content)
    destination.chmod(0o755 if mode == "100755" else 0o644)


def materialize(data, output, paths, snapshot):
    output = output.resolve()
    destination_path(output, ".source-archive-output")
    output.mkdir(parents=True, exist_ok=True)
    if snapshot:
        prefix = "tests/alloc-bench/results/" + snapshot
        entries = git("ls-tree", "-r", "-z", data["source_commit"], "--", prefix).split(b"\0")
        count = 0
        with BlobReader() as reader:
            for entry in entries:
                if not entry:
                    continue
                metadata, name = entry.split(b"\t", 1)
                mode, kind, blob = metadata.decode().split()
                if kind != "blob" or mode not in ("100644", "100755"):
                    raise ValueError("Unsupported historical tree entry: " + name.decode())
                actual, content = reader.read(blob)
                if actual != blob:
                    raise ValueError("Git object identity changed")
                write_source(output, name.decode(), content, mode)
                count += 1
        print(f"Recovered {count} exact snapshot files under {output / prefix}")
    else:
        selected = set(paths) if paths else {item["path"] for item in data["files"]
                                            if item["storage"] == "git-history"}
        records = {item["path"]: item for item in data["files"]}
        unknown = selected - records.keys()
        if unknown:
            raise ValueError("Unknown evidence source: " + repr(sorted(unknown)))
        for path in sorted(selected):
            record = records[path]
            write_source(output, path, read_source(path), record["mode"])
        print(f"Recovered {len(selected)} exact source files under {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    actions.add_parser("verify", help="Check every original object, hash and retained musl snapshot")
    read = actions.add_parser("read", help="Write one verified historical source to stdout")
    read.add_argument("path")
    recover = actions.add_parser("materialize", help="Recover exact source bytes outside this checkout")
    recover.add_argument("--output", type=Path, required=True)
    selection = recover.add_mutually_exclusive_group()
    selection.add_argument("--path", action="append", default=[])
    selection.add_argument("--snapshot", choices=CAMPAIGNS,
                           help="Recover the entire original campaign, including frozen scripts/logs")
    args = parser.parse_args()
    try:
        data = manifest()
        if args.action == "verify":
            verify(data)
        elif args.action == "read":
            sys.stdout.buffer.write(read_source(args.path))
        else:
            materialize(data, args.output, args.path, args.snapshot)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, "Cannot recover historical source evidence: " + str(error) + "\n")


if __name__ == "__main__":
    main()
