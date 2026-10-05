#!/usr/bin/env python3
"""Build a normal SurfaceView/JNI APK against the selected production ATL."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import zipfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_entry(archive, name, data):
    entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
    entry.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(entry, data)


def native_elf(path):
    data = path.read_bytes()
    if data[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', data, 18)[0] != 183:
        raise SystemExit('fixture native library is not an ARM64 little-endian ELF')
    headers = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    loads = 0
    for index in range(count):
        kind, _, offset, address, _, filesz, _, align = struct.unpack_from('<IIQQQQQQ', data, headers + index * size)
        if kind == 1:
            loads += 1
            if align < 16384 or offset % 16384 != address % 16384:
                raise SystemExit('fixture native library cannot load with 16 KiB pages')
        if kind == 2:
            for position in range(offset, offset + filesz, 16):
                tag, _ = struct.unpack_from('<qQ', data, position)
                if tag == 0:
                    break
                if tag == 1:
                    raise SystemExit('fixture must import platform APIs without a host-library DT_NEEDED')
    if not loads:
        raise SystemExit('fixture native library has no loadable segments')


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
    for path, expected in ((args.r8, '900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199'),
                           (args.core_classes, 'f47736d9d410766a20ae1f60d679607d8e85241e8cdeb5a0c040ab260ba68f42')):
        if digest(path) != expected:
            raise SystemExit(f'pinned compiler input mismatch: {path}')
    target = subprocess.check_output([args.cc, '-dumpmachine'], text=True).strip()
    if not target.startswith('aarch64') or 'musl' not in target:
        raise SystemExit('fixture compiler must target ARM64 musl Linux')
    here = Path(__file__).resolve().parent
    source = here / 'AndroidEglQueueProbe.java'
    native_source = here / 'android-egl-queue-probe.c'
    manifest = here / 'AndroidEglQueueProbeManifest.xml'
    args.output.mkdir(parents=True, exist_ok=True)
    native = args.output / 'libvinix_egl_queue_probe.so'
    native_command = [args.cc, '-std=gnu11', '-O2', '-shared', '-fPIC', '-nostdlib',
                      '-fno-stack-protector', '-Wall', '-Wextra', '-Werror',
                      '-Wl,-z,max-page-size=16384', '-I' + str(args.jni_include),
                      '-I' + str(args.jni_include / 'linux'), str(native_source), '-o', str(native)]
    subprocess.run(native_command, check=True)
    native_elf(native)
    classes = args.output / 'classes'
    if classes.exists():
        shutil.rmtree(classes)
    classes.mkdir()
    subprocess.run([args.javac, '-source', '8', '-target', '8', '-bootclasspath', str(args.core_classes),
                    '-cp', str(args.framework_classes), '-d', str(classes), str(source)], check=True)
    jar = args.output / 'egl-queue-fixture-classes.jar'
    with zipfile.ZipFile(jar, 'w') as archive:
        for path in sorted(classes.rglob('*.class')):
            name = path.relative_to(classes).as_posix()
            if not re.fullmatch(r'org/vinix/tests/AndroidEglQueueProbe(?:\$[A-Za-z0-9_]+)*\.class', name):
                raise SystemExit('fixture contains a class outside its own app')
            write_entry(archive, name, path.read_bytes())
    dex = args.output / 'android-egl-queue-probe.jar'
    subprocess.run([args.java, '-cp', str(args.r8), 'com.android.tools.r8.D8', '--min-api', '26',
                    '--lib', str(args.core_classes), '--lib', str(args.framework_classes),
                    '--output', str(dex), str(jar)], check=True)
    apk = args.output / 'android-egl-queue-probe.apk'
    subprocess.run([args.aapt2, 'link', '--manifest', str(manifest), '-I', str(args.framework_res), '-o', str(apk)], check=True)
    with zipfile.ZipFile(dex) as compiled, zipfile.ZipFile(apk, 'a') as archive:
        if compiled.namelist() != ['classes.dex']:
            raise SystemExit('fixture D8 archive contains unexpected entries')
        write_entry(archive, 'classes.dex', compiled.read('classes.dex'))
        write_entry(archive, 'lib/arm64-v8a/libvinix_egl_queue_probe.so', native.read_bytes())
    with zipfile.ZipFile(apk) as archive:
        required = {'AndroidManifest.xml', 'classes.dex', 'lib/arm64-v8a/libvinix_egl_queue_probe.so'}
        if not required <= set(archive.namelist()) or not set(archive.namelist()) <= required | {'resources.arsc'}:
            raise SystemExit('fixture APK contains unexpected payloads')
    receipt = {'source_sha256': digest(source), 'native_source_sha256': digest(native_source),
               'manifest_sha256': digest(manifest), 'helper_sha256': digest(Path(__file__)),
               'framework_classes_sha256': digest(args.framework_classes),
               'framework_res_sha256': digest(args.framework_res), 'core_classes_sha256': digest(args.core_classes),
               'r8_sha256': digest(args.r8), 'native_library_sha256': digest(native),
               'fixture_apk_sha256': digest(apk), 'compiler_target': target,
               'native_compile_command': native_command, 'native_dt_needed': [],
               'activity': 'org.vinix.tests.AndroidEglQueueProbe$BootstrapActivity',
               'expected_marker': 'ANDROID-EGL-QUEUE-PASS', 'runtime_tested': False,
               'fixture_uses_public_api': True}
    (args.output / 'egl-queue-probe-build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(apk)


if __name__ == '__main__':
    main()
