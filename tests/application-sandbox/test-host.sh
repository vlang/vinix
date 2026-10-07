#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
. "$root/build-support/find-v.sh"
export VEXE="$V"
source=
keep=
host_arch=$(uname -m)
while [ "$#" -gt 0 ]; do
    case "$1" in
        --source) source=$2; shift 2 ;;
        --keep-dir) keep=$2; shift 2 ;;
        --arch) host_arch=$2; shift 2 ;;
        *) echo "usage: $0 [--source /immutable/host.c] [--keep-dir /new/evidence-dir] [--arch arm64|x86_64]" >&2; exit 2 ;;
    esac
done
if [ -n "$keep" ]; then
    mkdir "$keep"
    work=$(CDPATH= cd -- "$keep" && pwd)
else
    work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-sandbox-host.XXXXXX")
    trap 'rm -rf "$work"' EXIT HUP INT TERM
fi
python3 - "$root" "$work" "$source" "$host_arch" "$V" "${CC:-cc}" <<'PY'
from pathlib import Path
import hashlib, json, os, subprocess, sys
root, work = map(Path, sys.argv[1:3])
original, arch, v, cc = sys.argv[3:]
if arch in ("arm64", "aarch64"):
    arch, v_arch = "arm64", "arm64"
elif arch in ("x86_64", "amd64"):
    arch, v_arch = "x86_64", "amd64"
else:
    raise SystemExit("unsupported host architecture")
native_arch = os.uname().machine
arch_flags = ["-arch", arch] if sys.platform == "darwin" else []
if not arch_flags and native_arch not in (arch, "aarch64" if arch == "arm64" else "amd64"):
    raise SystemExit("requested host architecture requires a native runner")
commands = []
def invoke(command):
    commands.append(command)
    (work/"commands.json").write_text(json.dumps(commands, indent=2)+"\n")
    subprocess.run(command, check=True)
invoke([sys.executable, str(root/"build-support/security-tools/compile-v-core.py"),
        "sandbox", str(work/"core.c"), "--arch", v_arch,
        "-d", "security_no_main", "-d", "security_fixture"])
common = [cc, *arch_flags, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
          "-fsanitize=address,undefined"]
invoke([*common, "-D_GNU_SOURCE", "-DVINIX_V_RUNTIME", "-DVINIX_SECURITY_FIXTURE",
        "-I", str(root/"tools/sandbox"), "-c", str(work/"core.c"), "-o", str(work/"core.o")])
if original:
    fixture = Path(original).resolve(strict=True)
    if not fixture.is_file():
        raise SystemExit("control source is not a file")
    invoke([*common, "-I", str(root/"tests/application-sandbox"),
            "-c", str(fixture), "-o", str(work/"fixture.o")])
else:
    fixture = work/"fixture.c"
    invoke([sys.executable, str(root/"build-support/compile-v-module.py"),
            str(root/"tests/application-sandbox/hostfixture"), str(fixture),
            "--arch", v_arch, "-d", "nofloat"])
    # Only unused compiler scaffolding receives these warning exceptions.
    invoke([*common, "-Wno-unused-function", "-Wno-unused-parameter", "-fPIC",
            "-I", str(root/"tests/application-sandbox/hostfixture"),
            "-I", str(root/"tools/sandbox"), "-c", str(fixture), "-o", str(work/"fixture.o")])
invoke([*common, str(work/"fixture.o"), str(work/"core.o"), "-o", str(work/"host")])
paths = [root/name for name in (
    "tests/application-sandbox/test-host.sh", "tools/sandbox/core/core.v",
    "tools/sandbox/core/native.v", "tools/sandbox/sandbox_v.h",
    "build-support/find-v.sh", "build-support/compile-v-module.py",
    "build-support/security-tools/compile-v-core.py")]
paths.extend((work/"core.c", work/"core.o", fixture, work/"fixture.o", work/"host"))
if not original:
    paths.extend(sorted((root/"tests/application-sandbox/hostfixture").glob("*")))
record = {"fixture": "original-C" if original else "maintained-V", "host": native_arch,
          "target_arch": arch, "v_version": subprocess.check_output([v, "version"], text=True).strip(),
          "cc_version": subprocess.check_output([cc, "--version"], text=True).splitlines()[0],
          "sanitizers": ["address", "undefined"],
          "inputs": {str(p): {"bytes": p.stat().st_size,
                              "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths}}
(work/"inputs.json").write_text(json.dumps(record, indent=2)+"\n")
PY
if ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1}" \
   UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1}" "$work/host" \
       >"$work/host.log" 2>"$work/failures.log"; then
    cat "$work/host.log"
else
    status=$?
    cat "$work/host.log"
    cat "$work/failures.log" >&2
    exit "$status"
fi
