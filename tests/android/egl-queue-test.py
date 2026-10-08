#!/usr/bin/env python3
"""Build a normal SurfaceView/JNI APK against the selected production ATL."""
import argparse
import os
import platform
import importlib.util
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[2]
_native_spec = importlib.util.spec_from_file_location("vinix_android_native", ROOT / "build-support/android/_native.py")
_native = importlib.util.module_from_spec(_native_spec)
_native_spec.loader.exec_module(_native)


def digest(path):
    return _native.request("runner_digest", path_hex=os.fsencode(path).hex())


def write_entry(archive, name, data):
    entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
    entry.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(entry, data)


def native_elf(path):
    return _native.request("advanced_native_elf", path_hex=os.fsencode(path).hex())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--framework-classes', type=Path, required=True)
    parser.add_argument('--framework-res', type=Path, required=True)
    parser.add_argument('--core-classes', type=Path, required=True)
    parser.add_argument('--r8', type=Path, required=True)
    parser.add_argument('--jni-include', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cc', default='gcc')
    parser.add_argument('--javac', default='javac')
    parser.add_argument('--java', default='java')
    parser.add_argument('--aapt2', default='aapt2')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    fields = {"tool_arch": platform.machine(), "kind": 'egl-queue', "helper": str(Path(__file__)),
              "source": str(here / 'AndroidEglQueueProbe.java'), "native_source": str(here / 'android-egl-queue-probe.c'),
              "manifest": str(here / 'AndroidEglQueueProbeManifest.xml'),
              **{key: str(getattr(args, key)) for key in
                 ("r8", "core_classes", "framework_classes", "framework_res", "jni_include",
                  "output", "cc", "javac", "java", "aapt2")}}
    _native.command("build_advanced_probe", fields={key: os.fsencode(value).hex() for key, value in fields.items()})


if __name__ == '__main__':
    main()
