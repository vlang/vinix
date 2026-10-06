#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check genuine pinned bounds generation and failure publication boundaries.

Uses the real target compiler and unchanged Linux sources. The resulting
kernel bounds main is never linked or executed. No Linux page runtime is
implemented or simulated by this test.
"""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "kernel/linuxkpi/generate-bounds.py"
sys.path.insert(0, str(SCRIPT.parent))
spec = importlib.util.spec_from_file_location("bounds_generator", SCRIPT)
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(keep_directory=None):
    linux = Path(os.environ.get("LINUXKPI_SOURCE_DIR",
                                generator.upstream.DEFAULT /
                                ("linux-" + generator.upstream.PIN["version"]))).resolve()
    archive = linux.parent / ("linux-" + generator.upstream.PIN["version"] + ".tar.xz")
    compiler = os.environ.get("CC", "clang")
    temporary = (tempfile.TemporaryDirectory(prefix="vinix-bounds-generation-")
                 if keep_directory is None else None)
    work = Path(temporary.name) if temporary else Path(keep_directory).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    results = []
    try:
        original_config = (ROOT / "kernel/linuxkpi/include/generated/autoconf.h").read_text()
        config = re.sub(r"^#define CONFIG_MMU[^\n]*\n", "", original_config,
                        flags=re.MULTILINE)
        profiles = {}
        integer_policy_schema = ROOT / "kernel/linuxkpi/abi/overflow.json"
        adapters = [("spinlock.json", "spinlock_adapters.h"),
                    ("atomic-exchange.json", "atomic_exchange.h")]
        if integer_policy_schema.exists():
            adapters.append(("overflow.json", "integer_policy.h"))
        for name, mmu, cpus in (("native", "1", 256), ("cpu64", "1", 64),
                                 ("nommu", None, 256), ("mmu_zero", "0", 256)):
            include = work / (name + " inputs # $ space") / "include"
            (include / "generated").mkdir(parents=True)
            selected = re.sub(r"^#define CONFIG_NR_CPUS[^\n]*",
                              "#define CONFIG_NR_CPUS " + str(cpus), config,
                              flags=re.MULTILINE)
            if mmu is not None:
                selected += "\n#define CONFIG_MMU " + mmu + "\n"
            (include / "generated/autoconf.h").write_text(selected)
            for schema, header in adapters:
                subprocess.run([sys.executable, str(ROOT / "kernel/linuxkpi/generate-abi.py"),
                                str(ROOT / "kernel/linuxkpi/abi" / schema),
                                str(include / "vinix" / header)], check=True,
                               capture_output=True, text=True)
            profiles[name] = include

        def flags(profile, standard):
            return ["--target=x86_64-unknown-none", "-std=" + standard, "-O2",
                    "-ffreestanding", "-fwrapv", "-nostdinc", "-mno-red-zone",
                    "-mcmodel=kernel", "-fno-PIC", "-Werror=implicit-function-declaration",
                    "-Wno-unused-parameter", "-D__KERNEL__", "-include", "linux/kconfig.h",
                    "-include", str(linux / "include/linux/compiler_types.h"),
                    "-isystem", str(ROOT / "kernel/freestnd-c-hdrs"),
                    "-I", str(profiles[profile]), "-I", str(ROOT / "kernel/linuxkpi/include"),
                    "-I", str(ROOT / "kernel/c"), "-I", str(linux / "include"),
                    "-I", str(linux / "include/uapi"), "-I", str(linux / "arch/x86/include"),
                    "-I", str(linux / "arch/x86/include/uapi"), "-MMD", "-MP"]

        def invoke(name, output, native, *, source=linux, source_archive=archive, cc=compiler):
            command = [sys.executable, str(SCRIPT), "--source-dir", str(source),
                       "--archive", str(source_archive), "--output", str(output),
                       "--cc", cc, "--"] + native
            completed = subprocess.run(command, capture_output=True, text=True)
            (work / (name + ".log")).write_text(completed.stdout + completed.stderr)
            result = {"name": name, "command": command, "returncode": completed.returncode,
                      "warnings": completed.stderr.count("warning:"),
                      "errors": [s for s in completed.stderr.splitlines() if "error:" in s],
                      "stderr_sha256": hashlib.sha256(completed.stderr.encode()).hexdigest()}
            results.append(result)
            return completed

        reference = work / "reference.c"
        reference.write_text(r'''
#define __GENERATING_BOUNDS_H
#include <linux/page-flags.h>
#include <linux/mmzone.h>
#include <linux/log2.h>
#include <linux/spinlock_types.h>
#include GENERATED_HEADER
_Static_assert(NR_PAGEFLAGS == __NR_PAGEFLAGS, "page enum derived");
_Static_assert(MAX_NR_ZONES == __MAX_NR_ZONES, "zone enum derived");
_Static_assert(SPINLOCK_SIZE == sizeof(spinlock_t), "actual spinlock ABI");
#ifdef CONFIG_SMP
_Static_assert(NR_CPUS_BITS == order_base_2(CONFIG_NR_CPUS), "CPU bound derived");
#endif
#ifdef CONFIG_LRU_GEN
_Static_assert(LRU_GEN_WIDTH == order_base_2(MAX_NR_GENS + 1), "LRU bound derived");
_Static_assert(__LRU_REFS_WIDTH == MAX_NR_TIERS - 2, "LRU tier bound derived");
#else
_Static_assert(LRU_GEN_WIDTH == 0, "disabled LRU has no generation field");
_Static_assert(__LRU_REFS_WIDTH == 0, "disabled LRU has no reference field");
#endif
''')
        outputs = {}
        for profile in ("native", "cpu64"):
            # Exercise dependency escaping using spaces, # and $ in real paths.
            output = work / (profile + " quoted # $ output") / "generated/bounds # $.h"
            outputs[profile] = output
            timestamp = None
            for standard in ("gnu99", "gnu11"):
                selected = flags(profile, standard)
                completed = invoke(profile + "-" + standard, output, selected)
                require(completed.returncode == 0, completed.stderr)
                require(not list(output.parent.glob(".bounds-*")), "successful temporary cleanup")
                provenance = json.loads(Path(str(output) + ".json").read_text())
                require(provenance["header_sha256"] == sha256(output), "header publication marker")
                require(provenance["dependency_sha256"] == sha256(Path(str(output) + ".d")),
                        "dependency publication marker")
                require(provenance["archive_sha256"] == generator.upstream.PIN["sha256"],
                        "exact pinned archive")
                require(provenance["configuration"]["CONFIG_MMU"] == "1", "actual MMU config")
                require(not any(x in provenance["flags"] for x in ("-MD", "-MMD", "-MP")),
                        "caller dependency actions are replaced")
                dependency = Path(str(output) + ".d").read_text()
                require(".bounds-build-" not in dependency, "no cleaned source dependency")
                for path in (archive, SCRIPT, SCRIPT.parent / "upstream.json",
                             SCRIPT.parent / "upstream.py",
                             profiles[profile] / "generated/autoconf.h",
                             ROOT / "kernel/freestnd-c-hdrs/stdint.h"):
                    require(generator.make_escape(path) in dependency,
                            "missing stable/all-header dependency: " + str(path))
                hashed_inputs = [profiles[profile] / "generated/autoconf.h",
                                 profiles[profile] / "vinix/atomic_exchange.h",
                                 ROOT / "kernel/linuxkpi/include/linux/spinlock_types_raw.h",
                                 archive, SCRIPT, SCRIPT.parent / "upstream.py",
                                 SCRIPT.parent / "upstream.json",
                                 Path(provenance["compiler_path"])]
                if integer_policy_schema.exists():
                    hashed_inputs.append(profiles[profile] / "vinix/integer_policy.h")
                for path in hashed_inputs:
                    require(provenance["input_sha256"][str(path.resolve())] == sha256(path),
                            "actual config/ABI input hash: " + str(path))
                require(dependency.startswith(generator.make_escape(output) + ":"),
                        "quoted dependency target")
                if timestamp is not None:
                    require(output.stat().st_mtime_ns == timestamp, "unchanged header timestamp")
                timestamp = output.stat().st_mtime_ns
                check = subprocess.run(shlex_compiler(compiler) +
                                       [x for x in selected if x not in ("-MMD", "-MP")] +
                                       ['-DGENERATED_HEADER="' + str(output) + '"',
                                        "-fsyntax-only", str(reference)],
                                       capture_output=True, text=True)
                (work / (profile + "-" + standard + "-reference.log")).write_text(
                    check.stdout + check.stderr)
                require(check.returncode == 0, check.stderr)
                results[-1]["reference_enums_and_sizes_passed"] = True
                results[-1]["header_sha256"] = sha256(output)
                results[-1]["provenance_sha256"] = sha256(Path(str(output) + ".json"))
        first = json.loads(Path(str(outputs["native"]) + ".json").read_text())["bounds"]
        second = json.loads(Path(str(outputs["cpu64"]) + ".json").read_text())["bounds"]
        require(first["NR_CPUS_BITS"] != second["NR_CPUS_BITS"], "configuration affects derived bounds")
        require({k: v for k, v in first.items() if k != "NR_CPUS_BITS"} ==
                {k: v for k, v in second.items() if k != "NR_CPUS_BITS"},
                "unrelated bounds survive a CPU-bound change")

        output = work / "failure outputs/generated/bounds.h"
        output.parent.mkdir(parents=True)
        bundle = {output: b"old header\n", Path(str(output) + ".d"): b"old dependencies\n",
                  Path(str(output) + ".json"): b"old provenance\n"}
        for path, data in bundle.items():
            path.write_bytes(data)

        def rejected(name, selected, expected, **kwargs):
            completed = invoke(name, output, selected, **kwargs)
            require(completed.returncode != 0, "bad generation unexpectedly passed: " + name)
            require(expected in completed.stderr, "missing rejection: " + name + "\n" + completed.stderr)
            require(all(path.read_bytes() == data for path, data in bundle.items()),
                    "failed generation modified the previous bundle")
            require(not list(output.parent.glob(".bounds-*")), "failed temporary cleanup: " + name)

        rejected("missing-mmu", flags("nommu", "gnu99"), "CONFIG_MMU must be 1")
        rejected("zero-mmu", flags("mmu_zero", "gnu11"), "CONFIG_MMU must be 1")
        wrong_target = flags("native", "gnu99")
        wrong_target[0] = "--target=aarch64-unknown-none"
        wrong_target = [x for x in wrong_target if x not in
                        ("-mno-red-zone", "-mcmodel=kernel", "-fno-PIC")]
        rejected("wrong-target", wrong_target, "__x86_64__ must be 1")
        rejected("compiler-failure", flags("native", "gnu99") + ["-D__NR_PAGEFLAGS=("],
                 "compiler failed with exit status")
        rejected("caller-output", flags("native", "gnu99") + ["-o", str(work / "forbidden")],
                 "compiler output/action")
        changed_archive = work / "changed.tar.xz"
        changed_archive.write_bytes(b"changed archive bytes\n")
        rejected("changed-archive", flags("native", "gnu99"), "archive SHA256 differs",
                 source_archive=changed_archive)

        # Hardlink immutable import data, then replace one link before editing.
        # No write ever targets the borrowed original file's inode.
        changed_source = work / "changed-source"
        shutil.copytree(linux, changed_source, copy_function=os.link)
        manifest = json.loads((changed_source / ".vinix-upstream.json").read_text())
        changed_name = next(iter(manifest["files"]))
        altered = changed_source / changed_name
        original_sha = sha256(linux / changed_name)
        replacement = altered.with_name(altered.name + ".replacement")
        replacement.write_bytes(altered.read_bytes() + b"\n/* altered test copy */\n")
        replacement.replace(altered)
        rejected("changed-source", flags("native", "gnu99"), "modified upstream source",
                 source=changed_source)
        require(sha256(linux / changed_name) == original_sha, "original source remained unchanged")

        input_header = profiles["native"] / "generated/autoconf.h"
        input_hash = sha256(input_header)
        protected = invoke("protected-header", input_header, flags("native", "gnu99"))
        require(protected.returncode != 0 and "overlap discovered compiler inputs" in protected.stderr,
                "discovered input header must be protected")
        require(sha256(input_header) == input_hash, "protected config remained unchanged")
        require(not Path(str(input_header) + ".d").exists() and
                not Path(str(input_header) + ".json").exists(), "no overlapping header sidecars")
        require(not list(input_header.parent.glob(".bounds-*")), "overlap temporary cleanup")

        # Exercise the early compiler-output guard using a private copy of the
        # real executable; this copy is never launched or overwritten.
        protected_compiler = work / "protected-compiler"
        compiler_executable = shutil.which(shlex_compiler(compiler)[0])
        require(compiler_executable is not None, "compiler executable exists")
        shutil.copyfile(compiler_executable, protected_compiler)
        protected_compiler.chmod(0o755)
        compiler_hash = sha256(protected_compiler)
        protected = invoke("protected-compiler", protected_compiler, flags("native", "gnu99"),
                           cc=str(protected_compiler))
        require(protected.returncode != 0 and "overlap each other or protected inputs" in protected.stderr,
                "compiler executable must be protected")
        require(sha256(protected_compiler) == compiler_hash, "protected compiler remained unchanged")

        # Launch real Clang, then change only this owned header after discovery
        # returns but before the generator can hash its newly discovered files.
        # The final real preprocessing pass must detect the stale macro profile.
        wrapper = work / "changing-profile.py"
        marker = work / "changed-profile-once"
        wrapper.write_text(
            "import pathlib, subprocess, sys\n"
            "command = " + repr(shlex_compiler(compiler)) + "\n"
            "header = pathlib.Path(" + repr(str(input_header)) + ")\n"
            "marker = pathlib.Path(" + repr(str(marker)) + ")\n"
            "result = subprocess.run(command + sys.argv[1:])\n"
            "if result.returncode == 0 and '-E' in sys.argv and not marker.exists():\n"
            "    original = header.read_text()\n"
            "    changed = original.replace('#define CONFIG_NR_CPUS 256', "
            "'#define CONFIG_NR_CPUS 64')\n"
            "    assert changed != original\n"
            "    header.write_text(changed)\n"
            "    marker.write_text('real discovery completed before change\\n')\n"
            "sys.exit(result.returncode)\n")
        saved_config = input_header.read_bytes()
        try:
            rejected("changing-profile-after-discovery", flags("native", "gnu99"),
                     "preprocessed configuration changed during bounds generation",
                     cc=shlex.join([sys.executable, str(wrapper)]))
            require(marker.exists(), "real after-discovery edit was exercised")
        finally:
            input_header.write_bytes(saved_config)

        # The selected compiler is an owned executable wrapper which runs the
        # real compiler unchanged, then replaces its own bytes after discovery.
        # This must be rejected before any sidecar or header is published.
        changing_compiler = work / "changing-compiler.py"
        compiler_marker = work / "changed-compiler-once"
        changing_compiler.write_text(
            "#!" + sys.executable + "\n"
            "import pathlib, subprocess, sys\n"
            "command = " + repr(shlex_compiler(compiler)) + "\n"
            "marker = pathlib.Path(" + repr(str(compiler_marker)) + ")\n"
            "result = subprocess.run(command + sys.argv[1:])\n"
            "if result.returncode == 0 and '-E' in sys.argv and not marker.exists():\n"
            "    source = pathlib.Path(__file__)\n"
            "    source.write_bytes(source.read_bytes() + b'\\n# changed compiler input\\n')\n"
            "    marker.write_text('real discovery completed before compiler change\\n')\n"
            "sys.exit(result.returncode)\n")
        changing_compiler.chmod(0o755)
        rejected("changing-compiler-after-discovery", flags("native", "gnu99"),
                 "compiler inputs changed during bounds generation",
                 cc=shlex.join([str(changing_compiler)]))
        require(compiler_marker.exists(), "real compiler-input change was exercised")

        # Stamp-only mode never opens the nonexistent source/archive. Reusing
        # the compiler identity avoids rehashing its bytes on unchanged builds.
        stamp = work / "commands # $ space/compiler.json"
        stamp_commands = []

        def stamp_run(selected, cc=compiler, accepted=True, destination=stamp):
            command = [sys.executable, str(SCRIPT), "--command-stamp", str(destination),
                       "--source-dir", str(work / "no-source"),
                       "--archive", str(work / "no-archive"), "--cc", cc, "--"] + selected
            completed = subprocess.run(command, capture_output=True, text=True)
            stamp_commands.append({"command": command, "returncode": completed.returncode,
                                   "stderr": completed.stderr})
            require((completed.returncode == 0) == accepted, completed.stderr)
            return completed

        selected = flags("native", "gnu99")
        stamp_run(selected)
        first_stamp = stamp.read_bytes()
        stamp_time = stamp.stat().st_mtime_ns
        stamped = json.loads(first_stamp)
        require(stamped["compiler"][0] == str(Path(compiler_executable).resolve()),
                "stamp canonical compiler executable")
        require(stamped["compiler_sha256"] == sha256(Path(compiler_executable)),
                "stamp compiler digest")
        require(stamped["flags"] == generator.native_flags(selected), "stamp native flags")
        stamp_run(selected)
        require(stamp.read_bytes() == first_stamp and stamp.stat().st_mtime_ns == stamp_time,
                "unchanged command stamp timestamp")
        stamp_run(selected + ["-DCHANGED_NATIVE_FLAG=1"])
        changed_stamp = stamp.read_bytes()
        require(changed_stamp != first_stamp, "changed flags update command stamp")
        stamp_run(selected, shlex.join(shlex_compiler(compiler) + ["-Qunused-arguments"]))
        require(stamp.read_bytes() not in (first_stamp, changed_stamp),
                "changed compiler argv updates command stamp")
        before_rejection = stamp.read_bytes()
        stamp_run(selected + ["-o", "forbidden"], accepted=False)
        require(stamp.read_bytes() == before_rejection, "invalid stamp flags preserve old stamp")
        require(not list(stamp.parent.glob(".bounds-*")), "stamp temporary cleanup")
        source_destination = work / "no-source/generated/forbidden-stamp.json"
        refused = stamp_run(selected, accepted=False, destination=source_destination)
        require("outside the verified import" in refused.stderr and not source_destination.exists(),
                "stamp destination inside import is rejected without opening sources")
        archive_destination = work / "no-archive"
        refused = stamp_run(selected, accepted=False, destination=archive_destination)
        require("overlaps protected inputs" in refused.stderr and not archive_destination.exists(),
                "stamp destination on archive is rejected without opening archive")

        # The real formatter must reject malformed/duplicate/missing markers.
        probe_macros = {"CONFIG_SMP": "1"}
        for malformed in ('\t.ascii "->NR_PAGEFLAGS $1 enum"\n',
                          '\t.ascii "->NR_PAGEFLAGS $1 enum"\n' * 2,
                          '\t.ascii "->NR_PAGEFLAGS guessed enum"\n'):
            try:
                generator.offsets(malformed, probe_macros)
            except ValueError:
                pass
            else:
                raise AssertionError("malformed compiler offsets accepted")

        result = {"scope": "Real pinned native compiler generation and publication tests only",
                  "generator_sha256": sha256(SCRIPT), "test_sha256": sha256(Path(__file__)),
                  "config_source_sha256": hashlib.sha256(original_config.encode()).hexdigest(),
                  "archive_sha256": generator.upstream.PIN["sha256"],
                  "profiles": {name: sha256(path / "generated/autoconf.h")
                               for name, path in profiles.items()},
                  "successful_runs": 4, "rejected_runs": 11,
                  "command_stamp_runs": stamp_commands,
                  "malformed_offsets_rejected": 3, "results": results}
        (work / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print("LinuxKPI bounds: 4 real GNU99/GNU11 generations, 11 failure cases, "
              "3 malformed offset cases and command stamps passed")
        return result
    finally:
        if temporary:
            temporary.cleanup()


def shlex_compiler(compiler):
    import shlex
    return shlex.split(compiler)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-directory", type=Path)
    args = parser.parse_args()
    run(args.keep_directory)
