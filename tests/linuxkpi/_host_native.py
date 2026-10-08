# SPDX-License-Identifier: GPL-2.0-or-later
"""Temporary import, file-byte and exception transport for native host producers."""
import atexit
import json
import os
import platform
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
_LOCK = threading.Lock()
_BINARY = None


def request(operation, **fields):
    global _BINARY
    with _LOCK:
        if _BINARY is None:
            override = os.environ.get("VINIX_LINUXKPI_HOST_QUERY")
            if override:
                _BINARY = Path(override)
            else:
                directory = Path(tempfile.mkdtemp(prefix="vinix-host-producer-"))
                try:
                    binary = directory / "query"
                    subprocess.run([str(ROOT / "build-support/run-v-tool.sh"),
                                    str(ROOT / "tests/linuxkpi/host_query.v"),
                                    "--install-query", str(binary)], check=True,
                                   stdout=subprocess.DEVNULL)
                except BaseException:
                    shutil.rmtree(directory)
                    raise
                atexit.register(shutil.rmtree, directory)
                _BINARY = binary
    if (operation == "generate" and fields.get("shared_model")) or operation == "namespace":
        # Bind the stdlib replacement-template primitive. V applies the tokens
        # to its own Unicode/module selection after source staging and reads.
        replacement = "module " + (fields["name"] if operation == "namespace" else fields["source"].name)
        try:
            parser = getattr(re, "_parser", None)
            if parser is None:
                import sre_parse as parser
            groups, literals = parser.parse_template(replacement, re.compile(r"^module \w+$", re.M))
            fields["template"] = [{"whole": True} if text is None else {"literal": text} for text in literals]
        except (re.error, IndexError) as error:
            fields["template_error"] = {"type": type(error).__name__, "message": str(error),
                "msg": getattr(error, "msg", None), "pattern": getattr(error, "pattern", None), "pos": getattr(error, "pos", None)}
    for name in ("source", "output"):
        if name in fields:
            fields[name + "_hex"] = os.fsencode(fields.pop(name)).hex()
    fields["host_arch"] = platform.machine()
    if operation == "suite":
        fields["environment_hex"] = subprocess.check_output(["/usr/bin/env", "-0"]).hex()
    with tempfile.TemporaryDirectory(prefix="vinix-host-response-") as directory:
        result = Path(directory) / "result.json"
        subprocess.run([str(_BINARY), "--request", str(result), json.dumps({"operation": operation, **fields})],
                       check=True, restore_signals=False)
        value = json.loads(result.read_text())
    if "error" in value:
        if value.get("kind") == "TemplateError":
            if value["type"] == "IndexError":
                raise IndexError(value["message"])
            raise re.error(value["msg"], value["pattern"], value["pos"])
        if value.get("kind") == "CalledProcessError":
            sys.stdout.write(value["stdout"]); sys.stderr.write(value["stderr"])
            raise subprocess.CalledProcessError(value["returncode"], value["argv"], output=value.get("output"))
        if value.get("kind") == "CopyError":
            raise shutil.Error([tuple(entry) for entry in value["entries"]])
        if value.get("kind") == "UnicodeDecodeError":
            raise UnicodeDecodeError("utf-8", bytes.fromhex(value["data"]), value["start"], value["end"], value["reason"])
        if value.get("errno"):
            filename = os.fsdecode(bytes.fromhex(value.get("filename_hex", ""))) or None
            if filename is None:
                raise OSError(value["errno"], os.strerror(value["errno"]))
            raise OSError(value["errno"], os.strerror(value["errno"]), filename)
        raise {"RuntimeError": RuntimeError, "FileNotFoundError": FileNotFoundError}.get(value.get("kind"), ValueError)(value["error"])
    sys.stdout.write(value.get("stdout", "")); sys.stderr.write(value.get("stderr", ""))
    return value["value"]
