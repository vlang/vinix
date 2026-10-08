#!/usr/bin/env python3
"""Synchronous standard-library binding to the public Android runtime API."""
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("art_runtime", ROOT / "build-support/android/art-runtime.py")
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)
request = json.loads(sys.argv[1])
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
