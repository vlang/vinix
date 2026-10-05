#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Sanitize native V rendering/output policy against independent API fixtures."""
from pathlib import Path
import os, re, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
cc=os.environ.get("CC","clang")
with tempfile.TemporaryDirectory(prefix="vinix-triangle-") as directory:
    work=Path(directory)
    flags=["-std=gnu11","-O2","-g","-fwrapv","-fno-strict-aliasing","-fsanitize=address,undefined","-fno-omit-frame-pointer","-Wall","-Wextra","-Werror","-DVINIX_TRIANGLE_HOST_TEST","-I"+str(root/"gl-triangle"),"-I"+str(root/"tests/gl-triangle"),"-I/opt/homebrew/include"]
    hooks=["open","close","ioctl","mmap","munmap","malloc","free"]
    for kind in ("egl","glut","legacy"):
        source=work/(kind+".c");obj=work/(kind+".o");fixture=work/kind
        subprocess.run(["python3",str(root/"gl-triangle/compile-v.py"),str(source),"--kind",kind],check=True)
        subprocess.run([cc,*flags,"-Dmain=test_program_main",*["-D"+h+"=test_"+h for h in hooks],"-c",str(source),"-o",str(obj)],check=True)
        symbols=subprocess.check_output(["nm","-u",str(obj)],text=True)
        assert not re.search(r"\b_?(?:calloc|realloc|memdup|new_array\w*)\b",symbols),symbols
        subprocess.run([cc,*flags,*( ["-DVINIX_GLUT_TRIANGLE"] if kind!="egl" else [] ),*( ["-DVINIX_LEGACY_TRIANGLE"] if kind=="legacy" else [] ),str(root/"tests/gl-triangle/native_fixture.c"),str(obj),"-o",str(fixture)],check=True)
        scenarios=[[]] if kind!="egl" else [[],["--submit-only"],["--submit-only","--depth"],["--submit-only","--stencil"],["--submit-only","--depth-stencil"],["--depth"],["--stencil"],["--depth-stencil"]]
        for args in scenarios:
            result=subprocess.run([str(fixture),*args],capture_output=True,text=True,check=True)
            assert "Triangle native fixture: PASS" in result.stdout,result.stdout
            assert "VINIX M1 AGX RENDER TEST: PASS" not in result.stdout,result.stdout
            print(kind+" "+" ".join(args)+": PASS",flush=True)
        if kind=="egl":
            for bpp in ("16","24","32"):
                subprocess.run([str(fixture)],env={**os.environ,"TRIANGLE_FB_BPP":bpp},capture_output=True,text=True,check=True)
            for setting in ("TRIANGLE_SOFTWARE","TRIANGLE_APPLE"):
                result=subprocess.run([str(fixture)],env={**os.environ,setting:"1"},capture_output=True,text=True,check=True)
                assert "Triangle native fixture: PASS" in result.stdout,(result.stdout,result.stderr)
                assert ("VINIX M1 AGX RENDER TEST: PASS" in result.stdout)==(setting=="TRIANGLE_APPLE"),result.stdout
    print("Triangle sanitizer API/lifetime fixtures: PASS",flush=True)
