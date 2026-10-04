#!/usr/bin/env python3
"""Build a normal base APK, a dexless ARM64 split, and invalid split pairs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def append(archive, name, data):
    entry = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
    entry.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(entry, data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--framework-classes', type=Path, required=True)
    parser.add_argument('--framework-res', type=Path, required=True)
    parser.add_argument('--core-classes', type=Path, required=True)
    parser.add_argument('--r8', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--javac', default='javac')
    parser.add_argument('--java', default='java')
    parser.add_argument('--aapt2', default='aapt2')
    parser.add_argument('--cc', default='cc', help='native ARM64 compiler; this helper is run on ARM64')
    parser.add_argument('--jni-include', type=Path, required=True)
    args = parser.parse_args()
    for path, expected in ((args.core_classes, 'f47736d9d410766a20ae1f60d679607d8e85241e8cdeb5a0c040ab260ba68f42'),
                           (args.r8, '900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199')):
        if digest(path) != expected:
            raise SystemExit(f'pinned compiler input mismatch: {path}')
    here = Path(__file__).resolve().parent
    source = here / 'AndroidSplitApkProbe.java'
    base_manifest = here / 'AndroidSplitApkProbeManifest.xml'
    split_manifest = here / 'AndroidSplitApkProbeConfigManifest.xml'
    native_source = here / 'android-split-probe.c'
    args.output.mkdir(parents=True, exist_ok=True)
    classes = args.output / 'classes'
    if classes.exists():
        shutil.rmtree(classes)
    classes.mkdir()
    subprocess.run([args.javac, '-source', '8', '-target', '8', '-bootclasspath', str(args.core_classes),
                    '-cp', str(args.framework_classes), '-d', str(classes), str(source)], check=True)
    jar = args.output / 'split-fixture-classes.jar'
    with zipfile.ZipFile(jar, 'w') as archive:
        for path in sorted(classes.rglob('*.class')):
            name = path.relative_to(classes).as_posix()
            if not re.fullmatch(r'org/vinix/tests/AndroidSplitApkProbe(?:\$[A-Za-z0-9_]+)*\.class', name):
                raise SystemExit('fixture contains an unexpected provider class')
            append(archive, name, path.read_bytes())
        if not archive.namelist():
            raise SystemExit('fixture contains no classes')
    dex_output = args.output / 'split-fixture-dex.jar'
    subprocess.run([args.java, '-cp', str(args.r8), 'com.android.tools.r8.D8', '--min-api', '26',
                    '--lib', str(args.core_classes), '--lib', str(args.framework_classes),
                    '--output', str(dex_output), str(jar)], check=True)
    base = args.output / 'android-split-probe.apk'
    subprocess.run([args.aapt2, 'link', '--manifest', str(base_manifest), '-I', str(args.framework_res), '-o', str(base)], check=True)
    with zipfile.ZipFile(dex_output) as dex, zipfile.ZipFile(base, 'a') as archive:
        if dex.namelist() != ['classes.dex']:
            raise SystemExit('unexpected D8 payload')
        append(archive, 'classes.dex', dex.read('classes.dex'))
    library = args.output / 'libvinix_split_probe.so'
    subprocess.run([args.cc, '-shared', '-fPIC', '-nostdlib', '-Wl,-z,max-page-size=65536',
                    '-I' + str(args.jni_include), '-I' + str(args.jni_include / 'linux'),
                    str(native_source), '-o', str(library)], check=True)
    elf = library.read_bytes()
    if elf[:4] != b'\x7fELF' or elf[4] != 2 or int.from_bytes(elf[18:20], 'little') != 183:
        raise SystemExit('fixture compiler did not produce a genuine ARM64 ELF library')
    template = split_manifest.read_text()
    variants = {
        'config.arm64_v8a.apk': template,
        'bad-package.apk': template.replace('org.vinix.tests.split', 'org.vinix.tests.other'),
        'bad-version.apk': template.replace('7007', '7008'),
        'bad-empty-name.apk': template.replace(' split="config.arm64_v8a"', ''),
        'bad-code.apk': template.replace('android:hasCode="false"', 'android:hasCode="true"'),
        'bad-dependent.apk': template.replace('split="config.arm64_v8a"', 'split="config.arm64_v8a" configForSplit="feature"'),
        'bad-components.apk': template.replace('<application android:hasCode="false" android:extractNativeLibs="true" />',
                '<application android:hasCode="false"><activity android:name="org.vinix.tests.Other" /></application>'),
        'duplicate-name.apk': template,
        'bad-hidden-dex.apk': template,
    }
    for name, xml in variants.items():
        manifest = args.output / (name + '.xml')
        manifest.write_text(xml)
        apk = args.output / name
        subprocess.run([args.aapt2, 'link', '--manifest', str(manifest), '-I', str(args.framework_res), '-o', str(apk)], check=True)
        if name == 'config.arm64_v8a.apk':
            with zipfile.ZipFile(apk, 'a') as archive:
                append(archive, 'lib/arm64-v8a/libvinix_split_probe.so', elf)
                append(archive, 'assets/vinix-split-marker.txt', b'SPLIT-ASSET\n')
        if name == 'bad-hidden-dex.apk':
            with zipfile.ZipFile(dex_output) as dex, zipfile.ZipFile(apk, 'a') as archive:
                append(archive, 'classes.dex', dex.read('classes.dex'))
    missing = args.output / 'bad-missing-manifest.apk'
    with zipfile.ZipFile(missing, 'w') as archive:
        append(archive, 'assets/only.txt', b'No manifest here\n')
    with zipfile.ZipFile(base) as archive:
        if not set(archive.namelist()) <= {'AndroidManifest.xml', 'resources.arsc', 'classes.dex'}:
            raise SystemExit('unexpected base APK payload')
    with zipfile.ZipFile(args.output / 'config.arm64_v8a.apk') as archive:
        if not set(archive.namelist()) <= {'AndroidManifest.xml', 'resources.arsc', 'lib/arm64-v8a/libvinix_split_probe.so', 'assets/vinix-split-marker.txt'}:
            raise SystemExit('unexpected configuration split payload')
    cases = [
        {'name': 'wrong-package', 'splits': ['bad-package.apk'], 'error': 'Split APK identity does not match the base'},
        {'name': 'wrong-version', 'splits': ['bad-version.apk'], 'error': 'Split APK identity does not match the base'},
        {'name': 'empty-name', 'splits': ['bad-empty-name.apk'], 'error': 'Split APK identity does not match the base'},
        {'name': 'code', 'splits': ['bad-code.apk'], 'error': 'Split APK components or code are not supported'},
        {'name': 'dependency', 'splits': ['bad-dependent.apk'], 'error': 'Feature and dependent split APKs are not supported'},
        {'name': 'components', 'splits': ['bad-components.apk'], 'error': 'Split APK components or code are not supported'},
        {'name': 'duplicate-name', 'splits': ['config.arm64_v8a.apk', 'duplicate-name.apk'], 'error': 'Split APK identity does not match the base'},
        {'name': 'hidden-dex', 'splits': ['bad-hidden-dex.apk'], 'error': 'Split APK DEX code is not supported'},
        {'name': 'missing-manifest', 'splits': ['bad-missing-manifest.apk'], 'error': 'APK archive has no AndroidManifest.xml'},
        {'name': 'install', 'splits': ['config.arm64_v8a.apk'], 'options': ['--install'], 'error': 'installing split APKs is not supported'},
        {'name': 'install-internal', 'splits': ['config.arm64_v8a.apk'], 'options': ['--install-internal'], 'error': 'installing split APKs is not supported'},
    ]
    (args.output / 'test-cases.json').write_text(json.dumps({'cases': cases}, indent=2) + '\n')
    receipt = {
        'inputs': {p.name: digest(p) for p in (source, base_manifest, split_manifest, native_source, args.framework_classes, args.framework_res, args.core_classes, args.r8)},
        'outputs': {p.name: digest(p) for p in sorted(args.output.glob('*.apk'))},
        'library_sha256': digest(library),
        'helper_sha256': digest(Path(__file__)),
        'test_cases_sha256': digest(args.output / 'test-cases.json'),
        'activity': 'org.vinix.tests.AndroidSplitApkProbe$BootstrapActivity',
        'expected_marker': 'ANDROID-SPLIT-PASS',
        'runtime_tested': False,
        'fixture_uses_public_api': True,
        'signatures': 'Local unsigned test fixture only; genuine app archives are separately signature-verified.',
    }
    (args.output / 'split-probe-build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(base)


if __name__ == '__main__':
    main()
