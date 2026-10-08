#!/usr/bin/env python3
"""Compile only the fixture against a coherently built production hax.jar."""
import argparse
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_native_spec = importlib.util.spec_from_file_location("vinix_android_native", ROOT / "build-support/android/_native.py")
_native = importlib.util.module_from_spec(_native_spec)
_native_spec.loader.exec_module(_native)


def digest(path):
    return _native.request("digest", path=str(path))


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
                        default=Path(__file__).with_name('AndroidAutofillProbeManifest.xml'))
    parser.add_argument('--aapt2', default='aapt2')
    parser.add_argument('--source', type=Path,
                        default=Path(__file__).with_name('AndroidAutofillProbe.java'))
    parser.add_argument('--javac', default='javac')
    parser.add_argument('--java', default='java')
    args = parser.parse_args()
    _native.command("build_probe", kind="autofill", helper=str(Path(__file__)),
                    **{key: str(value) for key, value in vars(args).items()})


if __name__ == '__main__':
    main()
