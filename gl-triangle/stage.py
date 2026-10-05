#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Stage native V sources, ABI bindings and generated guest rebuild artifacts."""
from pathlib import Path
import argparse,shutil,subprocess
here=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("destination",type=Path)
parser.add_argument("--arch",choices=("amd64","arm64"),default="arm64")
args=parser.parse_args();args.destination.mkdir(parents=True,exist_ok=True)
for kind,name in (("egl","egl_triangle.c"),("glut","triangle.c"),("legacy","legacy_triangle.c")):
    subprocess.run(["python3",str(here/"compile-v.py"),str(args.destination/name),"--kind",kind,"--arch",args.arch],check=True)
for name in ("eglcore","glutcore","legacycore"):
    shutil.copytree(here/name,args.destination/name,dirs_exist_ok=True)
for name in ("gl_v.h","compile-v.py"):
    shutil.copyfile(here/name,args.destination/name)
