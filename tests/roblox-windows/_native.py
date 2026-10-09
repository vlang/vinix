# SPDX-License-Identifier: MIT
"""Borrowed interpreter objects for native Roblox Windows guest policy."""
import importlib.util
from pathlib import Path
import runpy

_HERE = Path(__file__).resolve().parent
_package = runpy.run_path(str(_HERE.parents[1] / "tools/_package_store_native.py"))
_spec = importlib.util.spec_from_file_location("roblox_guest_bridge", _HERE.parent / "kernel-gaps/_native.py")
_gap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gap)
_controller = _gap._host.Controller(_HERE / "guest_query.v", "VINIX_ROBLOX_GUEST_QUERY", process=_gap._Process)
_host_controller = _package["_host"].Controller(_HERE / "host_query.v", "VINIX_ROBLOX_HOST_QUERY")


def host(operation, namespace, *arguments):
    return _package["call"](operation, arguments, namespace, controller=_host_controller)


def guest(operation, namespace, *arguments):
    resources = {"arg" + str(index): value for index, value in enumerate(arguments)}
    resources.update({"intrinsic-" + key: value for key, value in {"truth": bool, "format": format, "iterate": iter, "attribute": getattr, "slice": slice}.items()})
    resources["intrinsic-invoke"] = lambda target, *args: target(*args)
    resources.update(root=namespace["ROOT"], file=namespace["__file__"], owned=operation in ("run_guest", "stop"))
    if operation == "stop":
        resources.update(pid=arguments[0], master=arguments[1])

    extra_fds = {}
    terminal = False
    def open_fd(path, flags):
        fd = namespace["os"].open(path, flags)
        try:
            extra_fds[id(fd)] = (fd, path)
        except BaseException:
            namespace["os"].close(fd)
            raise
        return fd
    def close_fd(fd):
        extra_fds.pop(id(fd), None)
        return namespace["os"].close(fd)
    resources["intrinsic-open-fd"] = open_fd
    resources["intrinsic-close-fd"] = close_fd

    class Borrowed:
        def call(self, request, primitive, **options):
            original_cleanup = options["cleanup"]
            def cleanup():
                try:
                    original_cleanup()
                finally:
                    if not terminal:
                        for key, (fd, path) in tuple(extra_fds.items()):
                            extra_fds.pop(key)
                            namespace["os"].close(fd)
                            path.unlink()
            options["cleanup"] = cleanup
            def binding(method, row):
                nonlocal terminal
                if method == "invoke":
                    return primitive("function", {"owner": "intrinsic-invoke", "method": "__call__",
                                    "args": [["owner", row["target"]], *row["args"]], "result": "owner", "call": True})
                if method == "finished":
                    value = primitive(method, row)
                    terminal = True
                    return value
                if method in ("truth", "format", "iterate", "attribute", "slice"):
                    arguments = [["owner", ident] for ident in row["args"]] if method == "slice" else [["owner", row["id"]]]
                    if method == "format": arguments.append(["value", row["spec"]])
                    if method == "attribute": arguments.append(["value", row["name"]])
                    return primitive("function", {"owner": "intrinsic-" + method, "method": "__call__",
                                    "args": arguments, "result": "value" if method in ("truth", "format") else "owner"})
                if method == "exception_matches":
                    error = options["errors"][row["error"]["binding_error"]]
                    kind = tuple(resources[ident] for ident in row["classes"]) if "classes" in row else resources[row["class"]]
                    traceback = error.__traceback__
                    try:
                        try:
                            raise error.with_traceback(traceback)
                        except kind:
                            return True
                        except BaseException:
                            return False
                    finally:
                        error.__traceback__ = traceback
                if method in ("resolve", "literal"):
                    if method == "resolve":
                        parts = row["name"].split(".")
                        value = namespace.get(parts[0], getattr(_gap.builtins, parts[0], None))
                        for name in parts[1:]:
                            value = getattr(value, name)
                    else:
                        value = row["value"]
                    resources["next_id"] = resources.get("next_id", 0) + 1
                    ident = str(resources["next_id"])
                    resources[ident] = value
                    return ident
                return primitive(method, row)
            return _controller.call(request, binding, **options)

    return _gap.call("boot" if operation in ("run_guest", "stop") else operation,
                     {"public_operation": operation}, namespace, resources, controller=Borrowed())
