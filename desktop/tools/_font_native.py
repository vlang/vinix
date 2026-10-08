"""Python import/exception transport and Pillow/fontTools library bindings."""
import atexit
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import urllib.request
import weakref

from PIL import ImageFont

_HERE = Path(__file__).resolve().parent
_LOCK = threading.RLock()
_PROCESS = None
_DIRECTORY = None
_FONTS = {}
_IDS = {}
_OWNERS = {}
_STRONG = {}
_NEXT_ID = 0
_TT = {}
_NEXT_TT_ID = 0
_ERRORS = {}
_NEXT_ERROR_ID = 0
_MASKS = {}
_NEXT_MASK_ID = 0


def _register(font, owner):
    global _NEXT_ID
    key = id(font)
    if key not in _IDS:
        _NEXT_ID += 1
        ident = _NEXT_ID
        _IDS[key] = ident
        try:
            def expired(reference, key=key, ident=ident):
                _FONTS.pop(ident, None)
                if _IDS.get(key) == ident:
                    _IDS.pop(key)
            _FONTS[ident] = weakref.ref(font, expired)
        except TypeError:
            _FONTS[ident] = None
    ident = _IDS[key]
    _OWNERS.setdefault(ident, set()).add(owner)
    _STRONG[ident] = font
    return ident


def _lookup(ident):
    if ident in _STRONG:
        return _STRONG[ident]
    return _FONTS[ident]()


def _release(ident, owner):
    owners = _OWNERS.get(ident)
    if owners is None:
        return
    owners.discard(owner)
    if not owners:
        font = _STRONG.pop(ident)
        _OWNERS.pop(ident)
        if _FONTS[ident] is None:
            _FONTS.pop(ident)
            _IDS.pop(id(font))


def call_font(operation, font, arguments, context):
    with _LOCK:
        ident = _register(font, "borrow")
        try:
            return call(operation, dict(arguments, font=ident), context)
        finally:
            _release(ident, "borrow")


def _close():
    global _PROCESS, _DIRECTORY
    process, directory = _PROCESS, _DIRECTORY
    _PROCESS = None
    _DIRECTORY = None
    try:
        if process is not None:
            try:
                process.stdin.close()
            except BaseException:
                pass
            try:
                process.wait(timeout=5)
            except BaseException:
                try:
                    process.kill()
                except OSError:
                    pass
                process.wait()
            finally:
                process.stdout.close()
    finally:
        try:
            for ident, owners in list(_OWNERS.items()):
                for owner in tuple(owners - {"borrow"}):
                    _release(ident, owner)
        finally:
            try:
                _ERRORS.clear()
                _MASKS.clear()
                for ident in list(_TT):
                    font = _TT.pop(ident)
                    try:
                        font.close()
                    except BaseException:
                        pass
            finally:
                if directory is not None:
                    shutil.rmtree(directory)


atexit.register(_close)


def _start():
    global _PROCESS, _DIRECTORY
    if _PROCESS is not None:
        return
    binary = os.environ.get("VINIX_FONT_CONTROLLER")
    if binary is None:
        _DIRECTORY = tempfile.mkdtemp(prefix="vinix-font-controller-")
        binary = str(Path(_DIRECTORY) / "controller")
        try:
            subprocess.run([str(_HERE.parents[1] / "build-support/run-v-tool.sh"),
                            str(_HERE / "font_query.v"), "--install-controller", binary],
                           check=True, stdout=subprocess.DEVNULL, env=os.environ)
        except BaseException:
            _close()
            raise
    try:
        _PROCESS = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    text=True, encoding="utf-8", env=os.environ)
    except BaseException:
        _close()
        raise


def _error(error):
    global _NEXT_ERROR_ID
    _NEXT_ERROR_ID += 1
    _ERRORS[_NEXT_ERROR_ID] = error
    return {"binding_error": _NEXT_ERROR_ID, "kind": type(error).__name__, "message": str(error)}


def _raise(row):
    if "binding_error" in row:
        raise _ERRORS.pop(row["binding_error"])
    kind = row["kind"]
    if kind == "OSError":
        if row["errno"] is None:
            raise OSError(row["message"])
        filename = row["filename"]
        if filename is None:
            raise OSError(row["errno"], os.strerror(row["errno"]))
        raise OSError(row["errno"], os.strerror(row["errno"]), os.fsdecode(bytes.fromhex(filename)))
    if kind == "UnicodeDecodeError":
        raise UnicodeDecodeError("utf-8", bytes.fromhex(row["data"]), row["start"], row["end"], row["reason"])
    kinds = {"SystemExit": SystemExit, "ValueError": ValueError, "RuntimeError": RuntimeError,
             "ImportError": ImportError, "TypeError": TypeError, "KeyError": KeyError,
             "IndexError": IndexError, "OverflowError": OverflowError,
             "KeyboardInterrupt": KeyboardInterrupt}
    raise kinds[kind](row["message"])


def _library(operation, row):
    if operation == "print":
        print(row["text"], flush=True)
        return None
    if operation == "fetch":
        with urllib.request.urlopen(row["url"], timeout=row["timeout"]) as response:
            return response.read().hex()
    if operation == "open":
        return _register(ImageFont.truetype(os.fsdecode(bytes.fromhex(row["path"])), row["size"]), row["owner"])
    if operation == "pin":
        _register(_lookup(row["font"]), row["owner"])
        return None
    if operation == "release":
        for ident in row["fonts"]:
            _release(ident, row["owner"])
        return None
    if operation == "bbox":
        return _lookup(row["font"]).getbbox(chr(row["code_point"]))
    if operation == "mask":
        global _NEXT_MASK_ID
        mask = _lookup(row["font"]).getmask(chr(row["code_point"]), mode="L")
        width, height = mask.size
        _NEXT_MASK_ID += 1
        _MASKS[_NEXT_MASK_ID] = mask
        return {"width": width, "height": height, "mask": _NEXT_MASK_ID}
    if operation == "pixels":
        return bytes(_MASKS[row["mask"]]).hex()
    if operation == "mask_release":
        _MASKS.pop(row["mask"])
        return None
    if operation == "length":
        return _length_wire(_lookup(row["font"]).getlength(chr(row["code_point"])))
    if operation == "metrics":
        return _lookup(row["font"]).getmetrics()
    if operation == "fonttools_import":
        global _subset, _TTFont, _instantiate
        try:
            from fontTools import subset as _subset
            from fontTools.ttLib import TTFont as _TTFont
            from fontTools.varLib.instancer import instantiateVariableFont as _instantiate
        except ImportError:
            raise SystemExit("subset regeneration needs fontTools; see desktop/fonts/README.md")
        return None
    if operation == "tt_open":
        global _NEXT_TT_ID
        font = _TTFont(io.BytesIO(bytes.fromhex(row["data"])), recalcTimestamp=row["recalc_timestamp"])
        _NEXT_TT_ID += 1
        key = _NEXT_TT_ID
        _TT[key] = font
        return key
    if operation == "tt_close":
        font = _TT.pop(row["font"])
        try:
            font.close()
        except BaseException:
            pass
        return None
    if operation == "tt_cmap":
        return list(_TT[row["font"]].getBestCmap())
    if operation == "tt_subset":
        options = _subset.Options()
        options.name_IDs += row["name_ids"]
        options.layout_features = row["layout_features"]
        subsetter = _subset.Subsetter(options=options)
        subsetter.populate(unicodes=row["runes"])
        subsetter.subset(_TT[row["font"]])
        return None
    if operation == "tt_instantiate":
        font = _instantiate(_TT[row["font"]], {"wght": row["weight"]}, inplace=row["inplace"])
        _NEXT_TT_ID += 1
        key = _NEXT_TT_ID
        _TT[key] = font
        return key
    if operation == "tt_records":
        return [[r.nameID, r.platformID, r.platEncID, r.langID] for r in _TT[row["font"]]["name"].names]
    if operation == "tt_set_name":
        _TT[row["font"]]["name"].setName(row["name"], *row["record"])
        return None
    if operation == "tt_save":
        _TT[row["font"]].save(os.fsdecode(bytes.fromhex(row["path"])))
        return None
    raise RuntimeError("unknown library callback: " + operation)


def _length_wire(value):
    return {"integer": str(value)} if isinstance(value, int) else {"float": repr(value)}


def call(operation, arguments=None, context=None):
    with _LOCK:
        _start()
        row = {"operation": operation, "arguments": arguments or {}, "context": context or {}}
        try:
            _PROCESS.stdin.write(json.dumps(row) + "\n")
            _PROCESS.stdin.flush()
            while True:
                line = _PROCESS.stdout.readline()
                if not line:
                    _close()
                    raise RuntimeError("native font controller ended before returning a result")
                result = json.loads(line)
                if "callback" not in result:
                    if "error" in result:
                        _raise(result["error"])
                    return result["value"]
                try:
                    value = {"value": _library(result["callback"], result["arguments"])}
                except BaseException as error:
                    value = {"error": _error(error)}
                _PROCESS.stdin.write(json.dumps(value) + "\n")
                _PROCESS.stdin.flush()
        except (BrokenPipeError, json.JSONDecodeError):
            _close()
            raise
        finally:
            _ERRORS.clear()
            _MASKS.clear()
