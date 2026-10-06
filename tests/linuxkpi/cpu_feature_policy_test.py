#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run the unchanged native MOVDIR boot policy with explicit host observers.

Only CPU membership, leaf-one CPUID, atomic publication and fatal handling are
modeled. The real policy and real public cpu_has body run unchanged; genuine
Linux feature IDs and public macros are compiled. This does not execute MOVDIR,
boot APs, establish kernel GS, support hotplug, or implement other word-16 bits.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "kernel/linuxkpi/cpu_features_amd64.v"
BRIDGE = ROOT / "kernel/linuxkpi/bridge_amd64.v"
LOCAL = ROOT / "kernel/x86/cpu/local/local.v"
HERE = ROOT / "kernel/linuxkpi"
LINUX = Path(os.environ.get("LINUXKPI_SOURCE_DIR", ROOT /
    "third_party/linux-i915/linux-6.6.157")).resolve()

OBSERVERS = r'''
@[has_globals]
module linuxkpi
import katomic
#include "policy_model.h"
fn C.policy_model_configure(voidptr, voidptr, i64)
pub struct Local {
pub mut:
    cpu_number u64
    online u64
    directstore_ecx u32
}
__global cpu_locals []&Local
@[export: 'policy_test_configure']
fn test_configure(members voidptr, count i64) {
    C.policy_model_configure(unsafe { &cpu_locals }, members, count)
}
@[export: 'policy_test_reset']
fn test_reset() {
    boot_directstore_bits = 0
    boot_directstore_count = 0
    boot_directstore_ready = 0
}
@[export: 'policy_test_seed']
fn test_seed(bits u32, count u32, ready u32) {
    boot_directstore_bits = bits
    boot_directstore_count = count
    boot_directstore_ready = ready
}
@[export: 'policy_test_initialize']
fn test_initialize() { initialise_cpu_features() }
@[export: 'policy_test_state']
fn test_state(field u32) u32 {
    if field == 0 { return boot_directstore_bits }
    if field == 1 { return boot_directstore_count }
    return katomic.load(&boot_directstore_ready)
}
'''

ATOMIC_OBSERVER = r'''
module katomic
#include "policy_model.h"
fn C.policy_model_load(&u32) u32
fn C.policy_model_load_u64(&u64) u64
fn C.policy_model_store(&u32, u32)
pub fn load[T](value &T) T {
    if sizeof(T) == 8 { return T(C.policy_model_load_u64(unsafe { &u64(value) })) }
    return T(C.policy_model_load(unsafe { &u32(value) }))
}
pub fn store[T](mut value T, item T) {
    C.policy_model_store(unsafe { &u32(value) }, u32(item))
}
'''

CPU_OBSERVER = r'''
module cpu
#include "policy_model.h"
fn C.policy_model_cpuid(u32, u32, &u32, &u32) bool
pub fn cpuid(leaf u32, subleaf u32) (bool, u32, u32, u32, u32) {
    mut ecx := u32(0)
    mut edx := u32(0)
    ok := C.policy_model_cpuid(leaf, subleaf, unsafe { &ecx }, unsafe { &edx })
    return ok, 0, 0, ecx, edx
}
'''

FATAL_OBSERVER = r'''
module lib
#include "policy_model.h"
@[noreturn]
fn C.policy_model_panic(&char)
@[noreturn]
pub fn kpanic(frame voidptr, message &char) { C.policy_model_panic(message) }
'''

MODEL_HEADER = r'''
#ifndef VINIX_POLICY_MODEL_H
#define VINIX_POLICY_MODEL_H
#include <stdbool.h>
#include <stdint.h>
uint32_t policy_model_load(const uint32_t *value);
uint64_t policy_model_load_u64(const uint64_t *value);
void policy_model_store(uint32_t *value, uint32_t item);
void policy_model_configure(void *slot, void *members, int64_t count);
bool policy_model_cpuid(uint32_t leaf, uint32_t subleaf, uint32_t *ecx, uint32_t *edx);
void policy_model_panic(const char *message) __attribute__((noreturn));
/* Borrowed pointer-table indexing is observed; no array growth is performed. */
void *array_get(Array value, int64_t index);
#endif
'''

C_TEST = r'''
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include <pthread.h>
#include <sched.h>
#include "model_types.h"
#include "policy_model.h"
unsigned cpu_policy_feature_id(unsigned);
bool cpu_policy_boot_query(unsigned), cpu_policy_static_query(unsigned);
bool vinix_linuxkpi_cpu_has(unsigned);
#define X86_FEATURE_MOVDIRI cpu_policy_feature_id(0)
#define X86_FEATURE_MOVDIR64B cpu_policy_feature_id(1)
#define X86_FEATURE_XMM4_1 cpu_policy_feature_id(2)
#define boot_cpu_has cpu_policy_boot_query
#define static_cpu_has cpu_policy_static_query
void policy_test_configure(void *, int64_t);
void policy_test_reset(void);
void policy_test_seed(uint32_t, uint32_t, uint32_t);
void policy_test_initialize(void);
uint32_t policy_test_state(uint32_t);

#define MASK ((UINT32_C(1) << 27) | (UINT32_C(1) << 28))
#define CHECK(x) do { __atomic_fetch_add(&assertions, 1, __ATOMIC_RELAXED); \
    if (!(x)) { fprintf(stderr,"CPU policy assertion line %d: %s\n",__LINE__,#x); abort(); } } while(0)
static linuxkpi__Local records[257], baseline[257];
static linuxkpi__Local *members[257];
static uint64_t assertions;
static unsigned cpuid_count, stores, loads, successful_publications;
static bool expect_panic;
static jmp_buf panic_target;
static char panic_message[160];
static _Thread_local uint64_t caller_flags, caller_affinity;
static _Thread_local uint32_t caller_preempt, caller_cpu;
static bool cpuid_available = true;
static uint32_t leaf_one_ecx, leaf_one_edx;

void policy_model_configure(void *slot, void *member_data, int64_t count) {
    Array *value = slot;
    memset(value,0,sizeof(*value));
    value->data = member_data; value->len = count; value->cap = count;
    value->element_size = sizeof(linuxkpi__Local *);
}
void *array_get(Array value, int64_t index) {
    CHECK(index >= 0 && index < value.len && value.data != NULL);
    CHECK(value.element_size == (int)sizeof(linuxkpi__Local *));
    return (char *)value.data + (size_t)index * sizeof(linuxkpi__Local *);
}

uint32_t policy_model_load(const uint32_t *value) {
    __atomic_fetch_add(&loads, 1, __ATOMIC_RELAXED);
    return __atomic_load_n(value, __ATOMIC_ACQUIRE);
}
uint64_t policy_model_load_u64(const uint64_t *value) {
    __atomic_fetch_add(&loads, 1, __ATOMIC_RELAXED);
    return __atomic_load_n(value, __ATOMIC_ACQUIRE);
}
void policy_model_store(uint32_t *value, uint32_t item) {
    /* This is publication observation, not a second reduction algorithm. */
    CHECK(item == 1);
    CHECK(policy_test_state(0) <= MASK && !(policy_test_state(0) & ~MASK));
    CHECK(policy_test_state(1) >= 1 && policy_test_state(1) <= 256);
    stores++; successful_publications++;
    __atomic_store_n(value, item, __ATOMIC_RELEASE);
}
bool policy_model_cpuid(uint32_t leaf, uint32_t subleaf, uint32_t *ecx, uint32_t *edx) {
    __atomic_fetch_add(&cpuid_count,1,__ATOMIC_RELAXED);
    CHECK(leaf == 1 && subleaf == 0);
    *ecx = leaf_one_ecx; *edx = leaf_one_edx;
    return cpuid_available;
}
void policy_model_panic(const char *message) {
    if (!expect_panic) { fprintf(stderr,"Unexpected policy panic: %s\n",message); abort(); }
    snprintf(panic_message, sizeof(panic_message), "%s", message);
    longjmp(panic_target, 1);
}
void *policy_unexpected_malloc(size_t size) { (void)size; abort(); }
void *policy_unexpected_calloc(size_t n, size_t size) { (void)n; (void)size; abort(); }
void *policy_unexpected_realloc(void *p, size_t size) { (void)p; (void)size; abort(); }
void policy_unexpected_free(void *p) { (void)p; abort(); }

static void configure(int64_t count) {
    policy_test_reset();
    memset(records, 0, sizeof(records));
    for (unsigned i = 0; i < 257; i++) {
        records[i].cpu_number = i;
        records[i].online = 1;
        records[i].directstore_ecx = MASK;
        members[i] = &records[i];
    }
    policy_test_configure(members, count);
    cpuid_count = stores = loads = successful_publications = 0;
}
static void expect_failure(bool initialize, unsigned feature, const char *text) {
    uint32_t before[3] = {policy_test_state(0),policy_test_state(1),policy_test_state(2)};
    memcpy(baseline, records, sizeof(records));
    unsigned prior_stores = stores, prior_cpuid = cpuid_count;
    expect_panic = true;
    if (!setjmp(panic_target)) {
        if (initialize) policy_test_initialize(); else (void)vinix_linuxkpi_cpu_has(feature);
        abort();
    }
    expect_panic = false;
    CHECK(strstr(panic_message, text) != NULL);
    for (unsigned i = 0; i < 3; i++) CHECK(policy_test_state(i) == before[i]);
    CHECK(memcmp(baseline, records, sizeof(records)) == 0);
    CHECK(stores == prior_stores && cpuid_count == prior_cpuid);
}
static void initialize_and_check(unsigned count, uint32_t expected) {
    memcpy(baseline, records, sizeof(records));
    policy_test_initialize();
    CHECK(policy_test_state(0) == expected);
    CHECK(policy_test_state(1) == count && policy_test_state(2) == 1);
    CHECK(stores == 1 && successful_publications == 1 && cpuid_count == 0);
    CHECK(memcmp(baseline, records, sizeof(records)) == 0);
    CHECK(boot_cpu_has(X86_FEATURE_MOVDIRI) == !!(expected & (UINT32_C(1)<<27)));
    CHECK(static_cpu_has(X86_FEATURE_MOVDIR64B) == !!(expected & (UINT32_C(1)<<28)));
    CHECK(cpuid_count == 0);
}
static void memberships(void) {
    static const unsigned counts[] = {1,2,4,64,65,256};
    for (unsigned n = 0; n < sizeof(counts)/sizeof(counts[0]); n++) {
        unsigned count = counts[n];
        for (unsigned pattern = 0; pattern < 4; pattern++) {
            configure(count);
            uint32_t expected = (pattern & 1 ? UINT32_C(1)<<27 : 0) |
                                (pattern & 2 ? UINT32_C(1)<<28 : 0);
            records[count-1].directstore_ecx = expected | ~MASK;
            initialize_and_check(count, expected);
            /* No later query may observe CPU-local feature replacement. */
            for (unsigned i = 0; i < count; i++) records[i].directstore_ecx = ~expected;
            CHECK(boot_cpu_has(X86_FEATURE_MOVDIRI) == !!(expected & (UINT32_C(1)<<27)));
            CHECK(static_cpu_has(X86_FEATURE_MOVDIR64B) == !!(expected & (UINT32_C(1)<<28)));
            expect_failure(true,0,"initialized twice");
        }
    }
    configure(256);
    records[17].directstore_ecx &= ~(UINT32_C(1)<<27);
    records[255].directstore_ecx &= ~(UINT32_C(1)<<28);
    initialize_and_check(256,0);
    configure(4); records[2].directstore_ecx = 0; initialize_and_check(4,0);
}
static void invalid_memberships(void) {
    static const int64_t invalid[] = {-1,0,257,INT32_MAX,INT64_MAX,INT64_C(0x100000001)};
    for (unsigned i = 0; i < sizeof(invalid)/sizeof(invalid[0]); i++) {
        configure(invalid[i]);
        /* Invalid bounds must reject before any array indexing. */
        policy_test_configure(NULL, invalid[i]);
        policy_test_seed(0x400,17,0);
        expect_failure(true,0,"invalid CPU feature policy membership");
    }
    for (unsigned position = 0; position < 256; position++) {
        configure(256); members[position] = NULL;
        expect_failure(true,0,"not acknowledged");
        configure(256); records[position].online = 0;
        expect_failure(true,0,"not acknowledged");
        configure(256); records[position].online = 2;
        expect_failure(true,0,"not acknowledged");
        configure(256); records[position].online = UINT64_C(0x100000001);
        expect_failure(true,0,"not acknowledged");
        configure(256); records[position].online = UINT64_MAX;
        expect_failure(true,0,"not acknowledged");
        configure(256); records[position].cpu_number = position + 1;
        expect_failure(true,0,"not acknowledged");
        configure(256); records[position].cpu_number = UINT64_C(0x100000000) + position;
        expect_failure(true,0,"not acknowledged");
    }
}
static void query_failures(void) {
    configure(4);
    expect_failure(false,X86_FEATURE_MOVDIRI,"not initialized");
    expect_failure(false,X86_FEATURE_MOVDIR64B,"not initialized");
    policy_test_seed(MASK,4,2);
    expect_failure(false,X86_FEATURE_MOVDIRI,"not initialized");
    expect_failure(false,X86_FEATURE_MOVDIR64B,"not initialized");
    policy_test_reset();
    for (unsigned phase = 0; phase < 2; phase++) {
        if (phase) initialize_and_check(4,MASK);
        for (unsigned bit = 0; bit < 32; bit++) {
            if (bit != 27 && bit != 28)
                expect_failure(false,16*32+bit,"unsupported CPU feature in word sixteen");
        }
    }
    /* Existing words retain the legacy leaf-one query scope. */
    leaf_one_ecx = UINT32_C(0xa5a536e9); leaf_one_edx = UINT32_C(0x693bc157);
    for (unsigned bit = 0; bit < 32; bit++) {
        CHECK(vinix_linuxkpi_cpu_has(bit) == !!(leaf_one_edx & (UINT32_C(1)<<bit)));
        CHECK(vinix_linuxkpi_cpu_has(4*32+bit) == !!(leaf_one_ecx & (UINT32_C(1)<<bit)));
    }
    CHECK(cpuid_count == 64);
    cpuid_available = false;
    CHECK(!vinix_linuxkpi_cpu_has(X86_FEATURE_XMM4_1));
    cpuid_available = true;
}
struct QueryActor { uint32_t expected; unsigned index; };
static void *query_actor(void *argument) {
    const struct QueryActor *actor = argument;
    caller_affinity = UINT64_C(0x8000000000000001) + actor->index;
    caller_preempt = actor->index + 3;
    for (unsigned round = 0; round < 20000; round++) {
        caller_cpu = (round * 17 + actor->index) % 256;
        caller_flags = UINT64_C(0x1234000000000046) | (round & 1 ? 0x200 : 0);
        uint64_t flags = caller_flags, affinity = caller_affinity;
        uint32_t preempt = caller_preempt, cpu = caller_cpu;
        CHECK(boot_cpu_has(X86_FEATURE_MOVDIRI) == !!(actor->expected & (UINT32_C(1)<<27)));
        CHECK(static_cpu_has(X86_FEATURE_MOVDIR64B) == !!(actor->expected & (UINT32_C(1)<<28)));
        CHECK(caller_flags == flags && caller_affinity == affinity);
        CHECK(caller_preempt == preempt && caller_cpu == cpu);
        if (!(round % 1024)) sched_yield();
    }
    return NULL;
}
static void concurrent_queries(void) {
    configure(256); records[169].directstore_ecx = UINT32_C(1)<<28;
    initialize_and_check(256,UINT32_C(1)<<28);
    pthread_t threads[8]; struct QueryActor actors[8];
    for (unsigned i = 0; i < 8; i++) {
        actors[i].expected = UINT32_C(1)<<28; actors[i].index = i;
        CHECK(pthread_create(&threads[i],NULL,query_actor,&actors[i]) == 0);
    }
    for (unsigned i = 0; i < 8; i++) CHECK(pthread_join(threads[i],NULL) == 0);
    CHECK(cpuid_count == 0 && stores == 1);
    CHECK(policy_test_state(0) == UINT32_C(1)<<28);
    CHECK(policy_test_state(1) == 256 && policy_test_state(2) == 1);
}
int main(void) {
    memberships(); invalid_memberships(); query_failures(); concurrent_queries();
    printf("PASS: %llu MOVDIR policy assertions\n", (unsigned long long)assertions);
    return 0;
}
'''


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def function(text, name):
    match = re.search(r"(?:@\[export: '[^']+'\]\n)?fn " + name + r"\([^\n]*\) [^\n]*\{", text)
    if not match:
        raise AssertionError("Missing actual function: " + name)
    depth = 1
    end = match.end()
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[match.start():end] + "\n"


def command(argv, log, timeout=120, env=None):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=timeout, env=env)
    Path(log).write_text(json.dumps(argv) + "\n" + result.stdout + result.stderr)
    if result.returncode:
        raise AssertionError("Command failed: see " + str(log))
    return result


def tool(name):
    return shutil.which(name) or str(Path("/opt/homebrew/opt/llvm/bin") / name)


def generated_prefix(raw):
    """Keep the real frozen-V builtin array descriptor, including i64 length."""
    record = re.search(r"struct array \{.*?\n\};",raw,re.S)
    local = re.search(r"struct linuxkpi__Local \{.*?\n\};",raw,re.S)
    tuple_record = re.search(r"struct multi_return_bool_u32_u32_u32_u32 \{.*?\n\};",raw,re.S)
    string = re.search(r"struct string \{.*?\n\};",raw,re.S)
    literal = re.search(r"^#define _S\(s\) [^\n]+",raw,re.M)
    if not all((record,local,tuple_record,string,literal)) or "i64 len;" not in record[0] or "u64 online;" not in local[0]:
        raise AssertionError("Missing actual native-width array/membership descriptors")
    constants="\n".join(re.findall(r"^#define linuxkpi__(?:directstore_mask|feature_movdiri|feature_movdir64b)[^\n]+",raw,re.M))
    declarations='''#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef uint8_t u8; typedef uint32_t u32; typedef uint64_t u64; typedef int64_t i64;
#define VNORETURN __attribute__((noreturn))
typedef struct string string;
typedef struct array array;
typedef array Array;
typedef struct linuxkpi__Local linuxkpi__Local;
typedef struct multi_return_bool_u32_u32_u32_u32 multi_return_bool_u32_u32_u32_u32;
'''+record[0]+"\n"+local[0]+"\n"+tuple_record[0]+"\n"+string[0]+"\n"+literal[0]+"\n"+constants+'''
void v_panic(string s);
Array linuxkpi__cpu_locals;
u32 linuxkpi__boot_directstore_bits, linuxkpi__boot_directstore_count, linuxkpi__boot_directstore_ready;
u32 katomic__load_T_u32(u32 *);
u64 katomic__load_T_u64(u64 *);
void katomic__store_T_u32(u32 *,u32);
void lib__kpanic(void *,char *) __attribute__((noreturn));
void *array_get(Array,i64);
multi_return_bool_u32_u32_u32_u32 cpu__cpuid(u32,u32);
bool linuxkpi__directstore_has(u32);
bool linuxkpi__cpu_has(u32);
void linuxkpi__initialise_cpu_features(void);
'''
    return declarations,record[0],local[0]


def native_proof(work, raw, cc, includes, public):
    """Compile untouched generated bodies; observers remain unresolved here."""
    names = ("linuxkpi__directstore_has", "linuxkpi__initialise_cpu_features",
             "linuxkpi__cpu_has", "vinix_linuxkpi_cpu_has")
    pattern = r"^[^\n;]+\([^\n]*\) \{\n.*?^\}"
    bodies = {}
    for name in names:
        matches = [body for body in re.findall(pattern, raw, re.M | re.S)
                   if re.match(r"^[^\n]*\b" + name + r"\(", body)]
        if len(matches) != 1:
            raise AssertionError("Missing unique actual generated native body " + name)
        bodies[name] = matches[0]
        if re.search(r"\b(?:malloc|calloc|realloc|memdup|v_malloc|new_array|array_clone|array_push)\b", matches[0]):
            raise AssertionError("Allocation appeared in native policy body " + name)
    prefix,_,_=generated_prefix(raw)
    variants = {
        "query": (names[:1], {"katomic__load_T_u32", "lib__kpanic"}),
        "constructor": (names[1:2], {"array_get", "katomic__load_T_u32", "katomic__load_T_u64", "katomic__store_T_u32", "lib__kpanic"}),
        "frontend": (names[2:], {"cpu__cpuid", "lib__kpanic", "linuxkpi__directstore_has"}),
    }
    results = []
    for name, (selected, expected) in variants.items():
        source = work / ("native-" + name + ".c")
        source.write_text(prefix+"\n\n"+"\n\n".join(bodies[item] for item in selected)+"\n")
        for standard in ("gnu99", "gnu11"):
            for optimize in ("O0", "O1", "O2"):
                obj = work / ("native-"+name+"-"+standard+"-"+optimize+".o")
                argv = [cc,"--target=x86_64-unknown-none","-std="+standard,"-"+optimize,
                    "-ffreestanding","-fno-builtin","-fwrapv","-Wall","-Wextra","-Werror",
                    "-nostdinc","-isystem",str(ROOT/"kernel/freestnd-c-hdrs"),
                    "-c",str(source),"-o",str(obj)]
                command(argv,obj.with_suffix(".log"))
                undefined = subprocess.check_output([tool("llvm-nm"),"--undefined-only",str(obj)],text=True)
                observed = set(re.findall(r"\bU\s+(\S+)",undefined))
                imports=expected | ({"v_panic"} if optimize=="O0" and name in ("query","frontend") else set())
                # Full builtin generation retains genuine divide/modulo-zero
                # fatal references at O0; both divisors are the constant 32.
                # O1/O2 eliminate those unreachable compiler guards.
                if observed != imports or len(undefined.splitlines()) != len(imports):
                    raise AssertionError("Unexpected real native imports for "+str(obj)+": "+undefined)
                disassembly = subprocess.check_output([tool("llvm-objdump"),"-dr",str(obj)],text=True)
                obj.with_suffix(".disassembly").write_text(disassembly)
                if re.search(r"\b(?:cpuid|movdir64b|movdiri)\b",disassembly):
                    raise AssertionError("Instruction appeared in immutable policy/legacy frontend object")
                results.append({"variant":name,"standard":standard,"optimization":optimize,
                    "argv":argv,"object_sha256":sha(obj),"undefined":sorted(observed)})
    cold = work/"native-public.c"
    cold.write_text(public.read_text().split("unsigned cpu_policy_feature_id")[0]+
        "const unsigned genuine_directstore_ids[2] = {X86_FEATURE_MOVDIRI,X86_FEATURE_MOVDIR64B};\n")
    cold_objects=[]
    for standard in ("gnu99","gnu11"):
        obj=work/("native-public-"+standard+".o")
        argv=[cc,"--target=x86_64-unknown-none","-std="+standard,"-O2","-ffreestanding",
            "-Wall","-Wextra","-Werror","-Wno-unused-parameter",*includes,"-c",str(cold),"-o",str(obj)]
        command(argv,obj.with_suffix(".log"))
        undefined=subprocess.check_output([tool("llvm-nm"),"--undefined-only",str(obj)],text=True)
        if undefined.strip():
            raise AssertionError("Cold genuine feature/header ABI probe imported runtime symbols")
        cold_objects.append({"standard":standard,"argv":argv,"object_sha256":sha(obj),"undefined":[]})
    return {"objects":results,"cold_original_header_objects":cold_objects,
        "unchanged_selected_body_sha256":{name:hashlib.sha256(body.encode()).hexdigest() for name,body in bodies.items()},
        "scope":"Exact host-generated native backend/frontend bodies, scalar observer layout, and unresolved genuine callees. No native CPU boot, actual Local layout, or MOVDIR execution is established."}


def run(keep_dir):
    temporary = tempfile.TemporaryDirectory(prefix="vinix-cpu-feature-policy-") if keep_dir is None else None
    work = Path(temporary.name) if temporary else Path(keep_dir).resolve()
    if not temporary:
        work.mkdir(parents=True, exist_ok=False)
    observed = (POLICY, BRIDGE, LOCAL, Path(__file__), HERE / "include/asm/cpufeature.h",
        HERE / "include/vinix/runtime.h", HERE / "include/linux/types.h",
        HERE / "include/generated/autoconf.h", HERE / "upstream.py", HERE / "upstream.json",
        LINUX / "arch/x86/include/asm/cpufeatures.h")
    initial = {str(path): sha(path) for path in observed}
    try:
        for field, spelling in (("cpu_number","u64"),("online","u64"),("directstore_ecx","u32")):
            if not re.search(r"^\s*"+field+r"\s+"+spelling+r"\s*$",LOCAL.read_text(),re.M):
                raise AssertionError("Native field changed from the explicit scalar observer: "+field)
        verification = [sys.executable,str(HERE/"upstream.py"),"verify","--base",str(LINUX.parent)]
        verified = command(verification,work/"upstream-verification.log")
        stage = work / "stage"
        for module in ("linuxkpi", "katomic", "lib", "x86/cpu"):
            (stage / module).mkdir(parents=True)
        (stage / "v.mod").write_text("Module { name: 'cpu_feature_policy_probe' }\n")
        (stage / "entry.v").write_text("module main\nimport linuxkpi as _\nfn main() {}\n")
        shutil.copyfile(POLICY, stage / "linuxkpi/policy.v")
        frontend = function(BRIDGE.read_text(), "cpu_has")
        (stage / "linuxkpi/frontend.v").write_text("module linuxkpi\nimport x86.cpu\nimport lib\n" + frontend)
        (stage / "linuxkpi/observer.v").write_text(OBSERVERS)
        (stage / "katomic/observer.v").write_text(ATOMIC_OBSERVER)
        (stage / "lib/observer.v").write_text(FATAL_OBSERVER)
        (stage / "x86/cpu/observer.v").write_text(CPU_OBSERVER)
        (work / "policy_model.h").write_text(MODEL_HEADER)
        v = os.environ.get("V", "v")
        resolved_v = Path(shutil.which(v) or v).resolve()
        v_hash = sha(resolved_v)
        arch = "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "amd64"
        generated = work / "policy.c"
        array_source=resolved_v.parent/"vlib/builtin/array.v"
        array_hash=sha(array_source)
        argv = [str(resolved_v), "-no-closures", "-os", "vinix", "-arch", arch,
            "-target-libc-headers", "-gc", "none", "-manualfree", "-o", str(generated), str(stage)]
        environment = {**os.environ, "VCACHE": str(work / "vcache"), "V_C_ERROR_BUG_REPORT_DISABLED": "1"}
        command(argv, work / "generation.log", env=environment)
        raw = generated.read_text()
        prefix,array,local=generated_prefix(raw)
        (work / "model_types.h").write_text("#include <stdint.h>\ntypedef uint64_t u64; typedef uint32_t u32;\n"
            "typedef int64_t i64;\ntypedef struct array array; typedef array Array;\n" + array + "\n"
            "typedef struct linuxkpi__Local linuxkpi__Local;\n" + local + "\n")
        body_pattern = r"^[^\n;]+\([^\n]*\) \{\n.*?^\}"
        names={"cpu__cpuid","katomic__load_T_u32","katomic__load_T_u64","katomic__store_T_u32","lib__kpanic",
            "linuxkpi__cpu_has","vinix_linuxkpi_cpu_has","linuxkpi__directstore_has","linuxkpi__initialise_cpu_features"}
        for suffix in ("configure","initialize","reset","seed","state"):
            names.update(("linuxkpi__test_"+suffix,"policy_test_"+suffix))
        bodies=[body for body in re.findall(body_pattern,raw,re.M|re.S)
                if any(re.match(r"^[^\n]*\b"+name+r"\(",body) for name in names)]
        if len(bodies)!=len(names):
            raise AssertionError("Missing unique actual policy/observer/generated wrapper body")
        compiled=prefix+'\n#include "policy_model.h"\n'+"\n\n".join(bodies)+"\n"
        if re.findall(body_pattern,compiled,re.M|re.S)!=bodies:
            raise AssertionError("Body extraction changed a generated function body")
        (work / "policy-compile.c").write_text(compiled)
        (work / "test.c").write_text(C_TEST)
        cc = os.environ.get("CC", "clang")
        flags = ["-O1", "-g", "-ffreestanding", "-fno-builtin", "-fwrapv", "-fno-strict-aliasing",
            "-Wall", "-Wextra", "-Werror", "-Wno-unused-function", "-Wno-unused-parameter", "-pthread",
            "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-I", str(work)]
        includes = ["-D__KERNEL__", "-include", "linux/kconfig.h", "-include",
            str(LINUX / "include/linux/compiler_types.h"), "-nostdinc", "-isystem",
            str(ROOT / "kernel/freestnd-c-hdrs")]
        for directory in (HERE / "include", LINUX / "include", LINUX / "include/uapi",
                          LINUX / "arch/x86/include", LINUX / "arch/x86/include/uapi"):
            includes += ["-I", str(directory)]
        public = work / "public.c"
        public.write_text('''#include <asm/cpufeature.h>
_Static_assert(X86_FEATURE_MOVDIRI == 539 && X86_FEATURE_MOVDIR64B == 540,
    "genuine pinned leaf-seven ECX IDs");
_Static_assert(__builtin_types_compatible_p(__typeof__(&vinix_linuxkpi_cpu_has),
    bool (*)(unsigned int)), "real public CPU feature ABI");
unsigned cpu_policy_feature_id(unsigned which) {
    return which == 0 ? X86_FEATURE_MOVDIRI : which == 1 ? X86_FEATURE_MOVDIR64B : X86_FEATURE_XMM4_1;
}
bool cpu_policy_boot_query(unsigned feature) { return boot_cpu_has(feature); }
bool cpu_policy_static_query(unsigned feature) { return static_cpu_has(feature); }
''')
        outcomes = []
        for standard in ("gnu99", "gnu11"):
            obj = work / (standard + "-core.o")
            compile_argv = [cc, "-std=" + standard, *flags, "-Dmain=policy_unused_main",
                "-Dmalloc=policy_unexpected_malloc", "-Dcalloc=policy_unexpected_calloc",
                "-Drealloc=policy_unexpected_realloc", "-Dfree=policy_unexpected_free",
                "-c", str(work / "policy-compile.c"), "-o", str(obj)]
            command(compile_argv, work / (standard + "-compile.log"))
            public_obj = work / (standard + "-public.o")
            public_argv = [cc, "-std=" + standard, *flags, *includes,
                "-c", str(public), "-o", str(public_obj)]
            command(public_argv, work / (standard + "-public.log"))
            executable = work / (standard + "-runtime")
            link_argv = [cc, "-std=" + standard, *flags,
                str(work / "test.c"), str(obj), str(public_obj), "-o", str(executable)]
            command(link_argv, work / (standard + "-link.log"))
            result = command([str(executable)], work / (standard + "-run.log"),
                env={**os.environ, "UBSAN_OPTIONS": "halt_on_error=1",
                     "ASAN_OPTIONS": "detect_stack_use_after_return=1"})
            if result.stderr:
                raise AssertionError("Unexpected runtime/sanitizer diagnostic: " + result.stderr)
            print(standard + ": " + result.stdout.strip())
            outcomes.append({"standard": standard, "compile_argv": compile_argv,
                "public_header_argv": public_argv, "public_object_sha256": sha(public_obj),
                "link_argv": link_argv, "object_sha256": sha(obj), "output": result.stdout.strip()})
        native = native_proof(work,raw,cc,includes,public)
        if initial != {str(path): sha(path) for path in observed} or sha(resolved_v) != v_hash or sha(array_source)!=array_hash:
            raise AssertionError("Policy/profile/test/compiler changed during isolated checks")
        (work / "result.json").write_text(json.dumps({"scope": __doc__, "source_sha256": initial,
            "V_sha256": v_hash, "generation_argv": argv, "generated_c_sha256": sha(generated),
            "upstream_verification": {"argv": verification,"output": verified.stdout.strip()},
            "compiler_metadata": {"selection":"Exact named generated bodies and actual descriptors; unrelated builtin runtime is not linked into this host model.",
                "builtin_array_source":str(array_source),"builtin_array_source_sha256":array_hash,
                "unchanged_body_count": len(bodies), "unchanged_body_sha256": [hashlib.sha256(body.encode()).hexdigest() for body in bodies]},
            "exact_frontend_sha256": hashlib.sha256(frontend.encode()).hexdigest(),
            "native_compiler_proof": native,
            "host_results": outcomes, "observer_scope": "Scalar membership and atomics are private host observers. Policy and frontend bodies unchanged. Boot sampling, AP ordering, native Local layout and actual MOVDIR execution require separate native verification."}, indent=2) + "\n")
    finally:
        if temporary:
            temporary.cleanup()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-dir", type=Path)
    run(parser.parse_args().keep_dir)
