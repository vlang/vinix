#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
"""Compare the V GPU presenter with its immutable C reference under sanitizers.

The independent V fixture supplies bounded EGL/GLES and OS models. The old C
implementation is recovered from Git into the external test state directory;
it is never maintained or generated as source inside the checkout.
"""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = "8f7239d1fd4c593746279699f6ff25df5f4dd7bd"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, *, output=None, env=None):
    result = subprocess.run(command, cwd=ROOT, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if output:
        output.with_suffix(".stdout").write_bytes(result.stdout)
        output.with_suffix(".stderr").write_bytes(result.stderr)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command!r}\n" +
                           result.stdout.decode(errors="replace") +
                           result.stderr.decode(errors="replace"))
    return result


def exercise(state, headers, compiler):
    if ROOT == state or ROOT in state.parents:
        raise ValueError("Test artifacts and the frozen C reference must stay outside the checkout")
    state.mkdir(parents=True, exist_ok=True)
    commands = []

    def command(args):
        commands.append([str(item) for item in args])
        return run(commands[-1])

    reference_files = {}
    for name in ("gpu_present_egl.c", "gpu_present.h"):
        path = "desktop/" + name
        data = run(["git", "show", REFERENCE + ":" + path]).stdout
        destination = state / name
        destination.write_bytes(data)
        reference_files[path] = {
            "commit": REFERENCE,
            "blob": run(["git", "rev-parse", REFERENCE + ":" + path]).stdout.decode().strip(),
            "sha256": digest(destination), "bytes": len(data),
            "recover": ["git", "show", REFERENCE + ":" + path],
        }

    core = state / "gpu-v.c"
    api = state / "gpu-api.h"
    fixture = state / "fixture-v.c"
    generator = ROOT / "build-support/compile-v-module.py"
    command(["python3", generator, ROOT / "desktop/gpucore", core,
             "-d", "gpu_presenter_enabled", "--header", api])
    fixture_command = ["python3", generator, ROOT / "desktop/tools/tests/gpufixture", fixture]
    if platform.system() == "Darwin":
        fixture_command += ["-d", "fixture_native_display_int"]
    darwin_arm64 = platform.system() == "Darwin" and platform.machine() == "arm64"
    if darwin_arm64:
        fixture_command += ["-d", "fixture_darwin_arm64"]
    command(fixture_command)

    flags = [compiler, "-std=c11", "-O2", "-g", "-Wall", "-Wextra", "-Werror",
             "-Wno-unused-function", "-Wno-unused-label", "-Wno-unused-parameter",
             "-fsanitize=address,undefined", "-fsanitize-address-use-after-return=always",
             "-fno-omit-frame-pointer"]
    if platform.system() == "Darwin":
        # The frozen C reference passes EGL's native integer zero to the
        # platform-display extension's pointer parameter on Darwin.
        flags.append("-Wno-non-literal-null-conversion")
    remaps = ["-D" + name + "=gpf_" + name
              for name in ("malloc", "calloc", "free", "getenv", "open", "close", "ioctl")]
    includes = ["-idirafter", headers]
    command(flags + ["-include", api, "-c", fixture, "-o", state / "fixture.o"])
    fixture_objects = [state / "fixture.o"]
    if darwin_arm64:
        adapter = ROOT / "desktop/tools/tests/gpufixture/ioctl_darwin_arm64.S"
        command([compiler, "-c", adapter, "-o", state / "ioctl.o"])
        fixture_objects.append(state / "ioctl.o")
    command(flags + includes + remaps + ["-DVINIX_GPU_PRESENTER_EXTERNAL",
            "-c", state / "gpu_present_egl.c", "-o", state / "gpu-c.o"])
    command(flags + includes + remaps + ["-c", core, "-o", state / "gpu-v.o"])
    outputs = {}
    leak_detection = 0 if platform.system() == "Darwin" else 1
    environment = {**os.environ, "ASAN_OPTIONS": f"detect_leaks={leak_detection}:halt_on_error=1",
                   "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=1"}
    for variant in ("c", "v"):
        executable = state / ("gpu-" + variant)
        command(flags + fixture_objects + [state / ("gpu-" + variant + ".o"),
                         "-o", executable])
        outputs[variant] = run([str(executable)], output=state / ("run-" + variant), env=environment)
        if b"GPU FIXTURE PASS 67 0\n" not in outputs[variant].stdout:
            raise AssertionError("Fixture did not complete for " + variant)
    for stream in ("stdout", "stderr"):
        before = getattr(outputs["c"], stream)
        after = getattr(outputs["v"], stream)
        if before != after:
            difference = "".join(difflib.unified_diff(
                before.decode().splitlines(True), after.decode().splitlines(True),
                fromfile="original C " + stream, tofile="V " + stream))
            (state / ("difference-" + stream + ".log")).write_text(difference)
            raise AssertionError("Presenter behavior differs:\n" + difference)

    generated = core.read_text()
    implicit = re.findall(r"\b(?:memdup|new_array_from_c_array|v_malloc|v_calloc|"
                          r"string__substr|[A-Za-z0-9_]+__str)\s*\(", generated)
    if implicit:
        raise AssertionError("Implicit allocator or formatting call in presenter: " + repr(implicit))
    stack_evidence = {}
    for name, expression in {
        "config_attributes": r"i32 config_attributes\[13\]",
        "surface_attributes": r"i32 surface_attributes\[5\]",
        "context_attributes": r"i32 context_attributes\[3\]",
        "retained_vertices": r"float gpucore__presenter_vertices\[16\]",
        "shader_source_pointer": r"glShaderSource\(shader, 1, \(void\*\)\(&source\), NULL\)",
    }.items():
        match = re.search(expression, generated)
        if not match:
            raise AssertionError("Missing stack lifetime evidence: " + name)
        stack_evidence[name] = match[0]
    undefined = run(["nm", "-u", str(state / "gpu-v.o")]).stdout.decode()
    (state / "gpu-v-undefined.log").write_text(undefined)
    cases = outputs["v"].stdout.count(b"CASE ")
    first_frame_logs = outputs["v"].stderr.count(b"first frame begin")
    if cases != 67 or first_frame_logs != 41:
        raise AssertionError("All cases must complete and each valid presenter must log its first frame once")
    evidence = {
        "reference": reference_files,
        "presenter_sources": {str(path.relative_to(ROOT)): digest(path)
                              for path in sorted((ROOT / "desktop/gpucore").glob("*.v"))},
        "fixture_sources": {str(path.relative_to(ROOT)): digest(path)
                            for path in sorted((ROOT / "desktop/tools/tests/gpufixture").iterdir())
                            if path.is_file()},
        "compiler": run([compiler, "--version"]).stdout.decode().splitlines()[0],
        "commands": commands, "sanitizers": ["address", "undefined"],
        "use_after_return": "always", "lsan_enabled": bool(leak_detection),
        "cases": cases, "first_frame_logs": first_frame_logs,
        "exact_stdout_sha256": hashlib.sha256(outputs["v"].stdout).hexdigest(),
        "exact_stderr_sha256": hashlib.sha256(outputs["v"].stderr).hexdigest(),
        "stack_evidence": stack_evidence,
        "implicit_allocation_calls": implicit,
        "result": "PASS",
    }
    (state / "validation.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(f"GPU presenter: {cases} cases, exact C/V calls and pixels, ASan/UBSan PASS")
    print("Evidence:", state / "validation.json")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path, help="Keep test evidence outside the checkout")
    parser.add_argument("--headers", type=Path,
                        default=ROOT / "build-aarch64-userland/staging/usr/include",
                        help="Upstream EGL/GLES headers; native libc headers take precedence")
    parser.add_argument("--cc", default=os.environ.get("CC", "clang"))
    args = parser.parse_args()
    for relative in ("EGL/egl.h", "EGL/eglext.h", "GLES2/gl2.h"):
        if not (args.headers / relative).is_file():
            parser.error("Missing upstream header " + str(args.headers / relative))
    if args.state_dir:
        exercise(args.state_dir.resolve(), args.headers.resolve(), args.cc)
    else:
        with tempfile.TemporaryDirectory(prefix="vinix-gpu-fixture-") as directory:
            exercise(Path(directory).resolve(), args.headers.resolve(), args.cc)


if __name__ == "__main__":
    main()
