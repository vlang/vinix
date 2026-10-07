"""Synchronous import bridge for the native V image-extraction library.

Input bytes are borrowed for one call. JSON and binary results have separate
libc ownership; both are copied to Python and released exactly once.
"""
from __future__ import annotations
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import threading

_DIRECTORY = Path(__file__).resolve().parent
_LIBRARY = None
_LOCK = threading.Lock()
_LOAD_OWNER = None


def _load(target):
    global _LOAD_OWNER
    if threading.current_thread() is threading.main_thread():
        return ctypes.CDLL(str(target))
    # Boehm's constructor treats the loading thread as its initial thread.
    # Give that thread the library's process lifetime even if the importing
    # worker exits. It receives no query input and retains no query result.
    ready = threading.Event()
    lifetime = threading.Event()
    result = []
    failures = []

    def owner():
        try:
            result.append(ctypes.CDLL(str(target)))
        except BaseException as error:
            failures.append(error)
        finally:
            ready.set()
        if result:
            lifetime.wait()

    thread = threading.Thread(target=owner, name="vinix-agx-extract-owner", daemon=True)
    thread.start()
    ready.wait()
    if failures:
        raise failures[0]
    _LOAD_OWNER = (thread, lifetime)
    return result[0]


def _library():
    global _LIBRARY
    with _LOCK:
        if _LIBRARY is not None:
            return _LIBRARY
        override = os.environ.get("VINIX_AGX_EXTRACT_LIBRARY")
        if override:
            target = Path(override)
        else:
            finder = _DIRECTORY.parent.parent / "build-support/find-v.sh"
            compiler = subprocess.check_output(
                ["sh", "-c", '. "$1"; printf "%s" "$V"', "sh", str(finder)],
                text=True,
            )
            architecture = "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "amd64"
            digest = hashlib.sha256(Path(compiler).read_bytes())
            digest.update(architecture.encode())
            compiler_root = Path(compiler).resolve().parent
            for command in (["git", "-C", str(compiler_root), "rev-parse", "HEAD"],
                            ["git", "-C", str(compiler_root), "diff", "HEAD", "--", "vlib", "thirdparty/libgc"]):
                snapshot = subprocess.run(command, capture_output=True)
                if snapshot.returncode == 0:
                    digest.update(snapshot.stdout)
            for folder in ("imageextract", "extractionabi", "traceanalysis", "g17decode", "g17power"):
                for source in sorted((_DIRECTORY / folder).glob("*.v")):
                    if not source.name.endswith("_test.v"):
                        digest.update(source.name.encode())
                        digest.update(source.read_bytes())
            suffix = ".dylib" if platform.system() == "Darwin" else ".so"
            cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "vinix/agx-extract"
            cache.mkdir(parents=True, exist_ok=True)
            target = cache / (digest.hexdigest() + suffix)
            if not target.is_file():
                with tempfile.TemporaryDirectory(prefix="compile-", dir=cache) as temporary:
                    built = Path(temporary) / ("extraction" + suffix)
                    subprocess.run(
                        [compiler, "-enable-globals", "-gc", "boehm", "-cc", "clang", "-arch", architecture,
                         "-shared", "-o", str(built), str(_DIRECTORY / "extractionabi")],
                        check=True, cwd=_DIRECTORY,
                    )
                    os.replace(built, target)
        library = _load(target)
        library.vinix_agx_extract_query.argtypes = (
            ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_char_p,
        )
        library.vinix_agx_extract_query.restype = ctypes.c_void_p
        library.vinix_agx_extract_release.argtypes = (ctypes.c_void_p,)
        library.vinix_agx_extract_release.restype = None
        _LIBRARY = library
        return library


def query(data: bytes | bytearray, operation: str, **options):
    library = _library()
    # These owners live until the native call returns; no native pointer escapes.
    owner = (ctypes.c_ubyte * len(data)).from_buffer(data) if isinstance(data, bytearray) else ctypes.c_char_p(data)
    pointer = library.vinix_agx_extract_query(
        owner, len(data), operation.encode(), json.dumps(options).encode(),
    )
    if not pointer:
        raise MemoryError("cannot allocate native extraction response")
    try:
        response = json.loads(ctypes.string_at(pointer))
    finally:
        library.vinix_agx_extract_release(pointer)
    if "error" in response:
        raise ValueError(response["error"])
    result = response["result"]
    if isinstance(result, dict) and "pointer" in result:
        binary = result.pop("pointer")
        try:
            result["data"] = ctypes.string_at(binary, result.pop("bytes"))
        finally:
            library.vinix_agx_extract_release(binary)
    return result


def span(data, result):
    return data[result["start"]:result["end"]]


def main(name: str) -> int:
    import sys
    return subprocess.call([str(_DIRECTORY / name), *sys.argv[1:]])
