#!/usr/bin/env python3
"""Package explicitly selected, locally extracted Apple firmware, not downloads.
The manifest binds the selection to a saved device status. It is not proof that
selected firmware/calibration files are appropriate: use the matching extracted
files for this board/module. No vendor firmware is distributed with the driver.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import struct


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--status', type=Path, required=True, help='wifi-ctl status-raw output')
    p.add_argument('--firmware', type=Path, required=True)
    p.add_argument('--nvram', type=Path, required=True)
    p.add_argument('--clm', type=Path, required=True)
    p.add_argument('--txcap', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    status = a.status.read_bytes()
    if len(status) != 256 or struct.unpack_from('<I', status)[0] != 1:
        p.error('status must be a 256-byte successful chip-probe response')
    revision = struct.unpack_from('<I', status, 8)[0]
    if revision not in (3, 5) or status[120:152].split(b'\0', 1)[0] != b'apple,shikoku':
        p.error('unsupported chip revision or board')
    manifest = bytearray(128)
    struct.pack_into('<I', manifest, 0, revision)
    for dst, src, length in ((8,40,16),(24,56,16),(40,72,16),(56,104,16),(72,120,32)):
        value = status[src:src+length]
        if not value[0] or b'\0' not in value:
            p.error('incomplete OTP/board identity')
        manifest[dst:dst+length] = value
    parts = []
    for src, name, limit in ((a.firmware,'firmware.bin',4*1024*1024),(a.nvram,'nvram.txt',65536),
                             (a.clm,'clm.blob',1024*1024),(a.txcap,'txcap.blob',1024*1024)):
        size = src.stat().st_size
        if not src.is_file() or not 0 < size <= limit:
            p.error(f'invalid file size: {src}')
        data = src.read_bytes()
        if len(data) != size:
            p.error(f'file changed while reading: {src}')
        if name == 'firmware.bin' and (len(data) < 0x74 or data[0x6c:0x70] != b'RAMS'):
            p.error('firmware has no expected RAMS header')
        if name == 'nvram.txt':
            if b'\0' in data:
                p.error('provide textual board NVRAM, not a packed binary')
            data.decode('ascii')
        parts.append((name, data, str(src)))
    a.output.mkdir(parents=True, exist_ok=False)
    (a.output/'manifest.bin').write_bytes(manifest)
    records = {}
    for name, data, source in parts:
        (a.output/name).write_bytes(data)
        records[name] = {'source':source,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
    (a.output/'provenance.json').write_text(json.dumps(records,indent=2)+'\n')
    print(f'Wrote {a.output}; selected firmware must match this machine’s board/module.')

if __name__ == '__main__':
    main()
