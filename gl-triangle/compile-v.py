#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate a native V triangle program for the target userspace compiler."""
from pathlib import Path
import argparse, hashlib, os, shutil, subprocess, tempfile
here = Path(__file__).resolve().parent
root = here.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--kind", choices=("egl","glut","legacy"), default="egl")
parser.add_argument("--arch", choices=("amd64","arm64"), default="arm64")
parser.add_argument("--source", type=Path, help="alternate maintained module source for image comparison")
args = parser.parse_args()
module = {"egl":"egltri","glut":"gluttri","legacy":"legacytri"}[args.kind]
finder = root / "build-support/find-v.sh"
if finder.is_file():
    v = subprocess.check_output(["sh","-c",'. "$1/build-support/find-v.sh"; printf "%s" "$V"',"find-v",str(root)],text=True)
else:
    v = os.environ.get("V") or shutil.which("v")
    if not v: raise SystemExit("V is required to regenerate the triangle source")
with tempfile.TemporaryDirectory(prefix="vinix-gl-v-") as directory:
    work = Path(directory)
    source_dir = here/{"egl":"eglcore","glut":"glutcore","legacy":"legacycore"}[args.kind]
    shutil.copytree(source_dir,work/module)
    if args.source: shutil.copyfile(args.source,work/module/"core.v")
    digest = hashlib.sha256()
    for path in sorted((work/module).glob("*.v")): digest.update(path.read_bytes())
    digest.update((here/"gl_v.h").read_bytes())
    (work/"v.mod").write_text("Module {name: 'gl_triangle'}\n")
    (work/"entry.v").write_text("module main\nimport "+module+" as _\n")
    generated=work/"output.c"
    subprocess.run([v,"-shared","-no-builtin","-no-closures","-os","vinix","-arch",args.arch,"-target-libc-headers","-gc","none","-manualfree","-o",str(generated),str(work)],check=True,env={**os.environ,"V_C_ERROR_BUG_REPORT_DISABLED":"1"})
    output=generated.read_text()
args.output.write_text("/* Generated from maintained V; source SHA256 " + digest.hexdigest() + " */\n"+('#define VINIX_GLUT_TRIANGLE 1\n' if args.kind!='egl' else '')+'#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n#pragma GCC diagnostic ignored "-Wunused-label"\n#pragma GCC diagnostic ignored "-Wpointer-sign"\n'+output)
