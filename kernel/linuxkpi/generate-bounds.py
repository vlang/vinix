#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Derive Linux bounds from the pinned source and the caller's native C flags.

The caller supplies its complete target/preprocessor flags after ``--``,
including generated ABI adapters and the real configuration include paths.
Disabled CONFIG booleans must be undefined, as in Linux autoconf.h.

No source is downloaded or installed in the verified import. The header is
published atomically after successful verification and compilation. Sidecars
publish first; an output filesystem failure can leave a newer sidecar with an
older header. The provenance header SHA detects that condition. Build rules
also need a compiler/flags/config stamp: a recorded command cannot cause Make
to invoke this program when future command-line flags change.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile

import upstream


def digest_bytes(data):
    return hashlib.sha256(data).hexdigest()


def run_compiler(command, *, input=None):
    result = subprocess.run(command, input=input, capture_output=True, text=True)
    # Keep complete real diagnostics, including warnings from original headers.
    if result.stderr:
        sys.stderr.write(result.stderr)
    if result.returncode:
        if result.stdout:
            sys.stderr.write(result.stdout)
        raise ValueError("compiler failed with exit status " + str(result.returncode))
    return result.stdout


def native_flags(flags):
    """Own the output/actions and dependency files, preserving all other flags."""
    result = []
    for flag in flags:
        if flag in ("-MD", "-MMD", "-MP"):
            continue
        if (flag in ("-c", "-S", "-E", "-M", "-MM", "-fsyntax-only")
                or flag.startswith(("-o", "-MF", "-MT", "-MQ", "-MJ", "--output"))):
            raise ValueError("caller flags contain a compiler output/action: " + flag)
        result.append(flag)
    return result


def configuration(macros_text):
    macros = {}
    for line in macros_text.splitlines():
        match = re.fullmatch(r"#define (\w+)(?: (.*))?", line)
        if match:
            macros[match.group(1)] = match.group(2) or ""
    required = {"CONFIG_X86": "1", "CONFIG_X86_64": "1", "CONFIG_64BIT": "1",
                "CONFIG_MMU": "1", "__x86_64__": "1",
                "__SIZEOF_LONG__": "8", "__SIZEOF_POINTER__": "8"}
    for name, value in required.items():
        if macros.get(name) != value:
            raise ValueError("unsupported bounds configuration: " + name + " must be " + value)
    if "CONFIG_SMP" in macros and macros["CONFIG_SMP"] != "1":
        raise ValueError("disabled CONFIG_SMP must be undefined, not defined as zero")
    return macros


def extract_source(archive):
    name = "linux-" + upstream.PIN["version"] + "/kernel/bounds.c"
    # Stream the verified archive; read only this exact regular member.
    with tarfile.open(archive, "r|xz") as source:
        for member in source:
            if member.name == name:
                if not member.isfile():
                    raise ValueError("kernel/bounds.c is not a regular archive member")
                with source.extractfile(member) as stream:
                    return stream.read()
    raise ValueError("pinned archive has no kernel/bounds.c")


def offsets(assembly, macros):
    """Apply the pinned scripts/Makefile.lib offsets format, never guess values."""
    values = {}
    definitions = []
    for line in assembly.splitlines():
        ascii_line = re.match(r'^\s*\.ascii\s+"([^\"]*)"', line)
        if not ascii_line or not ascii_line.group(1).startswith("->"):
            continue
        marker = ascii_line.group(1)
        if marker.startswith("->#"):
            comment = marker[3:]
            if "*/" in comment:
                raise ValueError("invalid offsets comment")
            definitions.append("/* " + comment + " */")
            continue
        match = re.fullmatch(r"->([A-Za-z_]\w*) [$#]*(-?\d+) (.+)", marker)
        if not match or "*/" in match.group(3):
            raise ValueError("invalid compiler offsets marker: " + marker)
        name, value, expression = match.groups()
        if name in values:
            raise ValueError("duplicate compiler offsets marker: " + name)
        values[name] = int(value)
        definitions.append("#define " + name + " " + value + " /* " + expression + " */")
    expected = {"NR_PAGEFLAGS", "MAX_NR_ZONES", "SPINLOCK_SIZE", "LRU_GEN_WIDTH",
                "__LRU_REFS_WIDTH"}
    if "CONFIG_SMP" in macros:
        expected.add("NR_CPUS_BITS")
    if set(values) != expected:
        raise ValueError("compiler offsets marker set differs from pinned kernel/bounds.c")
    header = ("#ifndef __LINUX_BOUNDS_H__\n#define __LINUX_BOUNDS_H__\n"
              "/*\n * DO NOT MODIFY.\n * Derived from pinned Linux kernel/bounds.c"
              " using its Kbuild offsets format.\n */\n\n" + "\n".join(definitions)
              + "\n\n#endif\n")
    return header.encode(), values


def make_escape(path):
    return str(path).replace("$", "$$").replace("#", "\\#").replace(" ", "\\ ")


def dependencies(data, source, output, additional):
    # -MQ quotes the target; preserve Clang/GCC's quoting for every other path.
    temporary = make_escape(source)
    if temporary not in data:
        raise ValueError("compiler dependency output omits bounds.c")
    data = data.replace(temporary, make_escape(additional[0]))
    # No -MP phony rules are requested, so this is exactly one Make rule.
    data = data.rstrip() + " \\\n  " + " \\\n  ".join(make_escape(p) for p in additional[1:]) + "\n"
    if str(source.parent) in data:
        raise ValueError("compiler dependency output retains temporary paths")
    if not data.startswith(make_escape(output) + ":"):
        raise ValueError("compiler dependency target differs from the output header")
    return data.encode()


def dependency_paths(data, output):
    """Read one compiler Make rule without treating quotes as shell syntax."""
    prefix = make_escape(output) + ":"
    if not data.startswith(prefix):
        raise ValueError("compiler dependency target differs from the output header")
    body = data[len(prefix):]
    paths, word = [], []
    index = 0
    while index < len(body):
        character = body[index]
        if character == "\\":
            index += 1
            if index == len(body):
                raise ValueError("incomplete compiler dependency escape")
            if body[index] != "\n":
                word.append(body[index])
        elif character == "$":
            if body[index:index + 2] != "$$":
                raise ValueError("unexpected compiler dependency Make variable")
            word.append("$")
            index += 1
        elif character.isspace():
            if word:
                paths.append(Path("".join(word)).resolve())
                word = []
        else:
            word.append(character)
        index += 1
    if word:
        paths.append(Path("".join(word)).resolve())
    return paths


def macro_profile(macros):
    target = {"__x86_64__", "__SIZEOF_LONG__", "__SIZEOF_POINTER__"}
    return {k: v for k, v in macros.items() if k.startswith("CONFIG_") or k in target}


def input_snapshot(paths):
    result = {}
    for path in sorted(paths):
        before = path.stat()
        digest = upstream.digest(path)
        after = path.stat()
        fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
        if any(getattr(before, field) != getattr(after, field) for field in fields):
            raise ValueError("compiler inputs changed during bounds generation")
        result[str(path)] = {field: getattr(after, field) for field in fields}
        result[str(path)]["sha256"] = digest
    return result


def compiler_command(compiler):
    command = shlex.split(compiler)
    if not command:
        raise ValueError("compiler command is empty")
    executable = shutil.which(command[0])
    if executable is None:
        raise ValueError("compiler executable was not found: " + command[0])
    return command, Path(executable).resolve()


def checked_snapshot(paths, command, compiler_path):
    if compiler_command(shlex.join(command))[1] != compiler_path:
        raise ValueError("compiler inputs changed during bounds generation")
    result = input_snapshot(paths)
    if compiler_command(shlex.join(command))[1] != compiler_path:
        raise ValueError("compiler inputs changed during bounds generation")
    return result


def command_stamp(path, compiler, flags, source_dir, archive):
    """Record build command changes without verifying or extracting sources."""
    path = path.resolve()
    source_dir = source_dir.resolve()
    archive = archive.resolve()
    command, compiler_path = compiler_command(compiler)
    protected = {archive, compiler_path, Path(__file__).resolve(),
                 Path(upstream.__file__).resolve(), (upstream.HERE / "upstream.json").resolve()}
    if path in protected:
        raise ValueError("command stamp overlaps protected inputs")
    if path == source_dir or source_dir in path.parents:
        raise ValueError("command stamp must be outside the verified import")
    flags = native_flags(flags)
    state = compiler_path.stat()
    fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
    identity = {field: getattr(state, field) for field in fields}
    previous = None
    if path.exists():
        try:
            previous = json.loads(path.read_text())
        except (ValueError, UnicodeError):
            pass
    previous_hash = previous.get("compiler_sha256") if isinstance(previous, dict) else None
    if (isinstance(previous, dict) and previous.get("compiler_path") == str(compiler_path)
            and previous.get("compiler_state") == identity
            and isinstance(previous_hash, str) and re.fullmatch(r"[0-9a-f]{64}", previous_hash)):
        compiler_hash = previous_hash
    else:
        snapshot = checked_snapshot({compiler_path}, command, compiler_path)[str(compiler_path)]
        compiler_hash = snapshot.pop("sha256")
        identity = snapshot
    if compiler_command(shlex.join(command))[1] != compiler_path:
        raise ValueError("compiler inputs changed during command stamp generation")
    after = compiler_path.stat()
    if any(getattr(after, field) != identity[field] for field in fields):
        raise ValueError("compiler inputs changed during command stamp generation")
    metadata = {"compiler": [str(compiler_path)] + command[1:],
                "compiler_path": str(compiler_path), "compiler_state": identity,
                "compiler_sha256": compiler_hash, "flags": flags}
    publish(path, (json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode())
    return metadata


def publish(path, data):
    """Replace one file atomically; unchanged bytes retain their timestamp."""
    if path.exists() and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".bounds-publish-", dir=path.parent,
                                         delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def generate(source_dir, archive, output, depfile, provenance, compiler, flags):
    source_dir = source_dir.resolve()
    archive = archive.resolve()
    output = output.resolve()
    depfile = depfile.resolve()
    provenance = provenance.resolve()
    command, compiler_path = compiler_command(compiler)
    pin = (upstream.HERE / "upstream.json").resolve()
    generator = Path(__file__).resolve()
    verifier = Path(upstream.__file__).resolve()
    protected = {archive, pin, generator,
                 verifier, compiler_path}
    destinations = {output, depfile, provenance}
    if len(destinations) != 3 or destinations & protected:
        raise ValueError("bounds outputs overlap each other or protected inputs")
    if any(p == source_dir or source_dir in p.parents for p in destinations):
        raise ValueError("bounds outputs must be outside the verified import")
    flags = native_flags(flags)
    protected_state = checked_snapshot(protected, command, compiler_path)
    if protected_state[str(archive)]["sha256"] != upstream.PIN["sha256"]:
        raise ValueError("archive SHA256 differs from upstream.json")
    if json.loads(pin.read_text()) != upstream.PIN:
        raise ValueError("compiler inputs changed during bounds generation")
    upstream.verify(source_dir)
    source_bytes = extract_source(archive)
    version = run_compiler(command + ["--version"])
    if checked_snapshot(protected, command, compiler_path) != protected_state:
        raise ValueError("compiler inputs changed during bounds generation")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".bounds-build-", dir=output.parent) as work:
        work = Path(work)
        source = work / "bounds.c"
        source.write_bytes(source_bytes)
        preprocessing_dependencies = work / "preprocess.d"
        preprocess = command + flags + ["-MD", "-MF", str(preprocessing_dependencies),
                                         "-MQ", str(output), "-E", "-dM", str(source)]
        macros = configuration(run_compiler(preprocess))
        preliminary_inputs = set(dependency_paths(preprocessing_dependencies.read_text(), output))
        if destinations & preliminary_inputs:
            raise ValueError("bounds outputs overlap discovered compiler inputs")
        initial_state = checked_snapshot((preliminary_inputs - {source}) | protected,
                                         command, compiler_path)
        if any(initial_state[path] != state for path, state in protected_state.items()):
            raise ValueError("compiler inputs changed during bounds generation")
        input_hashes = {p: state["sha256"] for p, state in initial_state.items()}
        assembly = work / "bounds.s"
        dependency = work / "bounds.d"
        compile_command = command + flags + ["-MD", "-MF", str(dependency),
                                              "-MQ", str(output), "-S", str(source),
                                              "-o", str(assembly)]
        run_compiler(compile_command)
        header, values = offsets(assembly.read_text(), macros)
        dependency_text = dependency.read_text()
        inputs = set(dependency_paths(dependency_text, output))
        if destinations & inputs:
            raise ValueError("bounds outputs overlap discovered compiler inputs")
        if (inputs != preliminary_inputs or
                checked_snapshot((inputs - {source}) | protected, command,
                                 compiler_path) != initial_state):
            raise ValueError("compiler inputs changed during bounds generation")
        # Discovery necessarily precedes the first input hashes. Recheck the
        # actual macro profile too: an edit in that earlier window must not
        # leave old CONFIG metadata describing assembly built with new flags.
        final_macros = configuration(run_compiler(preprocess))
        final_inputs = set(dependency_paths(preprocessing_dependencies.read_text(), output))
        if macro_profile(final_macros) != macro_profile(macros):
            raise ValueError("preprocessed configuration changed during bounds generation")
        if (final_inputs != inputs or
                checked_snapshot((final_inputs - {source}) | protected, command,
                                 compiler_path) != initial_state):
            raise ValueError("compiler inputs changed during bounds generation")
        dep = dependencies(dependency_text, source, output,
                           [archive, upstream.HERE / "upstream.json",
                            Path(__file__).resolve(), Path(upstream.__file__).resolve(),
                            compiler_path])
        metadata = {
            "scope": "Compiler-derived bounds only; no Linux page or DMA runtime is supplied",
            "linux_version": upstream.PIN["version"],
            "archive": str(archive), "archive_sha256": protected_state[str(archive)]["sha256"],
            "manifest_sha256": upstream.PIN["manifest_sha256"],
            "source_sha256": digest_bytes(source_bytes),
            "generator_sha256": protected_state[str(generator)]["sha256"],
            "verifier_sha256": protected_state[str(verifier)]["sha256"],
            "pin_sha256": protected_state[str(pin)]["sha256"],
            "header_sha256": digest_bytes(header), "dependency_sha256": digest_bytes(dep),
            "assembly_sha256": upstream.digest(assembly),
            "compiler": command, "compiler_path": str(compiler_path),
            "compiler_sha256": protected_state[str(compiler_path)]["sha256"], "compiler_version": version,
            "input_sha256": input_hashes,
            "input_state": initial_state,
            "input_validation": "Repeated profile/dependency/hash/file-state checks; "
                                "caller must isolate mutable inputs. No transactional "
                                "snapshot or ABA immunity is claimed.",
            "flags": flags, "configuration": {k: v for k, v in macros.items()
                                                if k.startswith("CONFIG_")},
            "target": {k: macros[k] for k in ("__x86_64__", "__SIZEOF_LONG__",
                                               "__SIZEOF_POINTER__")},
            "bounds": values,
        }
        # No output is published until every verification/parse step succeeds.
        # Header publication is the final atomic marker, not a multifile commit.
        publish(depfile, dep)
        publish(provenance, (json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode())
        publish(output, header)
    return metadata


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path,
                        default=upstream.DEFAULT / ("linux-" + upstream.PIN["version"]))
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--command-stamp", type=Path,
                        help="record compiler/flags only, without source verification or compilation")
    parser.add_argument("--depfile", type=Path)
    parser.add_argument("--provenance", type=Path)
    parser.add_argument("--cc", default="clang")
    parser.add_argument("flags", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    flags = args.flags[1:] if args.flags[:1] == ["--"] else args.flags
    try:
        if args.command_stamp is not None:
            if args.output is not None or args.depfile is not None or args.provenance is not None:
                raise ValueError("command stamp mode does not accept generated output paths")
            command_stamp(args.command_stamp, args.cc, flags, args.source_dir,
                          args.archive or args.source_dir.parent /
                          ("linux-" + upstream.PIN["version"] + ".tar.xz"))
            return 0
        if args.output is None:
            raise ValueError("--output or --command-stamp is required")
        metadata = generate(args.source_dir,
                            args.archive or args.source_dir.parent /
                            ("linux-" + upstream.PIN["version"] + ".tar.xz"),
                            args.output, args.depfile or Path(str(args.output) + ".d"),
                            args.provenance or Path(str(args.output) + ".json"),
                            args.cc, flags)
        print("Generated " + str(args.output) + " from Linux " + metadata["linux_version"])
        return 0
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        print("Linux bounds generation failed: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
