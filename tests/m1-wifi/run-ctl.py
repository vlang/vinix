#!/usr/bin/env python3
# SPDX-License-Identifier: ISC
"""Run a native device fixture against the maintained V control utility."""
from pathlib import Path
import os, re, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
cc=os.environ.get("CC","clang")
with tempfile.TemporaryDirectory(prefix="vinix-wifi-cli-") as directory:
    work=Path(directory);source=work/"core.c";obj=work/"core.o"
    subprocess.run(["python3",str(root/"tools/m1-wifi/compile-v.py"),str(source)],check=True)
    flags=["-std=gnu11","-O2","-g","-fwrapv","-fno-strict-aliasing","-fsanitize=address,undefined","-fno-omit-frame-pointer","-Wall","-Wextra","-Werror","-I"+str(root/"tools/m1-wifi"),"-iquote",str(root/"kernel/c")]
    hooks=["open","close","read","tcgetattr","tcsetattr","nanosleep","ioctl"]
    subprocess.run([cc,*flags,"-Dmain=test_program_main",*["-D"+h+"=test_"+h for h in hooks],"-c",str(source),"-o",str(obj)],check=True)
    symbols=subprocess.check_output(["nm","-u",str(obj)],text=True)
    assert not re.search(r"\b_?(?:malloc|calloc|realloc|free|memdup|new_array\w*)\b",symbols),symbols
    fixture=work/"fixture"
    subprocess.run([cc,*flags,str(root/"tests/m1-wifi/ctl_fixture.c"),str(obj),"-o",str(fixture)],check=True)
    for scenario in ("status","on","off","networks","invalid","scan","join","join-timeout","stop"):
        subprocess.run([str(fixture),scenario],check=True)
    bundle=work/"bundle";bundle.mkdir()
    manifest=bytearray(128);manifest[0]=3;(bundle/"manifest.bin").write_bytes(manifest)
    for index,name in enumerate(("firmware.bin","nvram.txt","clm.blob","txcap.blob")):
        (bundle/name).write_bytes(bytes([index+1])*(5000 if index==0 else 100))
    subprocess.run([str(fixture),"load",str(bundle)],check=True)
    (bundle/"txcap.blob").write_bytes(b"")
    result=subprocess.run([str(fixture),"load-bad",str(bundle)],capture_output=True,text=True)
    assert result.returncode==1 and "Wi-Fi pre-upload fixture: PASS" in result.stdout,(result.returncode,result.stdout,result.stderr)
    print("Wi-Fi control: sanitizer fixture and allocator-import checks PASS",flush=True)
