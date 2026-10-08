#!/usr/bin/env python3
"""Synchronous standard-library binding to the public Android runtime API."""
import importlib.util
import json
from pathlib import Path
import sys


def _module(filename):
    specification = importlib.util.spec_from_file_location("android_binding_api", ROOT / "build-support/android" / filename)
    result = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(result)
    return result


def _binding(descriptor):
    kind = descriptor["kind"]
    if kind == "namespace":
        from types import SimpleNamespace
        return SimpleNamespace(**{name: _binding(value) for name, value in descriptor["attributes"].items()})
    if kind == "return":
        value = _binding(descriptor["value"])
        return lambda *args, **kwargs: value
    if kind == "value":
        return descriptor["value"]
    if kind == "public":
        target = getattr(_module(descriptor["module"]), descriptor["operation"])
        return lambda *args, **kwargs: target(*args, **kwargs, **descriptor.get("keywords", {}))
    if kind == "callback":
        def invoke(*args, **kwargs):
            import subprocess
            row = {"operation": descriptor["operation"], "arguments": args,
                   "keywords": kwargs, "context": descriptor.get("context", {})}
            result = _original_run([request["callback_binary"], "--atl-binding", json.dumps(row, default=str)],
                                   check=True, text=True, capture_output=True)
            response = json.loads(result.stdout)
            if descriptor.get("completed") and response is not None:
                return subprocess.CompletedProcess(args[0], 0, stdout=response)
            return response
        return invoke
    raise RuntimeError("unknown runtime binding kind " + kind)

request = json.loads(sys.argv[1])
ROOT = Path(__file__).resolve().parents[2]
module = request.get("module", "art")
if module == "shutil":
    import shutil as art
elif module == "zip":
    import zipfile as art
else:
    filename = {"musl": "musl-runtime.py", "boot": "art-bootclasspath.py", "builder": "build.py"}.get(module, "art-runtime.py")
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
            from argparse import Namespace
            conversions = {"path": Path, "bytes": bytes.fromhex, "set": set, "json": json.loads,
                           "namespace": lambda value: Namespace(**{name: Path(item) if kind == "path" else item
                                                                     for name, (kind, item) in value.items()}),
                           "value": lambda value: value}
            arguments = [conversions[kind](value) for kind, value in request["arguments"]]
        if request.get("patches"):
            import contextlib
            import io
            import subprocess
            from unittest.mock import patch
            _original_run = subprocess.run
            output = io.StringIO()
            with contextlib.ExitStack() as stack:
                for name, descriptor in request["patches"]:
                    target = art
                    parts = name.split(".")
                    for part in parts[:-1]:
                        target = getattr(target, part)
                    stack.enter_context(patch.object(target, parts[-1], _binding(descriptor)))
                with contextlib.redirect_stdout(output):
                    result = getattr(art, request["operation"])(*arguments)
            calls = []
            if request.get("record_patch"):
                calls = [json.loads(line) for line in Path(request["record_patch"]).read_text().splitlines()]
        elif request.get("record_run"):
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
