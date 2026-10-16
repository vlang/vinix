#!/usr/bin/env python3
"""Run real iOS-targeted Mach-O instructions in an isolated Vinix ARM64 VM."""
from pathlib import Path
import argparse
import gzip
import importlib.util
import os
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FEATURES = (
    b"iOS PASS: lock-free Darwin atomic queues and node reuse",
    b"iOS PASS: Darwin assertion diagnostics and SIGABRT",
    b"iOS PASS: Darwin stack probes preserve native arguments",
    b"iOS PASS: Darwin descriptor checks and fortified operations with SIGTRAP",
    b"iOS PASS: Darwin Unicode rune flags and locale selection",
    b"iOS PASS: Darwin socket addresses, options and native network I/O",
    b"iOS PASS: image-scoped exit callbacks and real process termination",
    b"iOS PASS: Darwin floating and integer conversion errors",
    b"iOS PASS: Darwin NaN payloads and floating state preservation",
    b"iOS PASS: Darwin pipes, polling filters and native readiness waits",
    b"iOS PASS: Darwin file permissions and descriptor lifetime",
    b"iOS PASS: Darwin dispatch queues, deadlines and callback ownership",
    b"iOS PASS: Darwin descriptor controls and real file synchronization",
    b"iOS PASS: Darwin name resolution, address ownership and network I/O",
    b"iOS PASS: Darwin network interfaces, snapshots and address ownership",
    b"iOS PASS: Darwin system queries, account records and resource usage",
    b"iOS PASS: Darwin process credentials, signal delivery and allocation sizes",
    b"iOS PASS: native hierarchical app memory budgets and live accounting",
    b"iOS PASS: image-owned fork callbacks, real cloning and Darwin wait status",
    b"iOS PASS: Darwin thread attributes, native user stacks and detached creation",
    b"iOS PASS: Darwin condition attributes and native private synchronization",
    b"iOS PASS: native thread identities, explicit exit and key destructor iterations",
    b"iOS PASS: native thread scheduling, guarded Darwin parameters and privilege enforcement",
    b"iOS PASS: native Mach thread ports, send references and namespace lifetime",
    b"iOS PASS: Darwin ioctl controls, socket bytes and interface queries",
    b"iOS PASS: Darwin calendars, timezone configuration and native process clocks",
    b"iOS PASS: Mach-O arithmetic and libSystem imports",
    b"iOS PASS: legacy dyld imports and image/TLS lifecycle",
    b"iOS PASS: native chained and legacy pointer tags",
    b"iOS PASS: native CoreFoundation conversion, data and collection ownership",
    b"iOS PASS: native PCM conversion and AudioToolbox callback ABI",
    b"iOS PASS: native offline AudioUnit graph rendering and mixer ownership",
    b"iOS PASS: native CoreGraphics color precision, fill state and ownership",
    b"iOS PASS: native CoreGraphics providers, raw image formats and callback ownership",
    b"iOS PASS: native CoreGraphics geometry and HFA calling conventions",
    b"iOS PASS: native GameController typed key codes and string constants",
    b"iOS PASS: native Security certificates, public keys, constants and random bytes",
    b"iOS PASS: native Security X.509 and SSL policy ownership",
    b"iOS PASS: native Security explicit-anchor trust evaluation and key ownership",
    b"iOS PASS: native CFNetwork HTTP proxy settings and ownership",
    b"iOS PASS: native keychain queries, ownership and persistent credentials",
    b"iOS PASS: native CommonCrypto SHA, HMAC and AES calling conventions",
    b"iOS PASS: native framework constants match installed Apple libraries",
    b"iOS PASS: native accessibility metadata and weak container lifecycle",
    b"iOS PASS: native Objective-C reflection, replacement and dynamic classes",
    b"iOS PASS: native register-specific ARC calling conventions and ownership",
    b"iOS PASS: native UIKit bitmap contexts, image ownership and PNG/JPEG codecs",
    b"iOS PASS: bundled Mach-O libraries, dependent initialization and isolated image TLS",
    b"iOS PASS: import audit reports missing dependencies without executing app code",
    b"iOS PASS: lazy function imports defer unsupported calls",
    b"iOS PASS: Darwin stdio, varargs and system queries",
    b"iOS PASS: native UIKit scene and application launch",
    b"iOS PASS: native file launch and scene URL ownership",
    b"iOS PASS: thread-safe ARC and autorelease pools",
    b"iOS PASS: native Mach VM aliases and mapping lifetime",
    b"iOS PASS: return status and unsupported imports",
    b"iOS PASS: universal executable selects ARM64",
    b"iOS PASS: ARM64e and malformed images rejected",
    b"iOS PASS: UIKit Mach-O 27 button/action cases",
    b"iOS PASS: UIKit resize, keyboard, 1000 updates and ARC teardown",
)


import importlib.util as _loader
import sys as _sys
_namespace, _frame = globals, _sys._getframe
_ATTRIBUTE, _SET_ATTRIBUTE, _TRUTH, _SLICE = getattr, setattr, bool, slice
_LITERAL_CACHE = {}
_SLOT_KEYS = {name: _sys.intern(name) for name in ('ArgumentParser', 'FAIL_MARKERS', 'FEATURE_MARKERS', 'PASS_MARKER', 'PIPE', 'Popen', 'TemporaryDirectory', 'action', 'add_argument', 'check', 'compresslevel', 'copy2', 'copy_function', 'copyfileobj', 'copytree', 'default', 'description', 'env', 'environ', 'error', 'exec_module', 'get', 'help', 'join', 'link', 'loader', 'mkdir', 'module_from_spec', 'no_build', 'open', 'pack_into', 'parents', 'parse_args', 'ppsspp_cube', 'ppsspp_gow', 'ppsspp_muted', 'ppsspp_nzp', 'prefix', 'read_bytes', 'resolve', 'run', 'run_vm', 'spec_from_file_location', 'stdout', 'symlink_to', 'symlinks', 'timeout', 'touch', 'type', 'unlink', 'util', 'wait', 'with_2048', 'with_cxx', 'with_gles', 'with_ppsspp', 'write_bytes', 'write_text')}
_spec = _loader.spec_from_file_location('ios_controller_binding', Path(__file__).with_name('_native.py'))
_library = _loader.module_from_spec(_spec)
_spec.loader.exec_module(_library)


def _native(operation, scope, builtins):
    try:
        return _library.call(operation, _namespace(), builtins, scope)
    finally:
        scope = builtins = None


def _tuple(*items):
    return (*items,)


def _list(*items):
    return [*items]


def _tuple_literal(key, *items):
    try:
        return _LITERAL_CACHE.setdefault(key, (*items,))
    finally:
        items = None


def _mapping(value):
    try:
        return {**value}
    finally:
        value = None


def _FORMAT(value):
    try:
        return f"{value}"
    finally:
        value = None


def _retire(scope, order):
    for name in order:
        scope[name] = None


def _pin_scope(pins, scope):
    try:
        pins.insert(0, scope)
    finally:
        pins = scope = None

_IMAGES_ORDER = ('fixtures', 'destination', 'original', 'arm64e', 'second', 'fat')
_MAIN_ORDER = ('parser', 'arguments', 'build', 'env', 'runner_root', 'spec', 'runner', 'directory', 'work', 'rootfs', 'name', 'destination', 'missing_bundle', 'arm64e_bundle', 'leaf', 'unsupported_library', 'installed', 'binary', 'game', 'system', 'sysroot', 'archive', 'compressed', 'tar')


def prepare_images(fixtures: Path, destination: Path) -> None:
    scope = {name: None for name in _IMAGES_ORDER}
    scope.update(fixtures=fixtures, destination=destination)
    fixtures = destination = None
    try:
        result = _native('images', scope, _frame().f_builtins)
        _retire(scope, _IMAGES_ORDER)
        return result
    finally:
        scope = None


def stage_game_asset(source: str, destination: str) -> None:
    # The host only archives these files; all game writes happen in guest RAM.
    # Share the verified assets until then, saving a 98 MB temporary copy.
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)




def _workflow(scope, builtins):
    try:
        _native('plan', scope, builtins)
        with tempfile.TemporaryDirectory(prefix="vinix-ios-vm-") as directory:
            scope['directory'] = directory
            directory = None
            try:
                _native('stage', scope, builtins)
                if scope['arguments'].with_gles:
                    with gzip.open(scope['archive'], "wb", compresslevel=1) as compressed:
                        scope['compressed'] = compressed
                        compressed = None
                        try:
                            with subprocess.Popen(["tar", "--format=ustar", "-cf", "-", "-C", str(scope['rootfs']), "."],
                                    env={**os.environ, "COPYFILE_DISABLE": "1"}, stdout=subprocess.PIPE) as tar:
                                scope['tar'] = tar
                                tar = None
                                try:
                                    shutil.copyfileobj(scope['tar'].stdout, scope['compressed'])
                                    if scope['tar'].wait():
                                        raise RuntimeError("could not archive GLES guest root")
                                except:
                                    scope['_failed'] = True
                                    _saved_scope = scope
                                    raise
                        except:
                            scope['_failed'] = True
                            _saved_scope = scope
                            raise
                else:
                    subprocess.run(["tar", "--format=ustar", "-cf", str(scope['archive']),
                        "-C", str(scope['rootfs']), "."], env={**os.environ, "COPYFILE_DISABLE": "1"}, check=True)
                return _native('finish', scope, builtins)
            except:
                scope['_failed'] = True
                _saved_scope = scope
                raise
    finally:
        scope = builtins = None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true", help="reuse build/ios/staging/usr/bin/run-ios")
    parser.add_argument("--with-2048", action="store_true", help="also build and run pinned upstream iOS-2048")
    parser.add_argument("--with-cxx", action="store_true", help="also build and execute native iOS C++ ABI fixtures")
    parser.add_argument("--with-gles", action="store_true", help="run with the optional Mesa GLES backend and native graphics fixture")
    parser.add_argument("--with-ppsspp", action="store_true", help="probe native PPSSPP scene startup and report its unsupported API")
    parser.add_argument("--ppsspp-muted", action="store_true", help="test PPSSPP with its ordinary Sound/Enable=False preference")
    parser.add_argument("--ppsspp-cube", action="store_true", help="boot the pinned upstream PSP rotating-cube demo in the unchanged iOS app")
    parser.add_argument("--ppsspp-nzp", action="store_true", help="play the pinned NZ:P 3D PSP shooter in the unchanged iOS app")
    parser.add_argument("--ppsspp-gow", action="store_true", help="run Sony's God of War: Chains of Olympus PSP demo in the unchanged iOS app")
    parser.add_argument("--timeout", type=int, default=180)
    arguments = parser.parse_args()

    scope = {name: None for name in _MAIN_ORDER}
    scope.update(parser=parser, arguments=arguments)
    parser = arguments = None
    try:
        result = _workflow(scope, _frame().f_builtins)
        if not scope.get('_failed', False):
            _retire(scope, _MAIN_ORDER)
        return result
    except:
        # Original main's named values remain owned by its saved traceback.
        _saved_scope = scope
        raise
    finally:
        scope = None


if __name__ == "__main__":
    raise SystemExit(main())
