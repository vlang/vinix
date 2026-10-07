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
        *) echo "usage: $0 [--source /immutable/collector_test.c] [--keep-dir /new/evidence-dir] [--arch arm64|x86_64]" >&2; exit 2 ;;
    esac
done
if [ -n "$keep" ]; then
    mkdir "$keep"
    work=$(CDPATH= cd -- "$keep" && pwd)
else
    work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-audit-collector.XXXXXX")
    trap 'rm -rf "$work"' EXIT HUP INT TERM
fi
python3 - "$root" "$work" "$source" "$host_arch" "$V" "${CC:-cc}" <<'PY'
from pathlib import Path
import hashlib, json, os, re, subprocess, sys
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
        "audit", str(work/"core.c"), "--arch", v_arch,
        "-d", "security_no_main"])
common = [cc, *arch_flags, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
          "-fsanitize=address,undefined"]
invoke([*common, "-D_GNU_SOURCE", "-DVINIX_V_RUNTIME",
        "-I", str(root/"tools/security-audit"), "-c", str(work/"core.c"), "-o", str(work/"core.o")])
objects = [work/"fixture.o", work/"core.o"]
if original:
    fixture = Path(original).resolve(strict=True)
    if not fixture.is_file():
        raise SystemExit("control source is not a file")
    invoke([*common, "-c", str(fixture), "-o", str(work/"fixture.o")])
else:
    fixture = work/"fixture.c"
    invoke([sys.executable, str(root/"build-support/compile-v-module.py"),
            str(root/"tests/security-audit/collectorhostfixture"), str(fixture),
            "--arch", v_arch, "-d", "nofloat"])
    # Only unused compiler scaffolding receives these warning exceptions.
    invoke([*common, "-Wno-unused-function", "-Wno-unused-parameter", "-fPIC",
            "-I", str(root/"tests/security-audit/collectorhostfixture"),
            "-c", str(fixture), "-o", str(work/"fixture.o")])
    imports = subprocess.check_output(["nm", "-u", str(work/"fixture.o")], text=True)
    (work/"fixture-imports.txt").write_text(imports)
    if re.search(r"\b_?(?:malloc|calloc|realloc|memdup|new_array\w*|array_new\w*)\b", imports):
        raise SystemExit("implicit fixture allocator import: " + imports)
invoke([*common, *map(str, objects), "-o", str(work/"host")])
invoke([sys.executable, str(root/"build-support/security-tools/compile-v-core.py"),
        "audit", str(work/"collector.c"), "--arch", v_arch])
invoke([*common, "-D_GNU_SOURCE", "-DVINIX_V_RUNTIME",
        "-I", str(root/"tools/security-audit"), str(work/"collector.c"),
        "-o", str(work/"collector")])
paths = [root/name for name in (
    "tests/security-audit/collector-run.sh", "tools/security-audit/core/core.v",
    "tools/security-audit/core/native.v", "tools/security-audit/collector_v.h",
    "build-support/find-v.sh", "build-support/compile-v-module.py",
    "build-support/security-tools/compile-v-core.py")]
paths.extend((work/"core.c", fixture, *objects, work/"host", work/"collector.c", work/"collector"))
if not original:
    paths.extend(sorted((root/"tests/security-audit/collectorhostfixture").glob("*")))
record = {"fixture": "original-C" if original else "maintained-V", "host": native_arch,
          "target_arch": arch, "v_version": subprocess.check_output([v, "version"], text=True).strip(),
          "cc_version": subprocess.check_output([cc, "--version"], text=True).splitlines()[0],
          "sanitizers": ["address", "undefined"],
          "asan_options": os.environ.get("ASAN_OPTIONS", "detect_leaks=0:halt_on_error=1"),
          "ubsan_options": os.environ.get("UBSAN_OPTIONS", "halt_on_error=1"),
          "native_entry": "original fixed-argument fixture main" if original else "exported native fixture main; sanitizer instrumented",
          "inputs": {str(p): {"bytes": p.stat().st_size,
                              "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths}}
(work/"inputs.json").write_text(json.dumps(record, indent=2)+"\n")
PY
if ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1}" \
   UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1}" "$work/host" \
       >"$work/host.log" 2>"$work/failures.log"; then
    cat "$work/host.log"
    cat "$work/failures.log" >&2
else
    status=$?
    cat "$work/host.log"
    cat "$work/failures.log" >&2
    exit "$status"
fi

if [ "$(id -u)" -ne 0 ]; then
    if ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1}" \
       UBSAN_OPTIONS="${UBSAN_OPTIONS:-halt_on_error=1}" \
       "$work/collector" --once >"$work/output" 2>&1; then
        echo 'non-root collector unexpectedly succeeded' >&2
        exit 1
    fi
    rg -q 'root required' "$work/output"
fi
