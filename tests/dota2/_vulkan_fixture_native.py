# SPDX-License-Identifier: GPL-2.0-or-later
"""Unittest, archive and imported-API bindings for the V staging fixtures."""
import atexit
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def _module(name, path):
    specification = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(specification)
    sys.modules[name] = result
    specification.loader.exec_module(result)
    return result


_transport = _module("vulkan_fixture_transport", ROOT / "build-support/dota2/_vulkan_native.py")


_host = _module("vulkan_fixture_host", ROOT / "build-support/native_host.py")
_controller = _host.Controller(ROOT / "tests/dota2/vulkan_fixture.v", "VINIX_DOTA_VULKAN_FIXTURE_QUERY")


def _binary():
    _transport._BINARY = _controller.executable()
    return _transport._BINARY


def _view(value):
    if isinstance(value, list):
        return [_view(item) for item in value]
    if isinstance(value, dict):
        if set(value) == {"bytes_hex"}:
            return bytes.fromhex(value["bytes_hex"])
        return {name: _view(item) for name, item in value.items()}
    return value


def query(operation, arguments, namespace, case=None):
    _binary()
    contexts = contextlib.ExitStack()
    stage = namespace["stage"]

    class Owner:
        def __init__(self, manager):
            self.manager = manager
            self.active = False
        def __enter__(self):
            entered = self.manager.__enter__()
            self.active = True
            contexts.push(self)
            return entered
        def __exit__(self, *error):
            if not self.active:
                return False
            self.active = False
            return self.manager.__exit__(*error)

    def unit(name, values):
        return getattr(case, name)(*_view(values))

    def stage_call(name, values):
        return getattr(stage, name)(*_view(values))

    def set_member(name, value):
        setattr(case, name, _view(value))

    def binding(descriptor, observations):
        kind = descriptor["kind"]
        if kind == "value":
            return _view(descriptor["value"])
        if kind == "return":
            return _view(descriptor["value"])
        if kind == "member":
            return getattr(case, descriptor["name"])
        if kind == "wrap":
            return getattr(stage, descriptor["name"])
        if kind == "namespace":
            original = getattr(stage, descriptor["name"])
            return SimpleNamespace(**{**vars(original), **{
                name: binding(value, observations) for name, value in descriptor["attributes"].items()}})
        if kind == "callback":
            def invoke(*args, **kwargs):
                record = query("effect", {"name": descriptor["name"], "context": descriptor["context"],
                                          "args": list(args), "keywords": kwargs}, namespace, case)
                if "observation" in record:
                    observations.append(record["observation"])
                value = record["result"]
                conversion = descriptor.get("result")
                if conversion in ("completed", "completed_stdout"):
                    options = {} if value is None else {"stdout": value}
                    completed = stage.subprocess.CompletedProcess(args[0], 0, **options)
                    return completed.stdout if conversion == "completed_stdout" else completed
                if conversion == "path":
                    return Path(value)
                if conversion == "paths":
                    return tuple(Path(item) for item in value)
                return value
            return invoke
        raise RuntimeError("unknown Vulkan fixture binding: " + kind)

    def invoke(patches, name, values, error=None):
        observations = []
        result = None
        with contextlib.ExitStack() as stack:
            mocks = []
            for location, descriptor in patches:
                target = {"stage": stage, "sys": sys}[location[0]]
                for component in location[1:-1]:
                    target = getattr(target, component)
                value = binding(descriptor, observations)
                options = {"wraps": value} if descriptor["kind"] == "wrap" else {"side_effect": value} if descriptor["kind"] == "callback" else {"return_value": value} if descriptor["kind"] in ("return", "member") else {"new": value}
                mocks.append(stack.enter_context(patch.object(target, location[-1], **options)))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            if error:
                stack.enter_context(case.assertRaisesRegex(getattr(__import__("builtins"), error[0]), error[1]))
            result = stage_call(name, values)
        return {"result": result, "observations": observations, "mocks": mocks}

    def expect(name, values, exception, expression):
        with case.assertRaisesRegex(getattr(__import__("builtins"), exception), expression):
            stage_call(name, values)

    def wrap(manager):
        return Owner(manager)

    def patch_one(name, descriptor):
        observations = []
        value = binding(descriptor, observations)
        options = {"wraps": value} if descriptor["kind"] == "wrap" else {"side_effect": value} if descriptor["kind"] == "callback" else {"return_value": value} if descriptor["kind"] in ("return", "member") else {"new": value}
        return Owner(patch.object(stage, name, **options))

    context = {"REPO": namespace["REPO"], "__file__": namespace["__file__"], "sys": sys,
               "subprocess": subprocess, "shutil": shutil, "_unit": unit, "_stage": stage,
               "_stage_call": stage_call, "_set_member": set_member, "_member": lambda name: getattr(case, name),
               "_append_member": lambda name, value: getattr(case, name).append(_view(value)),
               "_deb_bytes": lambda files, *links: namespace["deb_bytes"](_view(files), *links),
               "_invoke": invoke, "_expect": expect, "_wrap": wrap, "_patch": patch_one,
               "_patch_object": lambda target, name, value: patch.object(target, name, return_value=value),
               "_assert_raises": lambda name, expression: case.assertRaisesRegex(getattr(__import__("builtins"), name), expression),
               "_import": _module, "tempfile": tempfile, "tarfile": tarfile, "io": io, "bytes": bytes}
    with contexts:
        return _transport.query(operation, arguments, context)
