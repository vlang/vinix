"""Synchronous stdlib archive/filesystem bindings for the V boot controller."""
import atexit
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading

_HERE = Path(__file__).resolve().parent
_LOCK = threading.RLock()
_BINARY = None


def _register(resources, value):
    ident = resources.get("next_id", 0) + 1
    resources["next_id"] = ident
    resources[ident] = value
    return ident


def _binary():
    global _BINARY
    if _BINARY is None:
        override = os.environ.get("VINIX_ANDROID_BOOT_QUERY")
        if override:
            _BINARY = override
        else:
            directory = tempfile.mkdtemp(prefix="vinix-art-boot-controller-")
            try:
                binary = str(Path(directory) / "query")
                subprocess.run([str(_HERE.parent / "run-v-tool.sh"),
                                str(_HERE / "boot-query.v"), "--install-query", binary],
                               check=True, stdout=subprocess.DEVNULL, env=os.environ)
            except BaseException:
                shutil.rmtree(directory)
                raise
            atexit.register(shutil.rmtree, directory)
            _BINARY = binary
    return _BINARY


def _primitive(operation, row, context, resources):
    path = Path(row["path"]) if "path" in row else None
    if operation == "path":
        method = row["method"]
        if method in ("name", "parent", "parts", "suffix"):
            value = getattr(path, method)
            return list(value) if method == "parts" else str(value)
        arguments = row.get("arguments", [])
        if method == "unlink" and resources.get("temporary") == str(path):
            resources.pop("temporary")
        value = getattr(path, method)(*arguments, **row.get("options", {}))
        return str(value) if isinstance(value, Path) else value
    if operation == "join":
        return str(Path(row["parent"]) / row["child"])
    if operation == "read_bytes":
        return path.read_bytes().hex()
    if operation == "write_bytes":
        return path.write_bytes(bytes.fromhex(row["data"]))
    if operation == "read_text":
        return path.read_text()
    if operation == "print":
        print(row["data"])
        return None
    if operation == "write_text":
        return path.write_text(row["data"])
    if operation == "stat":
        return path.stat().st_size
    if operation == "rmtree":
        return context["shutil"].rmtree(path)
    if operation == "replace":
        return context["os"].replace(path, Path(row["destination"]))
    if operation == "json_loads":
        return context["json"].loads(row["data"])
    if operation == "json_dumps":
        return context["json"].dumps(row["data"], **row.get("options", {}))
    if operation == "run":
        context["subprocess"].run(row["arguments"], check=True)
        return None
    if operation == "capture":
        return context["subprocess"].check_output(row["arguments"], text=True)
    if operation == "tar_open":
        archive = context["tarfile"].open(path, "r:gz", ignore_zeros=True)
        return _register(resources, (archive, iter(archive)))
    if operation == "tar_next":
        archive, iterator = resources[row["id"]]
        member = next(iterator, None)
        if member is None:
            return None
        resources["member"] = member
        return {"name": member.name, "regular": member.isfile()}
    if operation == "tar_copy":
        archive, _ = resources[row["id"]]
        contents = archive.extractfile(resources["member"])
        if contents is None:
            return False
        with contents, path.open("wb") as target:
            context["shutil"].copyfileobj(contents, target)
        return True
    if operation == "zip_open":
        archive = context["zipfile"].ZipFile(path, row.get("mode", "r"),
                                            compression=row.get("compression", 0))
        return _register(resources, archive)
    if operation == "zip_names":
        return resources[row["id"]].namelist()
    if operation == "zip_read":
        return resources[row["id"]].read(row["name"]).hex()
    if operation == "zip_write":
        name = row["name"]
        if row.get("deterministic"):
            name = context["zipfile"].ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            name.compress_type = context["zipfile"].ZIP_DEFLATED
            name.external_attr = 0o644 << 16
        return resources[row["id"]].writestr(name, bytes.fromhex(row["data"]))
    if operation == "zip_file":
        return resources[row["id"]].write(path, row["name"])
    if operation == "close":
        resource = resources.pop(row["id"])
        return (resource[0] if isinstance(resource, tuple) else resource).close()
    if operation in ("glob", "rglob"):
        return [str(item) for item in getattr(path, operation)(row["pattern"])]
    if operation == "temporary_copy":
        with context["tempfile"].NamedTemporaryFile(prefix=row["prefix"], dir=path, delete=False) as output:
            temporary = str(output.name)
            resources["temporary"] = temporary
            with Path(row["source"]).open("rb") as source:
                context["shutil"].copyfileobj(source, output)
        return temporary
    if operation == "art_import":
        specification = context["importlib"].util.spec_from_file_location("art_runtime", path)
        art = context["importlib"].util.module_from_spec(specification)
        assert specification.loader is not None
        specification.loader.exec_module(art)
        resources["art"] = art
        return art.MANIFEST
    if operation == "art_read":
        return resources["art"].read_manifest(path)
    if operation == "art_inside":
        art = resources["art"]
        return str(art._inside(path, art._relative(row["name"])))
    raise RuntimeError("unknown bootclasspath primitive " + operation)


def call(operation, arguments, context):
    with _LOCK:
        resources, errors = {}, {}
        constants = {} if operation == "constants" else context["_boot_constants"]()
        with subprocess.Popen([_binary()], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              text=True, encoding="utf-8", env=os.environ) as process:
            try:
                request = {"operation": operation, "arguments": arguments, "constants": constants,
                           "source": context["__file__"], "support": str(context["SUPPORT"])}
                process.stdin.write(json.dumps(_pack(request)) + "\n")
                process.stdin.flush()
                while True:
                    line = process.stdout.readline()
                    if not line:
                        raise RuntimeError("native bootclasspath controller ended before returning a result")
                    row = _unpack(json.loads(line))
                    if "callback" not in row:
                        if "error" in row:
                            error = row["error"]
                            if "binding_error" in error:
                                raise errors[error["binding_error"]]
                            if "message" not in error:
                                context["_native"]._response(error)
                            failure = {"RuntimeError": RuntimeError, "KeyError": KeyError,
                                       "TypeError": TypeError, "ValueError": ValueError}[error["kind"]](error["message"])
                            if "cause" in error:
                                cause = error["cause"]
                                if "binding_error" in cause:
                                    raise failure from errors[cause["binding_error"]]
                                try:
                                    context["_native"]._response(cause)
                                except BaseException as cause_error:
                                    raise failure from cause_error
                            raise failure
                        return row["value"]
                    try:
                        response = {"value": _primitive(row["callback"], row["arguments"], context, resources)}
                    except BaseException as error:
                        ident = len(errors) + 1
                        errors[ident] = error
                        response = {"error": {"binding_error": ident, "kind": type(error).__name__, "message": str(error)}}
                    process.stdin.write(json.dumps(_pack(response)) + "\n")
                    process.stdin.flush()
            finally:
                try:
                    try:
                        process.stdin.close()
                    finally:
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                        except BaseException:
                            try:
                                process.kill()
                            except OSError:
                                pass
                            process.wait()
                            raise
                finally:
                    try:
                        for ident, resource in list(resources.items()):
                            if isinstance(ident, int):
                                try:
                                    (resource[0] if isinstance(resource, tuple) else resource).close()
                                except BaseException:
                                    pass
                    finally:
                        if "temporary" in resources:
                            Path(resources["temporary"]).unlink(missing_ok=True)


def _pack(value):
    if isinstance(value, str):
        return ["string", value.encode("utf-8", "surrogatepass").hex()]
    if isinstance(value, (list, tuple)):
        return ["list", [_pack(item) for item in value]]
    if isinstance(value, dict):
        return ["dict", [[_pack(key), _pack(item)] for key, item in value.items()]]
    if isinstance(value, float) and not math.isfinite(value):
        return ["float", repr(value)]
    return ["value", value if isinstance(value, (int, float, bool, type(None))) else None]


def _unpack(value):
    kind, data = value
    if kind == "float":
        return float(data)
    if kind == "string":
        return bytes.fromhex(data).decode("utf-8", "surrogatepass")
    if kind == "list":
        return [_unpack(item) for item in data]
    if kind == "dict":
        return {_unpack(key): _unpack(item) for key, item in data}
    return data
