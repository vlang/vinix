#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Store each repeated file in an initramfs tar once.

    build-support/link-duplicate-files.py IN.tar OUT.tar

Vinix's loader opens libraries with O_NOFOLLOW, so the desktop staging copies
what would be symlinks instead: libfoo.so.1 next to libfoo.so.1.2.3, and Mesa's
software driver under four names. A fifth of the compact desktop image is such
repeats, and gzip cannot fold them together: each copy is megabytes away from
the last. Here every later copy becomes a hard-link entry naming the first.
kernel/initramfs creates those with fs.link(), so the unpacked tree reads the
same, and on the Asahi ESP, which has room for little more than the image,
the compressed image is that much smaller.

Only regular files below usr/lib and usr/share are linked, so no program can
tell by the name it was run under. A file is linked only to one with the same
mode and owner, and only when no name appears twice in the archive: the
loader writes a repeated name over the file already there, which would reach
every name linked to it. The result is checked against the input before it
is kept.
"""

import copy
import hashlib
import os
import sys
import tarfile

LINKED_PREFIXES = ('./usr/lib/', './usr/share/', 'usr/lib/', 'usr/share/')
MIN_SIZE = 4096
USTAR_LINKNAME_MAX = 100


def digest(archive, member):
    h = hashlib.sha256()
    f = archive.extractfile(member)
    while True:
        chunk = f.read(1 << 20)
        if not chunk:
            break
        h.update(chunk)
    return h.hexdigest()


def plan(path):
    """Map each repeated member name to the first name with its content."""
    first = {}
    links = {}
    seen_names = set()
    with tarfile.open(path) as archive:
        for m in archive:
            if m.name in seen_names:
                sys.exit(f'error: {m.name} appears twice; not linking anything')
            seen_names.add(m.name)
            if not m.isfile() or m.size < MIN_SIZE or not m.name.startswith(LINKED_PREFIXES):
                continue
            key = (digest(archive, m), m.size, m.mode, m.uid, m.gid)
            if key in first:
                if len(first[key]) <= USTAR_LINKNAME_MAX:
                    links[m.name] = first[key]
            else:
                first[key] = m.name
    return links


def rewrite(src, dst, links):
    saved = 0
    with tarfile.open(src) as archive, \
            tarfile.open(dst, 'w', format=tarfile.USTAR_FORMAT) as out:
        for m in archive:
            target = links.get(m.name)
            if target is None:
                out.addfile(m, archive.extractfile(m) if m.isfile() else None)
                continue
            link = copy.copy(m)
            link.type = tarfile.LNKTYPE
            link.linkname = target
            link.size = 0
            out.addfile(link)
            saved += m.size
    return saved


def check(src, dst):
    """Every name the input has reads the same content from the output."""
    expected = {}
    with tarfile.open(src) as archive:
        for m in archive:
            expected[m.name] = ('file', digest(archive, m)) if m.isfile() else (m.type, m.linkname)
    got = {}
    content = {}
    with tarfile.open(dst) as archive:
        for m in archive:
            if m.isfile():
                content[m.name] = digest(archive, m)
                got[m.name] = ('file', content[m.name])
            elif m.islnk() and expected.get(m.name, ('',))[0] == 'file':
                if m.linkname not in content:
                    sys.exit(f'error: {m.name} links to {m.linkname}, which comes later')
                got[m.name] = ('file', content[m.linkname])
            else:
                got[m.name] = (m.type, m.linkname)
    if got != expected:
        missing = sorted(set(expected) ^ set(got))[:5]
        changed = sorted(n for n in expected if n in got and got[n] != expected[n])[:5]
        sys.exit(f'error: output differs from input (names {missing}, content {changed})')


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().split('\n\n')[1])
    src, dst = sys.argv[1], sys.argv[2]
    links = plan(src)
    tmp = dst + '.tmp'
    try:
        saved = rewrite(src, tmp, links)
        check(src, tmp)
        os.replace(tmp, dst)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    print(f'linked {len(links)} repeated files, {saved / 1e6:.1f} MB stored once')


if __name__ == '__main__':
    main()
