#!/usr/bin/env python3
"""Reject incomplete/wrong-architecture kernel artifacts using only stdlib.

Verifies the final ELF, not a relocatable object or V-to-C generation alone.
Symbols and call-site checks establish integration, not hardware operation.
"""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import re
import struct

REQUIRED = {
    'apple__wifi__initialise', 'apple__wifi__poll',
    'apple__wifi__WifiDevice_read', 'apple__wifi__WifiDevice_write',
    'apple__wifi__WifiDevice_ioctl',
    'brcm_m1_prepare', 'brcm_m1_status', 'brcm_m1_upload', 'brcm_m1_boot',
    'brcm_m1_join', 'brcm_m1_poll', 'brcm_m1_read', 'brcm_m1_write', 'brcm_m1_stop',
    'bw_probe', 'bw_start', 'bw_poll', 'bw_join_wpa2',
}

KERNEL_FILE_REQUEST_ID = struct.pack(
    '<4Q',
    0xc7b1dd30df4c8b88,
    0x0a82e883a194f07b,
    0xad97e90e83f1ed67,
    0x31eb5d1c5ff23b69,
)


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def elf_symbols(data: bytes) -> set[str]:
    require(len(data) >= 64 and data[:7] == b'\x7fELF\x02\x01\x01',
            'expected a little-endian ELF64 executable')
    h = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    _, kind, machine, version, entry, phoff, shoff, _, ehsize, phsize, phnum, shsize, shnum, _ = h
    require(kind == 2 and machine == 183 and version == 1 and ehsize == 64,
            'expected a linked AArch64 ET_EXEC kernel')
    require(phsize == 56 and phnum > 0 and phoff + phnum * phsize <= len(data),
            'invalid program-header table')
    require(shsize == 64 and shnum > 0 and shoff + shnum * shsize <= len(data),
            'invalid section-header table')
    executable_entry = False
    for i in range(phnum):
        kind, flags, offset, va, _, filesz, memsz, _ = struct.unpack_from('<IIQQQQQQ', data, phoff + i * phsize)
        require(kind not in (2, 3), 'kernel must not need a dynamic loader')
        if kind == 1:
            require(filesz <= memsz and offset + filesz <= len(data), 'invalid PT_LOAD extent')
            executable_entry |= bool(flags & 1 and va <= entry < va + memsz)
    require(executable_entry, 'entry point is outside executable load segments')
    require(data.count(KERNEL_FILE_REQUEST_ID) == 1,
            'kernel must contain exactly one Limine kernel-file request')
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shsize) for i in range(shnum)]
    names = set()
    undefined = set()
    for s in sections:
        if s[1] != 2:  # SHT_SYMTAB
            continue
        offset, size, link, stride = s[4], s[5], s[6], s[9]
        require(stride == 24 and size % 24 == 0 and offset + size <= len(data)
                and link < len(sections), 'invalid symbol table')
        strings = sections[link]
        require(strings[1] == 3 and strings[4] + strings[5] <= len(data), 'invalid string table')
        pool = data[strings[4]:strings[4] + strings[5]]
        for p in range(offset, offset + size, stride):
            name, _, _, section, _, _ = struct.unpack_from('<IBBHQQ', data, p)
            require(name < len(pool), 'symbol name out of bounds')
            end = pool.find(b'\0', name)
            require(end >= 0, 'unterminated symbol name')
            text = pool[name:end].decode('ascii')
            if text:
                (names if section else undefined).add(text)
    require(not undefined, 'unresolved symbols: ' + ', '.join(sorted(undefined)))
    require(REQUIRED <= names, 'missing linked Wi-Fi symbols: ' + ', '.join(sorted(REQUIRED - names)))
    return names


def body(source: str, name: str) -> str:
    match = re.search(r'^void ' + re.escape(name) + r'\(void\) \{\n(.*?)^\}', source, re.M | re.S)
    require(match is not None, 'missing generated function: ' + name)
    return match.group(1)


def verify_hooks(source: str) -> None:
    init = body(source, 'dev__console__initialise')
    poll = body(source, 'dev__console__poll_uart_input')
    require(init.count('apple__wifi__initialise();') == 1, 'missing/duplicate Wi-Fi initialization')
    require(poll.count('apple__wifi__poll();') == 1, 'missing/duplicate Wi-Fi polling')
    require(init.index('apple__wifi__initialise();') < init.index('sched__set_uart_poll_callback('),
            'poll callback installed before Wi-Fi initialization')
    require('aarch64__virtio_input__poll();' in poll and 'aarch64__uart__getc()' in poll,
            'existing UART/VirtIO input hooks were lost')


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('kernel', type=Path)
    p.add_argument('generated_c', type=Path)
    args = p.parse_args()
    try:
        data = args.kernel.read_bytes()
        names = elf_symbols(data)
        verify_hooks(args.generated_c.read_text())
    except (OSError, ValueError, struct.error) as e:
        p.exit(1, f'FAIL: {e}\n')
    print(f'PASS linked AArch64 static kernel; {len(REQUIRED)} required Wi-Fi symbols; {len(names)} defined symbols')
    print('PASS initialization and polling connected; UART/VirtIO preserved')
    print(f'SHA256 {hashlib.sha256(data).hexdigest()}  {args.kernel.name}')


if __name__ == '__main__':
    main()
