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


# Runtime builder policies share this module's stdlib bindings and wire format.
import builtins as _builtins
import contextlib as _contextlib
import importlib.util as _import_util
import sys as _sys

_host_spec = _import_util.spec_from_file_location('android_runtime_transport', _HERE.parent / 'native_host.py')
_host = _import_util.module_from_spec(_host_spec)
_host_spec.loader.exec_module(_host)
_build_popen = subprocess.Popen


def _build_process(*args, **kwargs):
    return _build_popen(*args, start_new_session=True, **kwargs)


_build_transport = _host.Controller(_HERE / 'runtime-query.v', 'VINIX_ANDROID_RUNTIME_QUERY',
                                   prefix='vinix-android-runtime-controller-', process=_build_process)


def _build_snapshot(value):
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, (list, tuple)):
        return [_build_snapshot(item) for item in value]
    if isinstance(value, dict):
        return {key: _build_snapshot(item) for key, item in value.items()}
    return value


def _build_arguments(items, resources):
    return [resources[value] if kind == 'object' else resources['values'][value] if kind == 'owned'
            else Path(value) if kind == 'path' else bytes.fromhex(value) if kind == 'bytes'
            else value for kind, value in items]


def _build_invoke(row, context, resources):
    provider = resources[row['id']] if 'id' in row else context[row['module']] if row['module'] in context else __import__(row['module'], fromlist=['*'])
    options = dict(row.get('options', {}))
    options.update({key: resources[value] for key, value in row.get('keyword_objects', {}).items()})
    return getattr(provider, row['name'])(*_build_arguments(row.get('arguments', []), resources), **options)


def _build_exit(manager, exception):
    if exception[1] is None:
        manager.__exit__(*exception)
        return False
    error, traceback = exception[1:]
    try:
        raise error.with_traceback(traceback)
    except BaseException:
        replay = error.__traceback__
        error.__traceback__ = traceback
        try:
            return bool(manager.__exit__(*exception))
        finally:
            if error.__traceback__ is replay:
                error.__traceback__ = traceback


def _build_retire(owners):
    stack = _contextlib.ExitStack()
    for manager in owners.values():
        stack.push(manager)
    owners.clear()
    stack.__exit__(*_sys.exc_info())


def _build_primitive(operation, row, context, resources):
    if operation in ('invoke', 'acquire', 'enter'):
        value = _build_invoke(row, context, resources)
        if operation == 'enter':
            entered = value.__enter__()
            ident = _register(resources, entered)
            resources['owners'][ident] = value
            return ident
        if operation == 'acquire':
            return _register(resources, value)
        return value.hex() if row.get('bytes') else _build_snapshot(value)
    if operation == 'borrow':
        return _register(resources, resources['values'][row['name']])
    if operation == 'borrow_global':
        return _register(resources, context[row['name']])
    if operation == 'retain':
        return _register(resources, _build_arguments([row['value']], resources)[0])
    if operation == 'load_module':
        spec = context['importlib'].util.spec_from_file_location(row['name'],
                     _build_arguments([row['path']], resources)[0])
        assert spec and spec.loader
        module = context['importlib'].util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return _register(resources, module)
    if operation == 'is_none':
        return resources[row['id']] is None
    if operation == 'enter_existing':
        manager = resources[row['id']]
        ident = _register(resources, manager.__enter__())
        resources['owners'][ident] = manager
        return ident
    if operation == 'sequence':
        return _register(resources, _build_arguments(row['arguments'], resources))
    if operation == 'dictionary':
        return _register(resources, dict(zip(_build_arguments(row['keys'], resources),
                                            _build_arguments(row['values'], resources))))
    if operation == 'pool_map':
        shared = {key: _build_arguments([value], resources)[0] for key, value in row['shared'].items()}
        with context['concurrent'].futures.ThreadPoolExecutor(max_workers=row['workers']) as pool:
            result = list(pool.map(lambda item: build_call(row['operation'], {}, context,
                               values=dict(shared, item=item)), resources[row['records']]))
        return _register(resources, result)
    if operation == 'getattr':
        value = getattr(resources[row['id']], row['name'])
        return _register(resources, value) if row.get('object') else _build_snapshot(value)
    if operation == 'setattr':
        setattr(resources[row['id']], row['name'], _build_arguments([row['value']], resources)[0])
        return None
    if operation == 'iterate':
        try:
            value = next(resources[row['id']])
        except StopIteration:
            return {'done': True}
        return {'done': False, 'value': _register(resources, value)}
    if operation == 'exit':
        manager = resources['owners'].pop(row['id'])
        value = row.get('error')
        if value is None:
            exception = (None, None, None)
        else:
            error = resources['errors'][value['binding_error']] if 'binding_error' in value else getattr(_builtins, value['kind'])(value['message'])
            exception = (type(error), error, error.__traceback__)
        return _build_exit(manager, exception)
    if operation == 'exception_is':
        return isinstance(resources['errors'][row['error']['binding_error']],
                          tuple(getattr(_builtins, name) for name in row['kinds']))
    if operation == 'function':
        value = context[row['name']](*_build_arguments(row.get('arguments', []), resources),
                                    **row.get('options', {}))
        return _register(resources, value) if row.get('object') else _build_snapshot(value)
    if operation == 'print':
        print(row['data'], **row.get('options', {}))
        return None
    return _primitive(operation, row, context, resources)


def build_call(operation, arguments, context, *, values=None):
    resources = {'values': {} if values is None else values, 'owners': {}, 'errors': []}
    constants = {name: _build_snapshot(context[name]) for name in
                 ('MIRROR', 'PREFIX', 'ARCHITECTURE', 'REPOSITORIES', 'ROOT_PACKAGES', 'CALCULATOR', 'REQUIRED')}
    result = _build_transport.call({'operation': operation, 'arguments': _build_snapshot(arguments),
                                   'constants': constants, 'source': context['__file__'],
                                   'root': str(context['ROOT']), 'support': str(context['SUPPORT'])},
        lambda op, row: _build_primitive(op, row, context, resources),
        pack=_pack, unpack=_unpack, errors=resources['errors'],
        exception=lambda row: getattr(_builtins, row['kind'])(row['message']),
        cleanup=lambda: _build_retire(resources['owners']))
    return resources[result['object_result']] if isinstance(result, dict) and 'object_result' in result else result
