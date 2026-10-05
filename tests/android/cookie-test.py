#!/usr/bin/env python3
"""Compile only the fixture against a coherently built production hax.jar."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import subprocess
import zipfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--framework-classes', type=Path, required=True,
                        help='actual patched ATL output/src/api-impl/hax.jar')
    parser.add_argument('--core-classes', type=Path, required=True)
    parser.add_argument('--r8', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--framework-res', type=Path, required=True,
                        help='coherent production framework-res.apk for manifest linking')
    parser.add_argument('--manifest', type=Path,
                        default=Path(__file__).with_name('AndroidCookieProbeManifest.xml'))
    parser.add_argument('--aapt2', default='aapt2')
    parser.add_argument('--source', type=Path,
                        default=Path(__file__).with_name('AndroidCookieProbe.java'))
    parser.add_argument('--javac', default='javac')
    parser.add_argument('--java', default='java')
    args = parser.parse_args()
    expected = {
        args.r8: '900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199',
        args.core_classes: 'f47736d9d410766a20ae1f60d679607d8e85241e8cdeb5a0c040ab260ba68f42',
    }
    for path, checksum in expected.items():
        if digest(path) != checksum:
            raise SystemExit(f'pinned compiler input mismatch: {path}')
    args.output.mkdir(parents=True, exist_ok=True)
    classes = args.output / 'classes'
    if classes.exists():
        shutil.rmtree(classes)
    classes.mkdir()
    subprocess.run([args.javac, '-source', '8', '-target', '8', '-bootclasspath',
                    str(args.core_classes), '-cp', str(args.framework_classes),
                    '-d', str(classes), str(args.source)], check=True)
    jar = args.output / 'cookie-fixture-classes.jar'
    with zipfile.ZipFile(jar, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(classes.rglob('AndroidCookieProbe*.class')):
            entry = zipfile.ZipInfo(path.relative_to(classes).as_posix(), (1980, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, path.read_bytes())
    output = args.output / 'android-cookie-probe.jar'
    subprocess.run([args.java, '-cp', str(args.r8), 'com.android.tools.r8.D8',
                    '--min-api', '26', '--lib', str(args.core_classes), '--lib',
                    str(args.framework_classes), '--output', str(output), str(jar)], check=True)
    with zipfile.ZipFile(jar) as archive:
        if not archive.namelist() or any(not name.startswith('org/vinix/tests/AndroidCookieProbe')
                                        for name in archive.namelist()):
            raise SystemExit('fixture contains unexpected provider classes')
    apk = args.output / 'android-cookie-probe.apk'
    subprocess.run([args.aapt2, 'link', '--manifest', str(args.manifest),
                    '-I', str(args.framework_res), '-o', str(apk)], check=True)
    with zipfile.ZipFile(output) as dex, zipfile.ZipFile(apk, 'a', zipfile.ZIP_DEFLATED) as archive:
        names = dex.namelist()
        if names != ['classes.dex']:
            raise SystemExit('fixture D8 archive contains unexpected entries')
        entry = zipfile.ZipInfo('classes.dex', (1980, 1, 1, 0, 0, 0))
        entry.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(entry, dex.read('classes.dex'))
    with zipfile.ZipFile(apk) as archive:
        if not {'AndroidManifest.xml', 'classes.dex'} <= set(archive.namelist()) or not set(archive.namelist()) <= {'AndroidManifest.xml', 'resources.arsc', 'classes.dex'}:
            raise SystemExit('fixture APK contains unexpected payloads')
    receipt = {
        'source_sha256': digest(args.source),
        'framework_classes_sha256': digest(args.framework_classes),
        'core_classes_sha256': digest(args.core_classes),
        'r8_sha256': digest(args.r8),
        'fixture_sha256': digest(output),
        'framework_res_sha256': digest(args.framework_res),
        'manifest_sha256': digest(args.manifest),
        'fixture_apk_sha256': digest(apk),
        'expected_marker': 'ANDROID-COOKIE-PASS',
        'fixture_uses_public_api': True,
        'persistence_activity': 'org.vinix.tests.AndroidCookieProbe$PersistenceActivity',
        'expected_reload_marker': 'ANDROID-COOKIE-RELOAD-PASS',
        'runtime_tested': False,
    }
    (args.output / 'cookie-probe-build.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(apk)


if __name__ == '__main__':
    main()
