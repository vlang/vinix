#!/usr/bin/env python3
"""Compile ATL's Java classes with the pinned D8, accepting Meson's dx arguments."""
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zipfile

R8_SHA256 = "900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199"
CORE_SHA256 = "f47736d9d410766a20ae1f60d679607d8e85241e8cdeb5a0c040ab260ba68f42"
ARGUMENTS = ["--release", "--min-api", "26", "--android-platform-build",
             "--force-passthrough-assertions"]


def main():
    r8 = Path(os.environ["VINIX_ATL_R8"])
    core = Path(os.environ["VINIX_ATL_CORE_CLASSES"])
    for path, expected in ((r8, R8_SHA256), (core, CORE_SHA256)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise RuntimeError(f"ATL compiler input checksum mismatch: {path}")
    arguments = sys.argv[1:]
    outputs = [arg[9:] for arg in arguments if arg.startswith("--output=")]
    inputs = [arg for arg in arguments if not arg.startswith("--")]
    if (len(outputs) != 1 or len(inputs) != 1
            or any(arg.startswith("--") and arg not in ("--dex", "--incremental")
                   and not arg.startswith("--output=") for arg in arguments)):
        raise RuntimeError("unsupported ATL dx arguments")
    source = Path(inputs[0]).resolve()
    output = Path(outputs[0]).resolve()
    libraries = ["--lib", str(core)]
    hax = source.parent.parent / "api-impl" / "hax.jar"
    if source != hax and hax.is_file():
        libraries += ["--lib", str(hax)]
    with tempfile.TemporaryDirectory(prefix="atl-dex-", dir=output.parent) as directory:
        subprocess.run([os.environ.get("VINIX_ATL_JAVA_D8", "java"), "-cp", str(r8),
                        "com.android.tools.r8.D8", *ARGUMENTS, *libraries,
                        "--output", directory, str(source)], check=True)
        payload = {}
        with zipfile.ZipFile(source) as classes:
            for name in classes.namelist():
                if not name.endswith(".class") and not name.endswith("/"):
                    payload[name] = classes.read(name)
        for path in sorted(Path(directory).glob("*.dex")):
            data = path.read_bytes()
            if not data.startswith(b"dex\n"):
                raise RuntimeError(f"invalid D8 output: {path}")
            offset = struct.unpack_from("<I", data, 52)[0]
            count = struct.unpack_from("<I", data, offset)[0]
            for index in range(count):
                kind, _, size, _ = struct.unpack_from("<HHII", data, offset + 4 + 12 * index)
                if kind == 7 and size:
                    raise RuntimeError("D8 retained unsupported Java bootstrap callsites")
            payload[path.name] = data
        if "classes.dex" not in payload:
            raise RuntimeError("D8 did not produce classes.dex")
        temporary = output.with_suffix(".jar.next")
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in sorted(payload.items()):
                entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o644 << 16
                archive.writestr(entry, data)
        temporary.replace(output)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        sys.exit(f"atl-dex: {error}")
