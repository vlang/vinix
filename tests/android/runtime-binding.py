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
else:
    spec = importlib.util.spec_from_file_location("android_runtime",
        ROOT / "build-support/android" / ("musl-runtime.py" if module == "musl" else "art-runtime.py"))
    art = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(art)
for name, path in request.get("overrides", {}).items():
    setattr(art, name, Path(path))
try:
    if "attributes" in request:
        result = {name: getattr(art, name) for name in request["attributes"]}
    else:
        result = getattr(art, request["operation"])(
            *[Path(path) for path in request.get("paths", [])], *request.get("values", []))
    print(json.dumps({"result": result}, default=lambda value:
                     str(value) if isinstance(value, Path) else sorted(value)))
except BaseException as error:
    print(json.dumps({"kind": type(error).__name__, "message": str(error),
                      "errno": getattr(error, "errno", None)}))
