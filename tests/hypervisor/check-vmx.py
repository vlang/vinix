#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Test production VMX exports, compile privileged ports and compare entry bytes."""
import argparse
import errno
import fcntl
import json
import locale
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def symbol_bytes(path, name):
    """Read an ELF64 function without relying on a platform-specific nm."""
    data = path.read_bytes()
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", data)
    if header[0][:6] != b"\x7fELF\x02\x01":
        raise RuntimeError(f"not little-endian ELF64: {path}")
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, header[6] + i * header[11])
                for i in range(header[12])]
    for section in sections:
        if section[1] != 2:  # SHT_SYMTAB
            continue
        strings = sections[section[6]]
        names = data[strings[4]:strings[4] + strings[5]]
        for offset in range(section[4], section[4] + section[5], section[9]):
            symbol = struct.unpack_from("<IBBHQQ", data, offset)
            if names[symbol[0]:].split(b"\0", 1)[0].decode() == name:
                content = sections[symbol[3]]
                start = content[4] + symbol[4] - content[3]
                return data[start:start + symbol[5]]
    raise RuntimeError(f"missing {name} in {path}")



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", type=Path,
                        help="optional pre-port vmx.c for exact entry byte comparison")
    args = parser.parse_args()
    compiler = os.environ.get("CC", "clang")
    v = subprocess.check_output([
        "sh", "-c", '. "$1/build-support/find-v.sh"; printf "%s" "$V"',
        "find-v", str(ROOT)], text=True)
    with tempfile.TemporaryDirectory(prefix="vinix-vmx-", dir="/tmp") as directory:
        work = Path(directory)
        command = [str(ROOT / "build-support/run-v-tool.sh"),
                   str(Path(__file__).with_suffix(".v")), "--root=" + str(ROOT),
                   "--work=" + directory,
                   "--caller-arch=" + ("arm64" if os.uname().machine in ("arm64", "aarch64") else "amd64")]
        def phase(name, state=None):
            descriptors = []
            try:
                for fd in (0, 1):
                    try:
                        descriptors.append(-1 if fcntl.fcntl(fd, fcntl.F_GETFD) & fcntl.FD_CLOEXEC
                            else fcntl.fcntl(fd, fcntl.F_DUPFD_CLOEXEC, 3))
                    except OSError as error:
                        if error.errno != errno.EBADF:
                            raise
                        descriptors.append(-1)
                result = subprocess.run(command + ["--phase=" + name,
                    "--parent-stdin=" + str(descriptors[0]), "--parent-stdout=" + str(descriptors[1])],
                    input=json.dumps({"state": state, "compiler": os.fsencode(compiler).hex(), "v": v,
                        "python": os.fsencode(sys.executable).hex(),
                        "text_encoding": locale.getpreferredencoding(False),
                        "environment": [[os.fsencode(key).hex(), os.fsencode(value).hex()]
                            for key, value in os.environ.items()]}).encode(),
                    stdout=subprocess.PIPE, check=True,
                    pass_fds=tuple(fd for fd in descriptors if fd >= 0))
                reply = json.loads(result.stdout)
                if "error" in reply:
                    error = reply["error"]
                    if error["kind"] == "command":
                        raise subprocess.CalledProcessError(error["status"],
                            [os.fsdecode(bytes.fromhex(value)) for value in error["argv_bytes"]],
                            output=error.get("output"))
                    if error["kind"] == "UnicodeDecodeError":
                        raise UnicodeDecodeError(error["encoding"], bytes.fromhex(error["object"]),
                            error["start"], error["end"], error["reason"])
                    if error["kind"] == "os":
                        raise OSError(error["number"], error["message"],
                            os.fsdecode(bytes.fromhex(error["filename_bytes"]))
                            if error["filename_bytes"] is not None else None)
                    raise {"IndexError": IndexError, "StopIteration": StopIteration,
                           "RuntimeError": RuntimeError}[error["kind"]](error["message"])
                return reply
            finally:
                for fd in descriptors:
                    if fd >= 0:
                        os.close(fd)

        state = phase("host")
        source = work / "privileged.c"
        text = source.read_text()
        text += state["fx_assert"]
        text += state["descriptor_assert"]
        source.write_text(text)
        phase("instructions", {"text": text})
        print("VMX INSTRUCTION PASS: optimized x86 ports, CF/ZF capture, operands and barriers")
        phase("entry")
        if args.original:
            phase("reference", {"original": os.fsencode(args.original.resolve()).hex()})
            old = symbol_bytes(work / "original.o", "vinix_vmx_enter")
            new = symbol_bytes(work / "entry.o", "vinix_vmx_enter")
            state = phase("compare", {"old": old.hex(), "new": new.hex()})
            print(f"VMX ENTRY PASS: all {state['length']} instruction bytes match original C assembly")
        print("PASS VMX production V C ABI, ASan/UBSan, x86 assembly and no allocator imports")


if __name__ == "__main__":
    main()
