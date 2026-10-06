#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test original Linux CSD compiler ABI without supplying an SMP runtime.

The production x86 profile's current include blockers are recorded separately
from a private, declaration-only prerequisite profile. ARM initializer tests
use the original CONFIG_SMP=n branch solely for the unconditional 64-bit CSD
records; exact archived ARM SMP architecture closure is probed separately.
No CSD structures, callback interfaces or runtime implementations are replaced.
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
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "kernel/linuxkpi"
sys.path.insert(0, str(HERE))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


audit = load("smp_type_audit", HERE / "audit.py")
bounds_generator = load("smp_type_bounds", HERE / "generate-bounds.py")

NODE = r'''
#include <linux/smp_types.h>
#include <linux/llist.h>
_Static_assert(sizeof(struct llist_node) == 8, "original intrusive link");
_Static_assert(sizeof(struct __call_single_node) == 16, "original CSD node");
_Static_assert(_Alignof(struct __call_single_node) == 8, "original node alignment");
_Static_assert(offsetof(struct __call_single_node, llist) == 0, "original link offset");
_Static_assert(offsetof(struct __call_single_node, u_flags) == 8, "original flags offset");
_Static_assert(offsetof(struct __call_single_node, a_flags) == 8, "original atomic union");
_Static_assert(offsetof(struct __call_single_node, src) == 12, "original source offset");
_Static_assert(offsetof(struct __call_single_node, dst) == 14, "original target offset");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct __call_single_node *)0)->u_flags), unsigned int), "flag type");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct __call_single_node *)0)->a_flags), atomic_t), "atomic flag type");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct __call_single_node *)0)->llist.next), struct llist_node *), "link type");
_Static_assert(CSD_FLAG_LOCK == 1 && CSD_TYPE_ASYNC == 0 && CSD_TYPE_SYNC == 0x10 &&
    CSD_TYPE_IRQ_WORK == 0x20 && CSD_TYPE_TTWU == 0x30 && CSD_FLAG_TYPE_MASK == 0xf0,
    "original call-single flag values");
_Static_assert(IRQ_WORK_PENDING == 1 && IRQ_WORK_BUSY == 2 && IRQ_WORK_LAZY == 4 &&
    IRQ_WORK_HARD_IRQ == 8 && IRQ_WORK_CLAIMED == 3, "original IRQ-work flags");
unsigned long csd_node_bytes(void) { return sizeof(struct __call_single_node); }
'''

LAYOUT = r'''
_Static_assert(CONFIG_64BIT == 1, "64-bit record profile");
_Static_assert(sizeof(struct __call_single_data) == 32 && sizeof(call_single_data_t) == 32,
    "original CSD width");
_Static_assert(_Alignof(struct __call_single_data) == 8 && _Alignof(call_single_data_t) == 32,
    "original ordinary struct versus cacheline typedef alignment");
_Static_assert(offsetof(struct __call_single_data, node) == 0 &&
    offsetof(struct __call_single_data, func) == 16 &&
    offsetof(struct __call_single_data, info) == 24, "original data offsets");
_Static_assert(__builtin_types_compatible_p(smp_call_func_t, void (*)(void *)),
    "original callback ABI");
_Static_assert(__builtin_types_compatible_p(smp_cond_func_t, bool (*)(int, void *)),
    "original sender condition ABI");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct __call_single_data *)0)->func), smp_call_func_t), "function field");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct __call_single_data *)0)->info), void *), "borrowed argument field");
static void callback(void *info) { (void)info; }
static int sentinel;
static call_single_data_t file_initialized = CSD_INIT(callback, &sentinel);
unsigned long csd_record_bytes(void) { return sizeof(file_initialized); }
bool csd_file_initializer_valid(void) {
    return !file_initialized.node.llist.next && !file_initialized.node.u_flags &&
        !file_initialized.node.src && !file_initialized.node.dst &&
        file_initialized.func == callback && file_initialized.info == &sentinel;
}
unsigned long csd_array_stride(void) { call_single_data_t pair[2]; return
    (unsigned long)((char *)&pair[1] - (char *)&pair[0]); }
'''

RUNTIME = r'''
extern void csd_model_check(bool passed, int line);
#define CHECK(x) csd_model_check((x), __LINE__)
static unsigned function_evaluations, info_evaluations, target_evaluations;
static void *expected_info;
static call_single_data_t target;
static smp_call_func_t select_function(void) { function_evaluations++; return callback; }
static void *select_info(void) { info_evaluations++; return expected_info; }
static call_single_data_t *select_target(void) { target_evaluations++; return &target; }
static void check_csd(const struct __call_single_data *csd) {
    CHECK(csd->node.llist.next == NULL); CHECK(csd->node.u_flags == 0);
    CHECK(csd->node.src == 0); CHECK(csd->node.dst == 0);
    CHECK(csd->func == callback); CHECK(csd->info == expected_info);
}
void csd_test_initializers(void *info, unsigned iterations) {
    expected_info = info;
    CHECK(csd_file_initializer_valid()); CHECK(csd_array_stride() == 32);
    for (unsigned i = 0; i < iterations; i++) {
        function_evaluations = info_evaluations = target_evaluations = 0;
        struct __call_single_data local = CSD_INIT(select_function(), select_info());
        CHECK(function_evaluations == 1 && info_evaluations == 1); check_csd(&local);
        target.node.llist.next = &target.node.llist; target.node.u_flags = ~0u;
        target.node.src = 0xffff; target.node.dst = 0xffff;
        target.func = NULL; target.info = NULL;
        INIT_CSD(select_target(), select_function(), select_info());
        CHECK(function_evaluations == 2 && info_evaluations == 2 && target_evaluations == 1);
        check_csd(&target);
        struct __call_single_data nulls = CSD_INIT(NULL, NULL);
        CHECK(!nulls.node.llist.next && !nulls.node.u_flags && !nulls.node.src &&
              !nulls.node.dst && !nulls.func && !nulls.info);
        INIT_CSD(&nulls, callback, info); check_csd(&nulls);
    }
}
'''

REFERENCE = r'''
int (*single_reference)(int, smp_call_func_t, void *, int) = smp_call_function_single;
int (*async_reference)(int, struct __call_single_data *) = smp_call_function_single_async;
void (*many_reference)(const struct cpumask *, smp_call_func_t, void *, bool) = smp_call_function_many;
void (*all_reference)(smp_call_func_t, void *, int) = smp_call_function;
void (*conditional_reference)(smp_cond_func_t, smp_call_func_t, void *, bool,
    const struct cpumask *) = on_each_cpu_cond_mask;
void (*queue_reference)(int, struct llist_node *) = __smp_call_single_queue;
void call_original_wrappers(smp_call_func_t function, smp_cond_func_t condition,
    void *info, const struct cpumask *mask) {
    on_each_cpu(function, info, 1); on_each_cpu_mask(mask, function, info, true);
    on_each_cpu_cond(condition, function, info, true);
}
void call_original_arch_ipi(int cpu, const struct cpumask *mask) {
    arch_send_call_function_single_ipi(cpu); arch_send_call_function_ipi_mask(mask);
}
'''

DRIVER = r'''
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
void csd_test_initializers(void *, unsigned);
static unsigned assertions;
void csd_model_check(bool passed, int line) {
    assertions++; if (!passed) { fprintf(stderr, "Original CSD assertion line %d\n",line); abort(); }
}
int main(void) {
    int argument = 42;
    csd_test_initializers(&argument, 10000); csd_test_initializers(NULL, 10000);
    printf("PASS: %u original CSD initializer assertions\n",assertions); return 0;
}
'''


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def invoke(argv, log, expect_success=True, env=None):
    result = subprocess.run(argv, capture_output=True, text=True, env=env, timeout=180)
    Path(log).write_text(json.dumps(argv) + "\n" + result.stdout + result.stderr)
    if expect_success and result.returncode:
        raise AssertionError("Compiler/runtime failed; see " + str(log))
    return result


def macro(source, name):
    lines = source.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if re.match(r"^#define[ \t]+" + name + r"\(", line):
            result = line
            while line.rstrip().endswith("\\"):
                index += 1
                line = lines[index]
                result += line
            return result
    raise AssertionError("Missing exact pinned declaration macro: " + name)


def flags(linux, include, target, standard):
    result = ["--target=" + target, "-std=" + standard, "-O2", "-ffreestanding", "-fwrapv", "-nostdinc",
        "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-Wno-unused-function", "-D__KERNEL__",
        "-include", "linux/kconfig.h", "-include", str(linux / "include/linux/compiler_types.h"),
        "-isystem", str(ROOT / "kernel/freestnd-c-hdrs")]
    for path in (include, HERE / "include", ROOT / "kernel/c", linux / "include", linux / "include/uapi",
                 linux / "arch/x86/include", linux / "arch/x86/include/uapi"):
        result += ["-I", str(path)]
    return result


def imports(obj):
    executable = os.environ.get("LLVM_NM") or shutil.which("llvm-nm") or "/opt/homebrew/opt/llvm/bin/llvm-nm"
    output = subprocess.check_output([executable, "--undefined-only", str(obj)], text=True)
    return output, set(re.findall(r"\bU\s+(\S+)", output))


def run(keep_dir):
    temporary = tempfile.TemporaryDirectory(prefix="vinix-smp-types-") if keep_dir is None else None
    work = Path(temporary.name) if temporary else Path(keep_dir).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    linux = Path(os.environ.get("LINUXKPI_SOURCE_DIR", bounds_generator.upstream.DEFAULT /
        ("linux-" + bounds_generator.upstream.PIN["version"]))).resolve()
    archive = linux.parent / ("linux-" + bounds_generator.upstream.PIN["version"] + ".tar.xz")
    cc = os.environ.get("CC", "clang")
    compiler = shlex.split(cc)
    observed = (Path(__file__), HERE / "include/generated/autoconf.h", HERE / "include/linux/smp.h",
        HERE / "include/asm/percpu.h", linux / "include/linux/smp.h", linux / "include/linux/smp_types.h",
        linux / "include/linux/llist.h", linux / "arch/x86/include/asm/percpu.h")
    initial = {str(path): sha(path) for path in observed}
    try:
        include = work / "include"
        audit.generate_headers(include)
        bounds = include / "generated/bounds.h"
        base_flags = flags(linux, include, "x86_64-unknown-none", "gnu11")
        provenance = bounds_generator.generate(linux, archive, bounds, Path(str(bounds)+".d"),
            Path(str(bounds)+".json"), cc, base_flags)
        reference = work / "reference"
        reference_hashes = {}
        # Read the pinned archive outside its verified import. No tar paths or
        # symlinks are unpacked; only selected regular-file bytes are copied.
        with tarfile.open(archive, "r:xz") as tar:
            for member in tar:
                relative = member.name.removeprefix("linux-" + bounds_generator.upstream.PIN["version"] + "/")
                if member.isfile() and (relative.startswith("arch/arm64/include/") or
                        relative in ("scripts/Makefile.extrawarn", "arch/x86/Kconfig")):
                    content = tar.extractfile(member).read()
                    path = reference / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(content)
                    reference_hashes[relative] = hashlib.sha256(content).hexdigest()
        extrawarn = (reference / "scripts/Makefile.extrawarn").read_text()
        if not re.search(r"^KBUILD_CFLAGS\s*\+=\s*-Wno-sign-compare\b", extrawarn, re.M):
            raise AssertionError("Pinned Linux does not supply the proposed sign-compare policy")
        declaration = macro((linux / "arch/x86/include/asm/percpu.h").read_text(),
            "DECLARE_EARLY_PER_CPU_READ_MOSTLY")
        preamble = "#define CONFIG_HAVE_ARCH_WITHIN_STACK_FRAMES 1\n#ifndef DECLARE_EARLY_PER_CPU_READ_MOSTLY\n" + declaration + "#endif\n"
        full_header = '#include "' + str(linux / "include/linux/smp.h") + '"\n'
        (work / "prerequisites.h").write_text(preamble)
        results = []
        for standard in ("gnu99", "gnu11"):
            for target in ("x86_64-unknown-none", "aarch64-unknown-none"):
                tag = standard + "-" + target
                current_flags = flags(linux, include, target, standard)
                profiles = [("node", NODE, current_flags)]
                if target.startswith("x86"):
                    profiles += [("full-prerequisite", preamble + full_header + NODE + LAYOUT,
                                  current_flags + ["-Wno-sign-compare"])]
                else:
                    profiles += [("generic-record-SMP-off", "#undef CONFIG_SMP\n" + full_header + NODE + LAYOUT,
                                  current_flags)]
                for profile, text, selected_flags in profiles:
                    source = work / (tag + "-" + profile + ".c")
                    source.write_text(text)
                    obj = source.with_suffix(".o")
                    dep = source.with_suffix(".d")
                    argv = compiler + selected_flags + ["-MD", "-MF", str(dep), "-MQ", str(obj),
                        "-c", str(source), "-o", str(obj)]
                    invoke(argv, source.with_suffix(".log"))
                    output, symbols = imports(obj)
                    if output.strip():
                        raise AssertionError("Cold type/initializer object unexpectedly imports runtime: " + output)
                    inputs = bounds_generator.dependency_paths(dep.read_text(), obj)
                    for original in (linux / "include/linux/smp_types.h", linux / "include/linux/llist.h"):
                        if original.resolve() not in inputs:
                            raise AssertionError("Actual original dependency missing: " + str(original))
                    if profile != "node" and (linux / "include/linux/smp.h").resolve() not in inputs:
                        raise AssertionError("CSD definitions were not supplied by the original full header")
                    results.append({"standard": standard, "target": target, "profile": profile, "argv": argv,
                        "object_sha256": sha(obj), "runtime_imports": output,
                        "input_sha256": {str(path): sha(path) for path in inputs}})
            # Production profile remains a separate result, whether future
            # genuine declarations make it pass or current prerequisites fail.
            baseline = work / (standard + "-production-header.c")
            baseline.write_text(full_header + LAYOUT)
            outcome = invoke(compiler + flags(linux, include, "x86_64-unknown-none", standard) +
                ["-Wno-sign-compare", "-fsyntax-only", str(baseline)], baseline.with_suffix(".log"), False)
            results.append({"standard": standard, "profile": "actual-production-original-full-header",
                "exit_code": outcome.returncode, "diagnostics": outcome.stderr})
            ref_source = work / (standard + "-runtime-references.c")
            ref_source.write_text(preamble + full_header + REFERENCE)
            ref_obj = ref_source.with_suffix(".o")
            invoke(compiler + flags(linux, include, "x86_64-unknown-none", standard) + ["-Wno-sign-compare",
                "-c", str(ref_source), "-o", str(ref_obj)], ref_source.with_suffix(".log"))
            output, symbols = imports(ref_obj)
            wanted = {"smp_call_function_single", "smp_call_function_single_async", "smp_call_function_many",
                "smp_call_function", "on_each_cpu_cond_mask", "__smp_call_single_queue", "__cpu_online_mask", "smp_ops"}
            if symbols != wanted:
                raise AssertionError("Original unresolved runtime references changed: " + output)
            results.append({"standard": standard, "profile": "genuine-unresolved-runtime-references",
                "object_sha256": sha(ref_obj), "runtime_imports": output})
            wrong = work / (standard + "-wrong-callback.c")
            wrong.write_text(preamble + full_header +
                "static void wrong(int argument) {(void)argument;}\ncall_single_data_t reject = CSD_INIT(wrong, NULL);\n")
            rejected = invoke(compiler + flags(linux, include, "x86_64-unknown-none", standard) +
                ["-Wno-sign-compare", "-fsyntax-only", str(wrong)], wrong.with_suffix(".log"), False)
            if not rejected.returncode or "incompatible function pointer" not in rejected.stderr:
                raise AssertionError("Wrong callback type was not rejected by actual CSD_INIT")
            # Execute the original unconditional initializer macros on the host
            # with no libc/Linux type collision in the production core TU.
            host_source = work / (standard + "-host.c")
            # Mach-O cannot represent Linux's ELF section names even on an
            # unused extern declaration. Omit only section-placement metadata
            # in this private host TU; original aligned CSD types/macros and
            # all native ELF compiler/reference probes remain unchanged.
            host_annotation = "#undef __section\n#define __section(name)\n" if sys.platform == "darwin" else ""
            host_source.write_text("#undef CONFIG_SMP\n" + host_annotation + full_header + NODE + LAYOUT + RUNTIME)
            host_obj = host_source.with_suffix(".o")
            host_flags = flags(linux, include, "arm64-apple-macos" if sys.platform == "darwin" and os.uname().machine == "arm64"
                else ("x86_64-apple-macos" if sys.platform == "darwin" else "x86_64-unknown-linux-gnu"), standard)
            sanitizer = ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
            invoke(compiler + host_flags + sanitizer + ["-c", str(host_source), "-o", str(host_obj)], host_source.with_suffix(".log"))
            driver = work / (standard + "-driver.c"); driver.write_text(DRIVER)
            executable = work / (standard + "-runtime")
            invoke(compiler + ["-std=" + standard, "-Wall", "-Wextra", "-Werror", *sanitizer,
                str(driver), str(host_obj), "-o", str(executable)], work / (standard + "-link.log"))
            runtime = invoke([str(executable)], work / (standard + "-run.log"), env={**os.environ,
                "UBSAN_OPTIONS": "halt_on_error=1", "ASAN_OPTIONS": "detect_stack_use_after_return=1"})
            if runtime.stderr:
                raise AssertionError("Unexpected sanitizer diagnostic: " + runtime.stderr)
            results.append({"standard": standard, "profile": "host-original-initializers-SMP-off",
                "object_sha256": sha(host_obj), "output": runtime.stdout.strip(),
                "host_only_placement_annotation": host_annotation})
            print(standard + ": " + runtime.stdout.strip())
        # Exact ARM architecture selection is diagnostic only. No fabricated
        # generated cpucaps/config or runtime functions are supplied to close it.
        arm_include = work / "arm-profile"
        (arm_include / "generated").mkdir(parents=True)
        (arm_include / "generated/autoconf.h").write_text(
            "#define CONFIG_ARM64 1\n#define CONFIG_64BIT 1\n#define CONFIG_SMP 1\n#define CONFIG_NR_CPUS 256\n"
            "#define CONFIG_MMU 1\n#define CONFIG_ARM64_4K_PAGES 1\n#define CONFIG_ARM64_PAGE_SHIFT 12\n"
            "#define CONFIG_PGTABLE_LEVELS 4\n#define CONFIG_THREAD_INFO_IN_TASK 1\n")
        arm_source = work / "arm-original-smp-closure.c"; arm_source.write_text(full_header + LAYOUT)
        arm_flags = flags(linux, include, "aarch64-unknown-none", "gnu11")
        argv = compiler + ["-I", str(arm_include), "-I", str(reference / "arch/arm64/include"),
            "-I", str(reference / "arch/arm64/include/uapi"), *arm_flags, "-fsyntax-only", str(arm_source)]
        arm = invoke(argv, work / "arm-original-smp-closure.log", False)
        results.append({"profile": "exact-archived-ARM-SMP-architecture-closure", "argv": argv,
            "exit_code": arm.returncode, "diagnostics": arm.stderr,
            "scope": "Diagnostic only; missing generated architecture/service dependencies remain unsupported."})
        if initial != {str(path): sha(path) for path in observed}:
            raise AssertionError("Observed production/test sources changed during isolated checks")
        report = {"scope": __doc__, "source_sha256": initial, "bounds": provenance,
            "exact_early_declaration_macro": declaration, "reference_sha256": reference_hashes,
            "pinned_sign_compare_policy": "scripts/Makefile.extrawarn: KBUILD_CFLAGS += -Wno-sign-compare",
            "results": results}
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-dir", type=Path)
    arguments = parser.parse_args()
    run(arguments.keep_dir)
