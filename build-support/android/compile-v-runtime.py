#!/usr/bin/env python3
"""Generate the native Android compatibility runtime from allocation-free V."""
import argparse
import importlib.util
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).resolve().parent


def compiler_tools():
    spec = importlib.util.spec_from_file_location("vinix_compile_v_module", ROOT / "build-support/compile-v-module.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def inputs():
    paths = [Path(__file__), SUPPORT / "runtime-v-abi.h", SUPPORT / "musl-statistics.h",
             ROOT / "build-support/compile-v-module.py", ROOT / "build-support/find-v.sh",
             *sorted((SUPPORT / "runtimecore").glob("*.v"))]
    version = subprocess.check_output(["sh", "-c", '. "$1/build-support/find-v.sh"; "$V" -version',
                                       "find-v", str(ROOT)], text=True).strip()
    return b"\0".join([*(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes() for path in paths),
                        version.encode()])


def generate(output, arch="arm64"):
    compiler_tools().generate(SUPPORT / "runtimecore", output.resolve(), arch, ["nofloat"])
    text = output.read_text()
    if arch == "arm64":
        # V3 initializes fixed const arrays with a constructor memmove. Restore
        # the compiler-emitted initializer as readonly static storage so native
        # atfork registrations see the original permanent callback addresses.
        # Every table value and callback body still comes from native V.
        table = "runtimecore__fork_thunks"
        pattern = r"\tmemmove\(" + table + r", \(runtimecore__ForkThunks\[128\]\)\{([^\n]+)\}, sizeof\(" + table + r"\)\);\n"
        match = re.search(pattern, text)
        if match is None:
            raise RuntimeError("V callback table initializer shape changed")
        declaration = "runtimecore__ForkThunks " + table + "[128];"
        if text.count(declaration) != 1:
            raise RuntimeError("V callback table declaration shape changed")
        text = text.replace(declaration, "static const runtimecore__ForkThunks " + table + "[128] = {" + match[1] + "};")
        text = re.sub(pattern, "", text, count=1)
        text += '\n#if !defined(__APPLE__)\n_Static_assert(sizeof(runtimecore__ForkHandler) == 80 && _Alignof(runtimecore__ForkHandler) == 8, "Original native fork slot layout");\n'
        for field, offset in (("prepare", 40), ("parent", 48), ("child", 56), ("dso", 64), ("used", 72)):
            text += f'_Static_assert(__builtin_offsetof(runtimecore__ForkHandler, {field}) == {offset}, "Original fork {field} offset");\n'
        text += '_Static_assert(sizeof(runtimecore__ForkThunks) == 24, "Original three-callback table entry");\n#endif\n'
    output.write_text(text)


def build(output, compiler, generated_dir, arch="arm64"):
    generated_dir.mkdir(parents=True, exist_ok=True)
    source = generated_dir / "android-runtime.c"
    generate(source, arch)
    subprocess.run([compiler, "-O2", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                    "-Wno-unused-label", "-Wno-unused-parameter", "-fvisibility=hidden", "-shared", "-fPIC",
                    "-I", str(SUPPORT), str(source), "-ldl", "-o", str(output)], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--arch", choices=("amd64", "arm64"), default="arm64")
    parser.add_argument("--cc", help="Build a shared library rather than only generating its C artifact")
    parser.add_argument("--generated-dir", type=Path)
    args = parser.parse_args()
    if args.cc:
        build(args.output, args.cc, args.generated_dir or args.output.parent / "generated", args.arch)
    else:
        generate(args.output, args.arch)
