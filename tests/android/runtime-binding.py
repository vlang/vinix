#!/usr/bin/env python3
"""Synchronous standard-library binding to the public Android runtime API."""
import importlib.util
import json
from pathlib import Path
import sys

request = json.loads(sys.argv[1])
ROOT = Path(__file__).resolve().parents[2]
module = request.get("module", "art")
if module == "shutil":
    import shutil as art
elif module == "zip":
    import zipfile as art
else:
    filename = {"musl": "musl-runtime.py", "boot": "art-bootclasspath.py"}.get(module, "art-runtime.py")
    spec = importlib.util.spec_from_file_location("android_runtime",
        ROOT / "build-support/android" / filename)
    art = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(art)
for name, path in request.get("overrides", {}).items():
    setattr(art, name, Path(path))
try:
    calls = []
    if module == "zip":
        import zipfile
        if request["operation"] == "write":
            with zipfile.ZipFile(request["path"], "w") as archive:
                for name, contents in request["entries"]:
                    archive.writestr(name, bytes.fromhex(contents))
            result = None
        else:
            with zipfile.ZipFile(request["path"]) as archive:
                result = {"names": archive.namelist(), "files": {
                    name: archive.read(name).hex() for name in request["names"]}}
    elif "attributes" in request:
        result = {name: getattr(art, name) for name in request["attributes"]}
    else:
        arguments = [Path(path) for path in request.get("paths", [])] + request.get("values", [])
        if "arguments" in request:
            conversions = {"path": Path, "bytes": bytes.fromhex, "set": set, "json": json.loads,
                           "value": lambda value: value}
            arguments = [conversions[kind](value) for kind, value in request["arguments"]]
        if request.get("record_run"):
            from unittest.mock import patch
            with patch.object(art.subprocess, "run") as run:
                try:
                    result = getattr(art, request["operation"])(*arguments)
                finally:
                    calls = run.call_args_list
        else:
            result = getattr(art, request["operation"])(*arguments)
    print(json.dumps({"result": result, "run_calls": len(calls)}, default=lambda value:
                     str(value) if isinstance(value, Path) else sorted(value)))
except BaseException as error:
    print(json.dumps({"kind": type(error).__name__, "message": str(error),
                      "errno": getattr(error, "errno", None), "run_calls": len(calls)}))
