# SPDX-License-Identifier: GPL-2.0-or-later
"""Synchronous imported API and exception transport for the native stager."""
import atexit
import dataclasses
import importlib.util
import json
import os
import operator
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
_LOCK = threading.RLock()
_BINARY = None

class ArgumentError(ValueError):
    pass


def _failure(failure, errors):
    if "binding_error" in failure:
        return errors[failure["binding_error"]]
    kind = failure["kind"]
    if kind == "OSError":
        args = [failure["errno"], os.strerror(failure["errno"])]
        if failure.get("filename"):
            args.append(os.fsdecode(bytes.fromhex(failure["filename"])))
        if "filename2" in failure:
            if len(args) == 2:
                args.append(None)
            args += [None, os.fsdecode(bytes.fromhex(failure["filename2"]))]
        return OSError(*args)
    if kind == "CopyError":
        return shutil.Error([(os.fsdecode(bytes.fromhex(source)), os.fsdecode(bytes.fromhex(target)), message)
                            for source, target, message in failure["entries"]])
    if kind == "UnicodeDecodeError":
        return UnicodeDecodeError("utf-8", bytes.fromhex(failure["data"]), failure["start"], failure["end"], failure["reason"])
    if kind == "StopIteration":
        return StopIteration()
    return {"SystemExit": SystemExit, "ArgumentError": ArgumentError,
           "ValueError": ValueError, "RuntimeError": RuntimeError,
           "StopIteration": StopIteration, "AttributeError": AttributeError}[kind](failure["message"])

def query(operation, arguments, namespace):
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            override = os.environ.get("VINIX_DOTA_VULKAN_QUERY")
            if override:
                _BINARY = override
            else:
                directory = Path(tempfile.mkdtemp(prefix="vinix-vulkan-controller-"))
                try:
                    binary = directory / "query"
                    with tempfile.TemporaryDirectory(prefix="vinix-vulkan-compiler-", dir="/tmp") as scratch:
                        subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                                        str(ROOT / "build-support/dota2/vulkan_query.v"),
                                        "--install-query", str(binary)], check=True,
                                       stdout=subprocess.DEVNULL, env={**os.environ, "TMPDIR": scratch})
                except BaseException:
                    shutil.rmtree(directory)
                    raise
                atexit.register(shutil.rmtree, directory)
                _BINARY = str(binary)
        objects, errors, owners = [], [], {}

        def encode(value):
            if isinstance(value, Path):
                return {"path_hex": os.fsencode(value).hex()}
            if isinstance(value, str) and any(0xd800 <= ord(ch) <= 0xdfff for ch in value):
                return {"surrogate_text": value.encode("utf-8", "surrogatepass").hex()}
            if isinstance(value, bool):
                return value
            if isinstance(value, int):
                return {"integer": str(value)}
            if isinstance(value, float):
                return {"float": repr(value)}
            if dataclasses.is_dataclass(value):
                objects.append(value)
                return {"object": len(objects) - 1, "fields": encode(vars(value))}
            if isinstance(value, (tuple, list)):
                return [encode(item) for item in value]
            if isinstance(value, dict):
                if set(value) in ({"path_hex"}, {"object"}, {"object", "fields"}, {"integer"},
                                  {"float"}, {"tuple"}, {"set"}, {"mapping"}, {"dictionary"},
                                  {"filesystem_text"}, {"filesystem_map"}, {"surrogate_text"}):
                    return {"dictionary": {key: encode(item) for key, item in value.items()}}
                if any(not isinstance(key, str) or any(0xd800 <= ord(ch) <= 0xdfff for ch in key) for key in value):
                    return {"mapping": [[encode(key), encode(item)] for key, item in value.items()]}
                return {key: encode(item) for key, item in value.items()}
            if value is None or isinstance(value, (str, bool, int, float)):
                return value
            objects.append(value)
            return {"object": len(objects) - 1}

        def decode(value, borrowed=True):
            if isinstance(value, list):
                return [decode(item, borrowed) for item in value]
            if isinstance(value, dict):
                if set(value) == {"filesystem_text"}:
                    return os.fsdecode(bytes.fromhex(value["filesystem_text"]))
                if set(value) == {"surrogate_text"}:
                    return bytes.fromhex(value["surrogate_text"]).decode("utf-8", "surrogatepass")
                if set(value) == {"filesystem_map"}:
                    return {os.fsdecode(bytes.fromhex(key)): decode(item, borrowed) for key, item in value["filesystem_map"]}
                if set(value) == {"dictionary"}:
                    return {key: decode(item, borrowed) for key, item in value["dictionary"].items()}
                if set(value) == {"integer"}:
                    return int(value["integer"])
                if set(value) == {"float"}:
                    return float(value["float"])
                if set(value) == {"mapping"}:
                    return {decode(key, borrowed): decode(item, borrowed) for key, item in value["mapping"]}
                if set(value) == {"tuple"}:
                    return tuple(decode(item, borrowed) for item in value["tuple"])
                if set(value) == {"set"}:
                    return set(decode(item, borrowed) for item in value["set"])
                if borrowed and set(value) == {"path_hex"}:
                    return Path(os.fsdecode(bytes.fromhex(value["path_hex"])))
                if borrowed and set(value) in ({"object"}, {"object", "fields"}):
                    return objects[value["object"]]
                return {key: decode(item, borrowed) for key, item in value.items()}
            return value

        def primitive(row):
            kind = row["kind"]
            values = decode(row.get("arguments", []))
            keywords = decode(row.get("keywords", {}))
            if kind == "public":
                return namespace[row["name"]](*values, **keywords)
            if kind == "global":
                if "key" in row:
                    return namespace[row["name"]][row["key"]]
                if row["name"] not in namespace:
                    return namespace["__getattr__"](row["name"])
                return namespace[row["name"]]
            if kind == "method":
                return getattr(decode(row["target"]), row["name"])(*values, **keywords)
            if kind == "call":
                return decode(row["target"])(*values, **keywords)
            if kind == "attribute":
                return getattr(decode(row["target"]), row["name"])
            if kind == "keys":
                return list(decode(row["target"]))
            if kind == "resolver":
                spec = importlib.util.spec_from_file_location("vinix_debian_root", ROOT / "build-support/debian-root.py")
                result = importlib.util.module_from_spec(spec)
                sys.modules[spec.name] = result
                spec.loader.exec_module(result)
                return result
            if kind == "run":
                return namespace["subprocess"].run(*values, **keywords)
            if kind == "check_output":
                return namespace["subprocess"].check_output(*values, **keywords)
            if kind == "json_loads":
                return json.loads(bytes.fromhex(row["data_hex"]).decode())
            if kind == "json_dumps":
                return json.dumps(*values, **keywords)
            if kind == "equal":
                return operator.eq(*values)
            if kind == "symlink":
                return values[1].symlink_to(values[0])
            if kind == "copy2":
                return namespace["shutil"].copy2(*values)
            if kind == "temporary":
                owner = tempfile.TemporaryDirectory(**keywords)
                entered = owner.__enter__()
                owners[id(owner)] = owner
                return {"owner": owner, "entered": entered}
            if kind == "retire":
                owner = owners.pop(id(values[0]))
                context = row.get("context")
                if context is None:
                    return bool(owner.__exit__(None, None, None))
                try:
                    raise _failure(context, errors)
                except BaseException:
                    return bool(owner.__exit__(*sys.exc_info()))
            if kind == "context_exit":
                manager = decode(row["target"])
                context = row.get("context")
                if context is None:
                    manager.__exit__(None, None, None)
                    return False
                try:
                    raise _failure(context, errors)
                except BaseException:
                    return bool(manager.__exit__(*sys.exc_info()))
            if kind == "print":
                print(*values, **keywords)
                return None
            raise RuntimeError("unknown Vulkan primitive: " + kind)

        child = subprocess.Popen([_BINARY], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 text=True, env=os.environ, restore_signals=False)
        try:
            metadata = {"operation": operation, "arguments": encode(arguments),
                        "repo_hex": os.fsencode(namespace["REPO"]).hex(),
                        "builder_hex": os.fsencode(namespace["__file__"]).hex(),
                        "python_hex": os.fsencode(sys.executable).hex(),
                        "platform": namespace["sys"].platform, "pid": os.getpid()}
            child.stdin.write(json.dumps(metadata) + "\n")
            child.stdin.flush()
            while True:
                line = child.stdout.readline()
                if not line:
                    child.wait()
                    raise RuntimeError("native Vulkan stager ended before returning a result")
                row = json.loads(line)
                if "callback" not in row:
                    if "error" in row:
                        failure = row["error"]
                        raise _failure(failure, errors)
                    # Public results contain data; only synchronous callbacks
                    # may borrow importer-owned Paths or API objects.
                    return decode(row["value"], borrowed=False)
                try:
                    reply = {"value": encode(primitive(row["callback"]))}
                except BaseException as error:
                    errors.append(error)
                    reply = {"error": {"binding_error": len(errors) - 1}}
                child.stdin.write(json.dumps(reply) + "\n")
                child.stdin.flush()
        finally:
            main_thread = threading.current_thread() is threading.main_thread()
            previous = signal.signal(signal.SIGINT, signal.SIG_IGN) if main_thread else None
            try:
                try:
                    try:
                        child.stdin.close()
                    finally:
                        try:
                            child.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            child.kill(); child.wait()
                        except BaseException:
                            child.kill(); child.wait(); raise
                finally:
                    try:
                        child.stdout.close()
                    finally:
                        for owner in owners.values():
                            owner.__exit__(*sys.exc_info())
            finally:
                if main_thread:
                    signal.signal(signal.SIGINT, previous)
