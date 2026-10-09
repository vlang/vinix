# SPDX-License-Identifier: GPL-2.0-or-later
"""Borrowed library objects for native Dota guest orchestration."""
import importlib.util
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("wake_vm_library_bridge", _HERE.parent / "kernel-gaps/_native.py")
_gap = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_gap)
_controller = _gap._host.Controller(_HERE / "wake_guest_query.v", "VINIX_WAKE_GUEST_QUERY", process=_gap._Process)


def guest(operation, namespace, *arguments):
    resources = {"arg" + str(index): value for index, value in enumerate(arguments)}
    resources.update(repo=namespace["REPO"], file=namespace["__file__"], owned=operation in ("boot", "stop_guest"))
    if operation == "stop_guest":
        resources.update(pid=arguments[0], master=arguments[1])

    resources.update({"intrinsic-" + key: value for key, value in {"truth": bool, "iterate": iter, "attribute": getattr}.items()})

    class BootRoot:
        def resolve(self):
            return resources["arg0"].boot_repo.resolve()

    resources["wake-root"] = BootRoot()

    class Borrowed:
        def call(self, request, primitive, **options):
            def binding(method, row):
                if method == "stop_public":
                    resources["reaped"] = resources["closed"] = True
                    return primitive("function", {"name": "stop_guest", "args": [["owner", "pid"], ["owner", "master"]],
                        "result": "owner", "call": True})
                if method == "finished":
                    # A completed public call returns process responsibility to
                    # its original caller; broken transport retains the guardian.
                    resources["reaped"] = True
                    return primitive(method, row)
                if method in ("truth", "iterate", "attribute"):
                    args = [["owner", row["id"]]]
                    if method == "attribute": args.append(["value", row["name"]])
                    return primitive("function", {"owner": "intrinsic-" + method, "method": "__call__", "args": args,
                        "result": "value" if method == "truth" else "owner", "call": True})
                if method == "exception_matches":
                    error = options["errors"][row["error"]["binding_error"]]
                    kind = tuple(resources[key] for key in row["classes"]) if "classes" in row else resources[row["class"]]
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
                if method in ("error_object", "literal", "resolve"):
                    if method == "resolve":
                        parts = row["name"].split(".")
                        value = namespace.get(parts[0], getattr(_gap.builtins, parts[0], None))
                        for part in parts[1:]:
                            value = getattr(value, part)
                    else:
                        value = options["errors"][row["error"]["binding_error"]] if method == "error_object" else row["value"]
                    resources["next_id"] = resources.get("next_id", 0) + 1
                    ident = str(resources["next_id"])
                    resources[ident] = value
                    return ident
                return primitive(method, row)
            return _controller.call(request, binding, **options)

    return _gap.call("boot" if operation == "stop_guest" else operation,
        {"public_operation": operation}, namespace, resources, controller=Borrowed())


import runpy
_package = runpy.run_path(str(_HERE.parents[1] / "tools/_package_store_native.py"))
_host_controller = _package["_host"].Controller(_HERE / "wake_host_query.v", "VINIX_WAKE_HOST_QUERY")


def host(operation, namespace, *arguments):
    return _package["call"](operation, arguments, namespace, controller=_host_controller)
