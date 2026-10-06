#!/usr/bin/env python3
"""Compile the upstream Kbuild i915 source list against Vinix's API layer.

This is a readiness check, not a build-success substitute: unsupported driver
translation units make the command fail and their diagnostics remain in JSON.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import upstream

HERE = Path(__file__).resolve().parent


def driver_sources(root, make):
    driver = root / "drivers/gpu/drm/i915"
    # Ask the actual upstream Makefile to expand its object list. Do not guess
    # from file names, include optional self-tests, or maintain a forked list.
    with tempfile.TemporaryDirectory(prefix="vinix-i915-kbuild-") as temporary:
        script = Path(temporary) / "Makefile"
        script.write_text("\n".join([
            "src := " + str(driver), "srctree := " + str(root),
            "CONFIG_X86 := y", "CONFIG_ACPI := y", "CONFIG_DRM_I915 := y",
            "CONFIG_DRM_FBDEV_EMULATION := y",
            "include " + str(driver / "Makefile"),
            ".PHONY: vinix-source-list",
            "vinix-source-list:", "\t@printf '%s\\n' $(i915-y)", "",
        ]))
        result = subprocess.run([make, "-s", "-f", str(script), "vinix-source-list"],
                                check=True, capture_output=True, text=True)
    return sorted(set(driver / (p[:-2] + ".c") for p in result.stdout.split() if p.endswith(".o")))


def generate_headers(directory):
    # The native build derives these declarations and adapters from V exports
    # and ABI metadata. Regenerate them here instead of using kernel obj files
    # that may belong to another architecture or an older implementation.
    adapters = [("spinlock.json", "spinlock_adapters.h"),
                ("atomic-exchange.json", "atomic_exchange.h")]
    # The integer-policy migration introduces this metadata alongside its
    # consumers. Older committed source snapshots have neither prerequisite.
    if (HERE / "abi/overflow.json").is_file():
        adapters.append(("overflow.json", "integer_policy.h"))
    for schema, header in adapters:
        subprocess.run([sys.executable, str(HERE / "generate-abi.py"),
                        str(HERE / "abi" / schema), str(directory / "vinix" / header)],
                       check=True, capture_output=True, text=True)


def generate_bounds(directory, root, archive, compiler, flags):
    # Use the same target/config/includes as every audited driver unit. The
    # original bounds source comes from the verified archive outside its import.
    script = HERE / "generate-bounds.py"
    spec = importlib.util.spec_from_file_location("vinix_audit_bounds", script)
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    output = directory / "generated/bounds.h"
    return generator.generate(root, archive, output, Path(str(output) + ".d"),
                              Path(str(output) + ".json"), compiler,
                              [flag for flag in flags if flag != "-fsyntax-only"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path,
                        default=upstream.DEFAULT / ("linux-" + upstream.PIN["version"]))
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--archive", type=Path,
                        help="pinned Linux archive used to derive kernel bounds")
    parser.add_argument("--make", default="make")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--output", type=Path, default=HERE.parents[1] / "build/linuxkpi/i915-audit.json")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    root = args.source_dir.resolve()
    try:
        upstream.verify(root)
        sources = driver_sources(root, args.make)
        if not sources:
            raise ValueError("upstream Kbuild returned no i915 sources")
        with tempfile.TemporaryDirectory(prefix="vinix-i915-audit-") as temporary:
            generated = Path(temporary) / "include"
            generate_headers(generated)
            flags = [
                "--target=x86_64-unknown-none", "-std=gnu11", "-ffreestanding", "-fwrapv",
                "-nostdinc", "-fsyntax-only", "-ferror-limit=5",
                "-Werror=implicit-function-declaration", "-Wno-unused-parameter",
                "-D__KERNEL__", "-include", "linux/kconfig.h",
                # Linux 6.6.157 scripts/Makefile.lib adds this after LINUXINCLUDE's
                # kconfig preinclude, before parsing each C translation unit.
                "-include", str(root / "include/linux/compiler_types.h"),
                "-DCONFIG_X86=1", "-DCONFIG_X86_64=1",
                "-DCONFIG_ACPI=1", "-DCONFIG_DRM_I915=1", "-DCONFIG_DRM_FBDEV_EMULATION=1",
                "-isystem", str(HERE.parent / "freestnd-c-hdrs"),
                "-I", str(generated),
                "-I", str(HERE / "include"), "-I", str(HERE.parent / "c"),
                "-I", str(root / "include"), "-I", str(root / "include/uapi"),
                "-I", str(root / "arch/x86/include"),
                "-I", str(root / "arch/x86/include/uapi"),
                "-I", str(root / "drivers/gpu/drm/i915"),
            ]
            bounds = generate_bounds(generated, root,
                                     args.archive or root.parent /
                                     ("linux-" + upstream.PIN["version"] + ".tar.xz"),
                                     args.cc, flags)

            def compile_source(source):
                result = subprocess.run([args.cc] + flags + [str(source)], capture_output=True, text=True)
                return {"source": str(source.relative_to(root)), "passed": result.returncode == 0,
                        "diagnostics": result.stderr}

            with ThreadPoolExecutor(max_workers=args.jobs) as pool:
                results = list(pool.map(compile_source, sources))
        failures = [r for r in results if not r["passed"]]
        blockers = {}
        for result in failures:
            first = next((line for line in result["diagnostics"].splitlines() if "error:" in line),
                         "compiler failed without an error diagnostic")
            # Group by the actual diagnostic, retaining complete output per TU.
            key = re.sub(r"^.*?(?:fatal )?error: ", "", first)
            blockers[key] = blockers.get(key, 0) + 1
        report = {"linux_version": upstream.PIN["version"], "pci_id": "8086:9a49",
                  "stage": "syntax-only; link/runtime readiness is not checked",
                  "bounds": bounds,
                  "compiled": len(results) - len(failures), "total": len(results),
                  "blockers": blockers, "results": results}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        print("i915 syntax readiness: %d/%d translation units pass" % (report["compiled"], report["total"]))
        for blocker, count in sorted(blockers.items(), key=lambda item: -item[1]):
            print("  %d: %s" % (count, blocker))
        print("Full diagnostics: " + str(args.output))
        return 1 if failures else 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("i915 audit failed: " + str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.rstrip(), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
