# SPDX-License-Identifier: GPL-2.0-or-later
"""Standard-library calls for the native Minecraft staging policy."""
import importlib.util
from pathlib import Path
import sys

_HERE = Path(__file__).resolve().parent


def _module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


_host = _module("minecraft_host_transport", _HERE.parent / "native_host.py")
_wire = _module("minecraft_wire_values", _HERE.parent / "android/_boot_native.py")
_controller = _host.Controller(_HERE / "fetch-query.v", "VINIX_MINECRAFT_FETCH_QUERY")


def _exit(manager, error, traceback):
    if error is None:
        manager.__exit__(None, None, None)
        return False
    try:
        raise error.with_traceback(traceback)
    except BaseException:
        try:
            return bool(manager.__exit__(type(error), error, traceback))
        finally:
            error.__traceback__ = traceback


def _primitive(operation, row, context, owners):
    args = row.get("arguments", [])
    if operation == "constant":
        return context[row['name']]
    if operation == "method":
        value = getattr(args[0], row["name"])(*args[1:])
        return list(value) if row["name"] in ("items", "values", "keys") else value
    if operation == "slice":
        return row["value"][:row["end"]]
    if operation == "index":
        return args[0][args[1]]
    if operation == "builtin":
        import builtins
        return getattr(builtins, row["name"])(*args)
    if operation == "print":
        import builtins
        return context.get("print", builtins.print)(row["data"], flush=row["flush"])
    if operation == "compare":
        import operator
        return getattr(operator, row["name"])(*args)
    if operation == "range_next":
        if "range" not in owners:
            owners["range"] = iter(range(row["count"]))
        try:
            next(owners["range"])
        except StopIteration:
            return False
        return True
    if operation == "public":
        conversions = {"path": Path, "bytes": bytes.fromhex, "value": lambda value: value}
        result = context[row["name"]](*[conversions[kind](value) for kind,value in row.get("args", [])],
                                      **row.get("keywords", {}))
        return result.hex() if row.get("binary") else result
    if operation == "path":
        path = Path(row["path"])
        value = getattr(path, row["method"])
        result = value(*args, **row.get("options", {})) if callable(value) else value
        return str(result) if isinstance(result, Path) else result
    if operation == "fetch_once":
        request = context["urllib"].request.Request(row["url"], headers=row["headers"])
        with context["urllib"].request.urlopen(request, timeout=row["timeout"]) as response:
            return {'received':True, 'data':response.read().hex()}
        return {'received':False}
    if operation == "join":
        return str(Path(row["parent"]) / row["child"])
    if operation == "json":
        data = bytes.fromhex(row["data"]) if row["binary"] else row["data"]
        return context["json"].loads(data)
    if operation == "bytes_method":
        return getattr(bytes.fromhex(row["data"]), row["method"])(*args)
    if operation == "write_bytes":
        return Path(row["path"]).write_bytes(bytes.fromhex(row["data"]))
    if operation == "open_read":
        manager = Path(row["path"]).open("rb")
        value = manager.__enter__()
        ident = str(id(manager));owners[ident] = (manager, value)
        return ident
    if operation == "read_handle":
        return owners[row["id"]][1].read(row["size"]).hex()
    if operation == "close_handle":
        manager, _ = owners.pop(row['id'])
        error = row['error']
        cause = None if error is None else owners['errors'][error['binding_error']] if 'binding_error' in error else RuntimeError(error['message'])
        return _exit(manager, cause, None if cause is None else cause.__traceback__)
    if operation == "pool_open":
        manager = context["ThreadPoolExecutor"](max_workers=row["jobs"])
        value = manager.__enter__()
        ident = str(id(manager));owners[ident] = (manager,value)
        return ident
    if operation == "pool_start":
        owners['iterator'] = iter(owners[row['id']][1].map(
            lambda entry: context['_invoke']('download_entry', entry, row['root']), owners['entries']))
        return None
    if operation == 'entry_length':
        return len(owners['entries'])
    if operation == "pool_next":
        try:
            return {'done':False,'value':next(owners['iterator'])}
        except StopIteration:
            return {'done':True}
    if operation == "paths":
        return [str(value) for value in Path(row["path"]).rglob(row["pattern"])]
    if operation == "stat_size":
        return Path(row["path"]).stat().st_size
    if operation == "format":
        return format(args[0], row["specification"])
    raise RuntimeError("unknown Minecraft library primitive: " + operation)


def call(operation, arguments, context):
    errors = []
    owners = {'errors':errors, 'entries':arguments[0] if operation == 'download_all' else None}
    def cleanup():
        for key, value in owners.items():
            if key not in ('range','iterator','errors','entries'):
                value[0].__exit__(*sys.exc_info())
    def exception(row):
        return {"SystemExit": SystemExit, "RuntimeError": RuntimeError}[row["kind"]](row["message"])
    return _controller.call({"operation": operation, "arguments": arguments},
        lambda operation,row: _primitive(operation,row,context,owners),
        pack=_wire._pack, unpack=_wire._unpack, exception=exception, cleanup=cleanup,
        errors=errors,
        error_fields=lambda error: {"runtime_error": isinstance(error, RuntimeError), "retryable": isinstance(error,
            (context["urllib"].error.URLError, TimeoutError, OSError))})
