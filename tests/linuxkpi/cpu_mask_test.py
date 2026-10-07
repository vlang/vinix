#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Execute the unchanged V boot-mask publisher and original Linux mask queries.

The original struct, atomic counter, constant objects and bitmap helpers retain
their real owners. Private host processes supply cold storage for each case;
there is no production reset, concurrent constructor, CPU hotplug or SMP call
implementation. Numerical CPU65/255 coverage does not boot those CPUs.
TLS caller-state values are host observers; native IRQ/migration behavior needs
the separate full kernel fixture. Native objects reject context/allocator imports.
Private Mach-O scaffolding adjusts only ELF section metadata and borrows the
actual foreign type/query aliases; full native contracts compile separately.
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
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


audit = load("cpu_mask_audit", HERE / "audit.py")
bounds = load("cpu_mask_bounds", HERE / "generate-bounds.py")
CORE = HERE / "compatcore/smp_masks.v"
QUERIES = HERE / "headercore/smp_masks.v"
STORAGE = HERE / "headercore/smp_masks_storage.v"
ORIGINAL_STORAGE_REVISION = "2a5abc36175a5177828d86aad71667787eb68110"
ORIGINAL_STORAGE_PATH = "kernel/c/linuxkpi_cpu_masks_data.c"
PRIMITIVES = ROOT / "kernel/c/linuxkpi_smp_masks_v_primitives.h"
CONTRACT = ROOT / "kernel/c/linuxkpi_smp_masks_v_contract.h"

TYPE_CHECKS = r'''
#include <linux/cpumask.h>
#include "linuxkpi_smp_masks_v_primitives.h"
_Static_assert(NR_CPUS == 256 && BITS_PER_LONG == 64 &&
    sizeof(struct cpumask) == 32 && _Alignof(struct cpumask) == 8,
    "original complete four-word CPU mask");
_Static_assert(sizeof(cpu_bit_bitmap) == 2080 && sizeof(cpu_all_bits) == 32,
    "original compressed constants");
_Static_assert(offsetof(struct cpumask, bits) == 0 &&
    __builtin_types_compatible_p(__typeof__(((struct cpumask *)0)->bits), unsigned long[4]),
    "original bitmap word type");
_Static_assert(__builtin_types_compatible_p(__typeof__(__cpu_possible_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_online_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_present_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_active_mask), struct cpumask) &&
    __builtin_types_compatible_p(__typeof__(__cpu_dying_mask), struct cpumask),
    "genuine five original objects");
_Static_assert(sizeof(atomic_t) == 4 && offsetof(atomic_t, counter) == 0 &&
    __builtin_types_compatible_p(__typeof__(__num_online_cpus), atomic_t) &&
    __builtin_types_compatible_p(__typeof__(__num_online_cpus.counter), int) &&
    __builtin_types_compatible_p(__typeof__(nr_cpu_ids), unsigned int),
    "genuine original count fields");
#if defined(CONFIG_HOTPLUG_CPU) || defined(CONFIG_CPUMASK_OFFSTACK)
#error This test establishes only permanent native boot masks
#endif
'''

FIXTURE = TYPE_CHECKS + r'''
extern void mask_check(bool, int);
#define CHECK(value) mask_check((value), __LINE__)
static struct cpumask *original_mask(unsigned kind) {
    switch (kind) {
    case 0: return &__cpu_possible_mask;
    case 1: return &__cpu_online_mask;
    case 2: return &__cpu_present_mask;
    case 3: return &__cpu_active_mask;
    case 4: return &__cpu_dying_mask;
    default: return NULL;
    }
}
static unsigned long expected_word(unsigned count, unsigned word) {
    unsigned long value = 0;
    for (unsigned bit = 0; bit < 64; ++bit)
        if (word * 64 + bit < count) value |= 1UL << bit;
    return value;
}
static unsigned long poison_word(unsigned kind, unsigned word) {
    return 0xfedcba9876543210UL ^ ((unsigned long)kind << 12) ^ word;
}
void mask_poison(void) {
    for (unsigned kind = 0; kind < 5; ++kind)
        for (unsigned word = 0; word < 4; ++word)
            original_mask(kind)->bits[word] = poison_word(kind, word);
    __num_online_cpus.counter = 0x12345678;
    nr_cpu_ids = 0x23456789;
}
void mask_poison_unchanged(void) {
    for (unsigned kind = 0; kind < 5; ++kind)
        for (unsigned word = 0; word < 4; ++word)
            CHECK(original_mask(kind)->bits[word] == poison_word(kind, word));
    CHECK(__num_online_cpus.counter == 0x12345678);
    CHECK(nr_cpu_ids == 0x23456789);
}
void mask_initial_state(void) {
    CHECK(!vkm_cpu_masks_ready()); CHECK(nr_cpu_ids == 256);
    CHECK(__num_online_cpus.counter == 0);
    CHECK(vkm_cpu_ids() == 0 && vkm_online_count() == 0);
    for (unsigned kind = 0; kind < 5; ++kind) {
        CHECK(vkm_mask_storage(kind) == original_mask(kind)->bits);
        CHECK(vkm_mask_weight(kind) == 0);
        for (unsigned word = 0; word < 4; ++word)
            CHECK(original_mask(kind)->bits[word] == 0);
        for (unsigned cpu = 0; cpu < 256; ++cpu) CHECK(!vkm_mask_has(kind,cpu));
    }
    CHECK(vkm_mask_storage(5) == NULL && vkm_mask_storage(~0U) == NULL);
    CHECK(vkm_cpu_ids_storage() == &nr_cpu_ids);
    CHECK(vkm_online_storage() == &__num_online_cpus.counter);
}
void mask_constants(void) {
    const struct cpumask *static_all = cpu_all_mask;
    const struct cpumask *static_none = cpu_none_mask;
    CHECK(static_all->bits == cpu_all_bits);
    CHECK(static_none->bits == cpu_bit_bitmap[0]);
    for (unsigned word = 0; word < 4; ++word) {
        CHECK(static_all->bits[word] == ~0UL);
        CHECK(static_none->bits[word] == 0);
    }
    for (unsigned selected = 0; selected < 256; ++selected) {
        const struct cpumask *one = cpumask_of(selected);
        /* Address arithmetic spans the complete original compressed table,
         * rather than subtracting beyond a C array-row object in the oracle. */
        uintptr_t expected_address = (uintptr_t)&cpu_bit_bitmap[0][0] +
            (4 * (1 + selected%64) - selected/64) * sizeof(unsigned long);
        CHECK((uintptr_t)one->bits == expected_address);
        CHECK(cpumask_of(selected) == one);
        struct cpumask copied;
        cpumask_copy(&copied,one);
        for (unsigned word = 0; word < 4; ++word) {
            unsigned long value = word == selected/64 ? 1UL << (selected%64) : 0;
            CHECK(one->bits[word] == value && copied.bits[word] == value);
        }
        cpumask_clear(&copied);
        for (unsigned word = 0; word < 4; ++word) CHECK(copied.bits[word] == 0);
        for (unsigned cpu = 0; cpu < 256; ++cpu) {
            CHECK(vkm_mask_of_has(selected,cpu) == (selected == cpu));
            CHECK(vkm_all_has(cpu));
            CHECK(!test_bit(cpu,static_none->bits));
        }
    }
    const unsigned invalid[] = {256,257,0xffffffffU};
    for (unsigned i=0;i<3;++i) {
        CHECK(!vkm_all_has(invalid[i]));
        CHECK(!vkm_mask_of_has(invalid[i],0));
        CHECK(!vkm_mask_of_has(0,invalid[i]));
        CHECK(!vkm_mask_of_has(invalid[i],invalid[i]));
    }
}
void mask_contents(unsigned count) {
    CHECK(vkm_cpu_masks_ready()); CHECK(vkm_cpu_ids()==count);
    CHECK(vkm_online_count()==count && num_online_cpus()==count);
    CHECK(nr_cpu_ids==count && __num_online_cpus.counter==(int)count);
    for (unsigned kind=0;kind<5;++kind) {
        const struct cpumask *mask=original_mask(kind);
        CHECK(vkm_mask_weight(kind)==(kind==4 ? 0 : count));
        CHECK(cpumask_weight(mask)==(kind==4 ? 0 : count));
        for (unsigned word=0;word<4;++word)
            CHECK(mask->bits[word]==(kind==4 ? 0 : expected_word(count,word)));
        for (unsigned cpu=0;cpu<257;++cpu)
            CHECK(vkm_mask_has(kind,cpu)==(kind!=4 && cpu<count));
        CHECK(!vkm_mask_has(kind,0xffffffffU));
        unsigned seen=0,cpu;
        for_each_cpu(cpu,mask) { CHECK(kind!=4 && cpu==seen && cpu<count); ++seen; }
        CHECK(seen==(kind==4 ? 0 : count));
        CHECK(cpumask_first(mask)==(kind==4 ? count : 0));
        CHECK(cpumask_next((int)count-1,mask)==count);
    }
    CHECK(vkm_mask_weight(5)==0 && vkm_mask_weight(0xffffffffU)==0);
    CHECK(!vkm_mask_has(5,0) && !vkm_mask_has(0xffffffffU,0));
    unsigned seen=0,cpu;
    for_each_online_cpu(cpu) { CHECK(cpu==seen); ++seen; } CHECK(seen==count);
    seen=0; for_each_possible_cpu(cpu) { CHECK(cpu==seen); ++seen; } CHECK(seen==count);
    seen=0; for_each_present_cpu(cpu) { CHECK(cpu==seen); ++seen; } CHECK(seen==count);
}
void mask_reader_batch(unsigned count,unsigned rounds) {
    for (unsigned iteration=0;iteration<rounds;++iteration) {
        CHECK(vkm_cpu_masks_ready()); CHECK(vkm_cpu_ids()==count);
        CHECK(vkm_online_count()==count);
        unsigned selected=(iteration*73)%256;
        for (unsigned kind=0;kind<5;++kind) {
            CHECK(vkm_mask_weight(kind)==(kind==4 ? 0 : count));
            CHECK(vkm_mask_has(kind,selected)==(kind!=4 && selected<count));
        }
        CHECK(vkm_mask_of_has(selected,selected));
        CHECK(!vkm_mask_of_has(selected,(selected+1)%256));
        CHECK(vkm_all_has(255)); CHECK(!vkm_all_has(256));
    }
}
'''

RUNNER = r'''
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include "linuxkpi_smp_masks_v_primitives.h"
void mask_initial_state(void); void mask_poison(void); void mask_poison_unchanged(void);
void mask_constants(void); void mask_contents(unsigned); void mask_reader_batch(unsigned,unsigned);
static unsigned long long assertions;
static _Thread_local unsigned irq_state,preempt_depth,cpu_number;
void mask_check(bool passed,int line) {
    __atomic_add_fetch(&assertions,1,__ATOMIC_RELAXED);
    if (!passed) { fprintf(stderr,"mask assertion at %d\n",line); abort(); }
}
static void *reader(void *argument) {
    unsigned count=*(const unsigned *)argument;
    irq_state=0; preempt_depth=7; cpu_number=63;
    mask_reader_batch(count,10000);
    mask_check(irq_state==0 && preempt_depth==7 && cpu_number==63,__LINE__);
    return NULL;
}
int main(int argc,char **argv) {
    if (argc!=2) return 2;
    unsigned long input=strtoul(argv[1],NULL,10);
    if (input>UINT32_MAX) return 2;
    unsigned count=(unsigned)input;
    mask_initial_state(); mask_constants();
    irq_state=1; preempt_depth=2; cpu_number=65;
    mask_poison();
    mask_check(vkm_cpu_masks_bootstrap(0)==-22,__LINE__); mask_poison_unchanged();
    mask_check(vkm_cpu_masks_bootstrap(257)==-22,__LINE__); mask_poison_unchanged();
    mask_check(vkm_cpu_masks_bootstrap(UINT32_MAX)==-22,__LINE__); mask_poison_unchanged();
    mask_check(!vkm_cpu_masks_ready(),__LINE__);
    if (count==0 || count>256) {
        mask_check(vkm_cpu_masks_bootstrap(count)==-22,__LINE__);
        mask_poison_unchanged();
    } else {
        mask_check(vkm_cpu_masks_bootstrap(count)==0,__LINE__); mask_contents(count);
        mask_check(vkm_cpu_masks_bootstrap(count)==-114,__LINE__);
        mask_check(vkm_cpu_masks_bootstrap(count==256 ? 1 : 256)==-114,__LINE__);
        mask_check(vkm_cpu_masks_bootstrap(0)==-22,__LINE__);
        mask_check(vkm_cpu_masks_bootstrap(257)==-22,__LINE__);
        mask_check(vkm_cpu_masks_bootstrap(UINT32_MAX)==-22,__LINE__);
        mask_contents(count);
        pthread_t actors[4];
        for (unsigned i=0;i<4;++i) if (pthread_create(&actors[i],NULL,reader,&count)) abort();
        for (unsigned i=0;i<4;++i) if (pthread_join(actors[i],NULL)) abort();
        /* No cold process is reused and no storage is mutated under readers. */
        mask_contents(count); mask_constants();
    }
    mask_check(irq_state==1 && preempt_depth==2 && cpu_number==65,__LINE__);
    printf("PASS: %llu original mask/publisher assertions (count=%u)\n",assertions,count);
    return 0;
}
'''

REFERENCES = TYPE_CHECKS + r'''
#include <linux/smp.h>
unsigned int *pending_total_cpus=&total_cpus;
struct cpumask *pending_booted_once=&cpus_booted_once_mask;
void (*pending_online)(unsigned int,bool)=set_cpu_online;
void (*pending_present)(const struct cpumask *)=init_cpu_present;
void (*pending_possible)(const struct cpumask *)=init_cpu_possible;
void (*pending_initial_online)(const struct cpumask *)=init_cpu_online;
int (*pending_dispatch)(int,smp_call_func_t,void *,int)=smp_call_function_single;
'''


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def tool(name):
    found=shutil.which(name)
    if found:
        return found
    path=Path("/opt/homebrew/opt/llvm/bin")/name
    if path.is_file():
        return str(path)
    raise FileNotFoundError(name)


def command(argv,log,env=None,success=True):
    result=subprocess.run(argv,capture_output=True,text=True,env=env,timeout=180)
    Path(log).write_text(shlex.join(argv)+"\n"+result.stdout+result.stderr)
    if success and result.returncode:
        raise AssertionError("Command failed; see "+str(log))
    return result


def vfunction(source,name):
    match=re.search(r"^(?:pub )?fn "+re.escape(name)+r"\([^\n]*\)[^\n{]*\{",source,re.M)
    if not match:
        raise AssertionError("Missing genuine V function "+name)
    start=match.start()
    previous=source[:start].splitlines(keepends=True)
    if previous and previous[-1].startswith("@[export:"):
        start-=len(previous[-1])
    end=match.end();depth=1
    while depth:
        depth+=(source[end]=="{")-(source[end]=="}");end+=1
    return source[start:end]+"\n"


def extract_body(raw,name):
    candidates=re.findall(r"^[^\n;]+\([^\n]*\) \{\n.*?^\}",raw,re.M|re.S)
    found=[body for body in candidates if re.match(r"^[^\n]*\b"+name+r"\(",body)]
    if len(found)!=1:
        raise AssertionError("Missing unique actual generated body "+name)
    return found[0]


def flags(linux,generated,standard,target=None):
    result=["-std="+standard,"-O2","-ffreestanding","-fwrapv","-fno-strict-aliasing",
        "-nostdinc","-Wall","-Wextra","-Werror","-Wno-unused-function","-Wno-unused-parameter",
        "-Wno-sign-compare",
        "-D__KERNEL__","-DVINIX_LINUXKPI","-include","linux/kconfig.h",
        "-include",str(linux/"include/linux/compiler_types.h"),
        "-isystem",str(ROOT/"kernel/freestnd-c-hdrs")]
    if target:
        result.insert(0,"--target="+target)
    for path in (generated,HERE/"include",ROOT/"kernel/c",linux/"include",linux/"include/uapi",
                 linux/"arch/x86/include",linux/"arch/x86/include/uapi"):
        result += ["-I",str(path)]
    return result


def symbol_table(obj):
    output=subprocess.check_output([tool("llvm-readelf"),"--symbols","--wide",str(obj)],text=True)
    result={}
    for line in output.splitlines():
        columns=line.split()
        if len(columns)==8 and columns[3]=="OBJECT" and columns[4]=="GLOBAL":
            result[columns[7]]={"value":int(columns[1],16),"size":int(columns[2]),"section":columns[6]}
    return result,output


def dump_rodata(obj,work,section=".rodata"):
    before=sha(obj);output=work/(obj.stem+section);derived=work/(obj.stem+section+".dump-copy.o")
    command([tool("llvm-objcopy"),"--dump-section",section+"="+str(output),str(obj),str(derived)],
        work/(obj.stem+section+".dump.log"))
    if sha(obj)!=before:
        raise AssertionError("Readonly dump rewrote the original compiler object")
    return output.read_bytes(),{"original_sha256":before,"derived_sha256":sha(derived),"bytes_sha256":sha(output)}


def run(keep_dir):
    temporary=tempfile.TemporaryDirectory(prefix="vinix-cpu-masks-") if keep_dir is None else None
    work=Path(temporary.name) if temporary else Path(keep_dir).resolve()
    if not temporary:
        work.mkdir(parents=True,exist_ok=False)
    linux=Path(os.environ.get("LINUXKPI_SOURCE_DIR",audit.upstream.DEFAULT/
        ("linux-"+audit.upstream.PIN["version"]))).resolve()
    compiler=shlex.split(os.environ.get("CC","clang"))
    observed=(Path(__file__),CORE,QUERIES,STORAGE,PRIMITIVES,CONTRACT,
        HERE/"compatcore/bitmap.v",HERE/"compatcore/primitives.v",HERE/"headercore/primitive.v",
        HERE/"headercore/wait.v",HERE/"include/generated/autoconf.h",ROOT/"kernel/GNUmakefile",
        ROOT/"kernel/c/linuxkpi_header_primitive_v_contract.h",
        ROOT/"kernel/c/linuxkpi_common_v_contract.h",ROOT/"build-support/compile-v-module.py",
        linux/"include/linux/cpumask.h",linux/"include/linux/smp.h",linux/"lib/find_bit.c",linux/"lib/hweight.c")
    initial={str(path):sha(path) for path in observed}
    (work/"initial-source-sha256.json").write_text(json.dumps(initial,indent=2)+"\n")
    try:
        verify=command([sys.executable,str(HERE/"upstream.py"),"verify","--base",str(linux.parent)],
            work/"upstream-verification.log")
        generated=work/"include";audit.generate_headers(generated)
        profile=flags(linux,generated,"gnu11","x86_64-unknown-none")
        bounds_path=generated/"generated/bounds.h"
        provenance=bounds.generate(linux,linux.parent/("linux-"+audit.upstream.PIN["version"]+".tar.xz"),
            bounds_path,Path(str(bounds_path)+".d"),Path(str(bounds_path)+".json"),
            shlex.join(compiler),profile)
        archive=Path(provenance["archive"])
        if sha(archive)!=provenance["archive_sha256"]:
            raise AssertionError("Pinned reference archive changed")
        with tarfile.open(archive,"r:xz") as tar:
            member=tar.getmember("linux-"+audit.upstream.PIN["version"]+"/kernel/cpu.c")
            if not member.isfile():
                raise AssertionError("Original mask data is not an archive regular file")
            original=tar.extractfile(member).read()
            warning_member=tar.getmember("linux-"+audit.upstream.PIN["version"]+"/scripts/Makefile.extrawarn")
            if not warning_member.isfile():
                raise AssertionError("Original warning policy is not a regular archive file")
            warning=tar.extractfile(warning_member).read()
        if not re.search(rb"^KBUILD_CFLAGS \+= -Wno-sign-compare\s*$",warning,re.M):
            raise AssertionError("Selected warning policy differs from exact original Kbuild")
        (work/"original-Makefile.extrawarn").write_bytes(warning)
        (work/"original-kernel-cpu.c").write_bytes(original)
        original_storage = subprocess.check_output(["git", "show",
            ORIGINAL_STORAGE_REVISION + ":" + ORIGINAL_STORAGE_PATH], cwd=ROOT)
        (work/"original-storage.c").write_bytes(original_storage)
        begin=original.index(b"/* cpu_bit_bitmap[0] is empty")
        end=original.index(b"EXPORT_SYMBOL(cpu_all_bits);",begin)+len(b"EXPORT_SYMBOL(cpu_all_bits);")
        constant_source=original[begin:end].decode()
        (work/"original-constants.c").write_text("#include <linux/cpumask.h>\n#include <linux/export.h>\n"+
            constant_source+"\n")
        (work/"cold.c").write_text(TYPE_CHECKS)
        (work/"references.c").write_text(REFERENCES)
        (work/"fixture.c").write_text(FIXTURE)
        (work/"runner.c").write_text(RUNNER)
        # The genuine kernel flags permit unsigned-long/u64 aliasing on the
        # ARM host. Native x86 uses the compiler's identical uint64_t spelling.
        if "-fno-strict-aliasing" not in (ROOT/"kernel/GNUmakefile").read_text():
            raise AssertionError("Native compiler alias policy changed")
        stage=work/"stage"
        for module in ("compatcore","headercore"):
            (stage/module).mkdir(parents=True)
        (stage/"v.mod").write_text("Module { name: 'cpu_mask_probe' }\n")
        (stage/"entry.v").write_text("module main\nimport compatcore as _\nimport headercore as _\nfn main() {}\n")
        shutil.copyfile(CORE,stage/"compatcore/smp_masks.v")
        shutil.copyfile(QUERIES,stage/"headercore/smp_masks.v")
        shutil.copyfile(STORAGE,stage/"headercore/smp_masks_storage.v")
        weight=vfunction((HERE/"compatcore/bitmap.v").read_text(),"bitmap_weight")
        hweight=vfunction((HERE/"compatcore/primitives.v").read_text(),"native_hweight_long")
        (stage/"compatcore/weight.v").write_text("@[translated]\nmodule compatcore\n"+weight+hweight)
        atomic=vfunction((HERE/"headercore/primitive.v").read_text(),"atomic_read")
        (stage/"headercore/bindings.v").write_text("@[translated]\nmodule headercore\n"
            '#include "linuxkpi_header_primitive_v_contract.h"\n'
            "@[typedef]\nstruct C.atomic_t { counter i32 }\n"
            "@[typedef]\nstruct C.vhp_const_atomicp {}\nfn C.test_bit(i32,voidptr) bool\n"
            "@[c: '__atomic_load_n']\nfn C.vhp_load32(&i32,i32) i32\n"+atomic)
        v=Path(shutil.which(os.environ.get("V","v")) or os.environ.get("V","v")).resolve()
        native_c=work/"actual-v.c"
        environment={**os.environ,"VCACHE":str(work/"vcache"),"V_C_ERROR_BUG_REPORT_DISABLED":"1"}
        generation=[str(v),"-no-builtin","-no-closures","-os","vinix","-arch","amd64",
            "-target-libc-headers","-gc","none","-manualfree","-o",str(native_c),str(stage)]
        command(generation,work/"generation.log",environment)
        module_compiler=load("cpu_mask_module_compiler",ROOT/"build-support/compile-v-module.py")
        rejection_cases=[]
        metadata_probe=work/"metadata-rejections";metadata_probe.mkdir()
        valid_metadata="// ABI native-scalar: probe_word const_unsigned_long_64\n@[typedef]\nstruct C.probe_word {}\n"
        for name,source,compiler_text,duplicate in (
            ("unknown-type",valid_metadata.replace("const_unsigned_long_64","writable_word"),"",False),
            ("invalid-identifier",valid_metadata.replace("probe_word const","probe_word; const"),"",False),
            ("missing-foreign-type",valid_metadata.split("@[typedef]")[0],"",False),
            ("duplicate-alias",valid_metadata,"",True),
            ("compiler-conflict",valid_metadata,"typedef unsigned long probe_word;",False)):
            case=metadata_probe/name;case.mkdir();(case/"a.v").write_text(source)
            if duplicate:(case/"b.v").write_text(source)
            try:module_compiler.native_scalar_metadata(case,compiler_text)
            except ValueError as error:rejection_cases.append({"case":name,"error":str(error)})
            else:raise AssertionError("Invalid scalar producer metadata was accepted: "+name)
        raw=module_compiler.native_scalar_metadata(stage/"headercore",native_c.read_text())
        native_c.write_text(raw)
        host_c=work/"actual-host-v.c"
        host_generation=generation[:-3]+["-d","linuxkpi_host_test","-o",str(host_c),str(stage)]
        command(host_generation,work/"host-generation.log",environment)
        host_raw=module_compiler.native_scalar_metadata(stage/"headercore",host_c.read_text())
        host_c.write_text(host_raw)
        storage_symbols=("cpu_bit_bitmap","cpu_all_bits","__cpu_possible_mask","__cpu_online_mask",
            "__cpu_present_mask","__cpu_active_mask","__cpu_dying_mask","__num_online_cpus","nr_cpu_ids")
        def storage_source(generated):
            declarations=[]
            for symbol in storage_symbols:
                found=re.findall(r"^(?:__attribute__\s*\(\([^\n;]*?\)\)\s*)?"
                    r"(?:vkms_const_word|struct cpumask|cpumask|atomic_t|u32)\s+"+re.escape(symbol)+
                    r"(?:\[[^\n;]*?\])?(?: = [^\n;]+)?;",generated,re.M)
                if len(found)!=1:
                    raise AssertionError("Missing unique V-owned storage definition "+symbol+": "+str(found))
                declarations.append(found[0])
            return '#include <linux/cache.h>\n#include <linux/cpumask.h>\n'+\
                'typedef struct cpumask cpumask;\n'+\
                module_compiler.native_scalar_metadata(stage/"headercore", "")+\
                "\n".join(declarations)+"\n",declarations
        data_source,data_definitions=storage_source(raw)
        host_data_source,host_data_definitions=storage_source(host_raw)
        strip_sections=lambda value:re.sub(r'__attribute__\s*\(\(\s*section\s*\(\s*"[^"]+"\s*\)\s*\)\)\s*',"",value)
        if [strip_sections(value) for value in data_definitions]!=host_data_definitions:
            raise AssertionError("Host profile changed V-owned storage types/initializers")
        (work/"data.c").write_text(data_source)
        (work/"host-data.c").write_text(host_data_source)
        # Ordinary native generation retains the actual export name but does
        # not add shared-library visibility annotations to its declarations.
        staged_sources="\n".join(path.read_text() for path in stage.rglob("*.v"))
        names=re.findall(r"@\[export: '([\w]+)'\]\s*(?:@\[[^\n]+\]\s*)*(?:pub )?fn ",staged_sources)
        core_internal={"compatcore__"+name for name in re.findall(r"^pub fn (\w+)\(",CORE.read_text(),re.M)}
        query_internal={"headercore__"+name for name in re.findall(r"^(?:pub )?fn (\w+)\(",QUERIES.read_text(),re.M)}
        names=set(names)|core_internal|query_internal|{"compatcore__native_hweight_long",
            "compatcore__bitmap_weight","headercore__atomic_read"}
        bodies={name:extract_body(raw,name) for name in names}
        if any(re.search(r"\b(?:malloc|calloc|realloc|memdup|v_malloc|new_array|array_clone|array_push)\b",body)
               for body in bodies.values()):
            raise AssertionError("Actual selected generated mask body allocates")
        prefix="#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n"
        prefix+="typedef uint32_t u32; typedef uint64_t u64; typedef int32_t i32;\n"
        prefix+="typedef int64_t i64; typedef uintptr_t usize; typedef void *voidptr;\n"
        ready=re.search(r"^u32 compatcore__vkms_ready(?: = [^;]+)?;",raw,re.M)
        if not ready:
            raise AssertionError("Missing genuine zero-initialized ready slot")
        def declarations(selected):
            result=[]
            for name in sorted(selected):
                found=re.findall(r"^[^\n{};]+\b"+name+r"\([^\n;]*\);",raw,re.M)
                if not found:
                    raise AssertionError("Missing actual generated declaration "+name)
                result.append(found[0])
            return "\n".join(result)+"\n"
        core_names={name for name in bodies if name.startswith("vkm_cpu_masks")}|core_internal
        core_source=prefix+'#include "linuxkpi_smp_masks_v_primitives.h"\n'+ready[0]+"\n"+\
            declarations(core_names)+\
            "\n\n".join(bodies[name] for name in sorted(core_names))+"\n"
        weight_names={"compatcore__native_hweight_long","compatcore__bitmap_weight","__bitmap_weight"}
        weight_source=prefix+declarations(weight_names)+\
            "\n\n".join(bodies[name] for name in sorted(weight_names))+"\n"
        query_names=set(bodies)-core_names-weight_names
        # Linux supplies the identical u32 alias. Retain its original owner
        # in this strict GNU99 scaffold rather than redeclaring that alias or
        # suppressing C11-only typedef diagnostics. Function bodies stay exact.
        query_prefix=prefix.replace("typedef uint32_t u32; ","")
        query_source=query_prefix+'#include "linuxkpi_header_primitive_v_contract.h"\n'+\
            '#include "linuxkpi_smp_masks_v_contract.h"\n'+\
            '_Static_assert(__builtin_types_compatible_p(u32,uint32_t), "identical native scalar alias");\n'+\
            declarations(query_names)+\
            "\n\n".join(bodies[name] for name in sorted(query_names))+"\n"
        for name,text in (("core",core_source),("weight",weight_source),("queries",query_source)):
            selected=[body for body in bodies.values() if body in text]
            if re.findall(r"^[^\n;]+\([^\n]*\) \{\n.*?^\}",text,re.M|re.S)!=selected:
                # Dict iteration and output order differ; equality as exact
                # independent bodies still forbids edits to any C algorithm.
                actual=re.findall(r"^[^\n;]+\([^\n]*\) \{\n.*?^\}",text,re.M|re.S)
                if sorted(actual)!=sorted(selected):
                    raise AssertionError("C extraction changed an actual generated body")
            (work/(name+".c")).write_text(text)
        # ARM hosting cannot import x86 privileged inline assembly through the
        # broad native common contract. Borrow the exact foreign declarations
        # and macro aliases required by these unchanged bodies, from genuine
        # original cpumask/atomic headers. The complete native contracts are
        # still compiled above; no host C record or query loop replaces them.
        foreign=[]
        for path,pattern in ((CONTRACT,r"^typedef const struct cpumask \*vkms_const_cpumask;$"),
            (ROOT/"kernel/c/linuxkpi_header_primitive_v_contract.h",r"^typedef const atomic_t \*vhp_const_atomicp;$")):
            match=re.search(pattern,path.read_text(),re.M)
            if not match:
                raise AssertionError("Actual foreign alias changed")
            foreign.append(match[0])
        for name in ("vkms_all_mask","vkms_const_bits"):
            match=re.search(r"^#define "+name+r"\([^\n]*",CONTRACT.read_text(),re.M)
            if not match:
                raise AssertionError("Actual original query alias changed")
            foreign.append(match[0])
        host_query_source=query_prefix.replace("typedef uint64_t u64; ","")+\
            '#include <linux/cpumask.h>\n#include "linuxkpi_smp_masks_v_primitives.h"\n'+\
            "\n".join(foreign)+"\n"+declarations(query_names)+\
            "\n\n".join(bodies[name] for name in sorted(query_names))+"\n"
        if sorted(re.findall(r"^[^\n;]+\([^\n]*\) \{\n.*?^\}",host_query_source,re.M|re.S))!=\
                sorted(bodies[name] for name in query_names):
            raise AssertionError("Host foreign declarations changed actual query bodies")
        (work/"host-queries.c").write_text(host_query_source)
        host_include=work/"host-include";(host_include/"asm").mkdir(parents=True)
        (host_include/"asm/cache.h").write_text(
            "/* Private section metadata adapter; all original cache definitions retained. */\n"
            "#include_next <asm/cache.h>\n"
            "#if defined(__APPLE__)\n#undef __read_mostly\n"
            '#define __read_mostly __attribute__((section("__DATA,__data")))\n#endif\n')
        (host_include/"linux").mkdir()
        (host_include/"linux/compiler_attributes.h").write_text(
            "/* Private Mach-O declaration metadata; native attributes remain original. */\n"
            "#include_next <linux/compiler_attributes.h>\n"
            "#if defined(__APPLE__)\n#undef __section\n#define __section(name)\n#endif\n")
        proofs=[];runtime=[]
        for standard in ("gnu99","gnu11"):
            native_flags=flags(linux,generated,standard,"x86_64-unknown-none")
            objects={}
            for name,source in (("cold",work/"cold.c"),("references",work/"references.c"),
                ("data",work/"data.c"),("original-data",work/"original-constants.c"),
                ("original-storage",work/"original-storage.c"),
                ("core",work/"core.c"),("queries",work/"queries.c"),("weight",work/"weight.c")):
                obj=work/(standard+"-native-"+name+".o")
                argv=compiler+native_flags+["-c",str(source),"-o",str(obj)]
                command(argv,obj.with_suffix(".log"))
                objects[name]=obj
                imports=subprocess.check_output([tool("llvm-nm"),"--undefined-only",str(obj)],text=True)
                actual_imports={line.split()[-1] for line in imports.splitlines() if line.strip()}
                allowed={
                    "cold":set(),"data":set(),"original-data":set(),"original-storage":set(),"weight":set(),
                    "core":{"vkm_cpu_ids_storage","vkm_mask_storage","vkm_online_storage"},
                    "queries":{"__cpu_possible_mask","__cpu_online_mask","__cpu_present_mask",
                        "__cpu_active_mask","__cpu_dying_mask","__num_online_cpus","nr_cpu_ids",
                        "cpu_bit_bitmap","cpu_all_bits","vkm_cpu_masks_ready","__bitmap_weight"},
                    "references":{"total_cpus","cpus_booted_once_mask","set_cpu_online","init_cpu_present",
                        "init_cpu_possible","init_cpu_online","smp_call_function_single"}}
                if actual_imports!=allowed[name]:
                    raise AssertionError("Genuine native imports changed for "+name+": "+imports)
                proofs.append({"standard":standard,"variant":name,"argv":argv,
                    "object_sha256":sha(obj),"undefined_symbols":imports})
            cold_symbols=subprocess.check_output([tool("llvm-nm"),str(objects["cold"])],text=True)
            if cold_symbols.strip():
                raise AssertionError("Cold original declarations created storage/runtime")
            reference_proof=next(item for item in reversed(proofs)
                if item["standard"]==standard and item["variant"]=="references")
            observed_imports={line.split()[-1] for line in reference_proof["undefined_symbols"].splitlines()}
            expected={"total_cpus","cpus_booted_once_mask","set_cpu_online","init_cpu_present",
                "init_cpu_possible","init_cpu_online","smp_call_function_single"}
            if observed_imports!=expected:
                raise AssertionError("Pending genuine services were concealed: "+str(observed_imports))
            constants={}
            storage_inventory={};mutable_bytes={}
            for name in ("data","original-data","original-storage"):
                symbols,table=symbol_table(objects[name]);data,receipt=dump_rodata(objects[name],work)
                section_report=subprocess.check_output([tool("llvm-readelf"),"--sections","--wide",
                    str(objects[name])],text=True)
                values={}
                if name in ("data","original-storage"):
                    expected_sizes={"cpu_bit_bitmap":2080,"cpu_all_bits":32,
                        "__cpu_possible_mask":32,"__cpu_online_mask":32,"__cpu_present_mask":32,
                        "__cpu_active_mask":32,"__cpu_dying_mask":32,"__num_online_cpus":4,"nr_cpu_ids":4}
                    if {key:value["size"] for key,value in symbols.items()}!=expected_sizes:
                        raise AssertionError("Real storage-only CPU-mask symbol inventory changed")
                    if re.search(r"\bFUNC\b",table) or subprocess.check_output(
                            [tool("llvm-nm"),"--undefined-only",str(objects[name])],text=True).strip():
                        raise AssertionError("Constant/storage translation unit contains code or runtime imports")
                    storage_inventory[name]={key:(value["size"],value["value"]% (8 if value["size"]>=32 else 4))
                        for key,value in symbols.items()}
                    relocations=subprocess.check_output([tool("llvm-readelf"),"--relocations",str(objects[name])],text=True)
                    if "There are no relocations" not in relocations:
                        raise AssertionError("Permanent V/original storage acquired relocations")
                    payload,_=dump_rodata(objects[name],work,".data..read_mostly")
                    mutable_bytes[name]={}
                    for symbol in storage_symbols[2:]:
                        field=symbols[symbol]
                        section=re.search(r"\[\s*"+field["section"]+r"\]\s+\.data\.\.read_mostly\s+([^\n]+)",section_report)
                        if not section or "W" not in section[1].split()[-4]:
                            raise AssertionError("Original writable storage section changed: "+symbol)
                        value=payload[field["value"]:field["value"]+field["size"]]
                        expected=(256).to_bytes(4,"little") if symbol=="nr_cpu_ids" else bytes(field["size"])
                        if value!=expected:
                            raise AssertionError("Original permanent storage cold bytes changed: "+symbol)
                        mutable_bytes[name][symbol]=value.hex()
                for symbol,size in (("cpu_bit_bitmap",2080),("cpu_all_bits",32)):
                    field=symbols[symbol]
                    section=re.search(r"\[\s*"+field["section"]+r"\]\s+\.rodata\s+([^\n]+)",section_report)
                    if field["size"]!=size or not section or "W" in section[1].split()[-4]:
                        raise AssertionError("Original constants are not exact readonly objects")
                    values[symbol]=hashlib.sha256(data[field["value"]:field["value"]+size]).hexdigest()
                constants[name]=values
                proofs.append({"standard":standard,"variant":name+"-readonly",
                    "symbols":table,"sections":section_report,"constant_sha256":values,"dump":receipt})
            if constants["data"]!=constants["original-data"] or constants["data"]!=constants["original-storage"]:
                raise AssertionError("Production readonly constant bytes differ from actual pinned definitions")
            if storage_inventory["data"]!=storage_inventory["original-storage"]:
                raise AssertionError("V/original permanent storage symbol size/alignment differs")
            if mutable_bytes["data"]!=mutable_bytes["original-storage"]:
                raise AssertionError("V/original permanent storage bytes differ")
            native_alias=work/(standard+"-native-word-alias.c")
            native_alias.write_text(TYPE_CHECKS+"\n_Static_assert(__builtin_types_compatible_p(uint64_t,unsigned long),"
                '"native scalar view exact alias");\n')
            command(compiler+native_flags+["-fsyntax-only",str(native_alias)],native_alias.with_suffix(".log"))
            for name,wrong in (("wrong-table","extern const unsigned long cpu_bit_bitmap[256][4];"),
                               ("wrong-counter","extern uint64_t __num_online_cpus;")):
                source=work/(standard+"-"+name+".c");source.write_text(TYPE_CHECKS+wrong+"\n")
                rejected=command(compiler+native_flags+["-fsyntax-only",str(source)],source.with_suffix(".log"),success=False)
                if rejected.returncode==0 or "different type" not in rejected.stderr:
                    raise AssertionError("Wrong original storage declaration was accepted")
            host_flags=["-I",str(host_include)]+flags(linux,generated,standard)+["-O1","-g",
                "-fsanitize=address,undefined","-fno-omit-frame-pointer"]
            host_objects=[]
            for name,source in (("core",work/"core.c"),("queries",work/"host-queries.c"),
                ("weight",work/"weight.c"),("data",work/"host-data.c"),("fixture",work/"fixture.c"),
                ("find-bit",linux/"lib/find_bit.c"),("hweight",linux/"lib/hweight.c")):
                obj=work/(standard+"-host-"+name+".o")
                command(compiler+host_flags+["-c",str(source),"-o",str(obj)],obj.with_suffix(".log"))
                host_objects.append(obj)
            runner=work/(standard+"-runner.o")
            command(compiler+["-std="+standard,"-O1","-g","-Wall","-Wextra","-Werror",
                "-iquote",str(ROOT/"kernel/c"),"-fsanitize=address,undefined","-fno-omit-frame-pointer",
                "-c",str(work/"runner.c"),"-o",str(runner)],runner.with_suffix(".log"))
            original_host_data=work/(standard+"-host-original-storage.o")
            command(compiler+host_flags+["-c",str(work/"original-storage.c"),"-o",str(original_host_data)],
                original_host_data.with_suffix(".log"))
            variant_totals=[]
            for variant in ("V","original-C"):
                selected_objects=list(host_objects)
                if variant=="original-C":selected_objects[3]=original_host_data
                executable=work/(standard+"-"+variant+"-runtime")
                command(compiler+["-fsanitize=address,undefined",*[str(p) for p in selected_objects],str(runner),
                    "-pthread","-o",str(executable)],executable.with_suffix(".link.log"))
                total=0
                count_cases=(1,2,4,63,64,65,127,128,129,191,192,193,255,256,0,257,0xffffffff)
                for count in count_cases:
                    result=command([str(executable),str(count)],work/(standard+"-"+variant+"-count-"+str(count)+".log"),
                        env={**os.environ,"UBSAN_OPTIONS":"halt_on_error=1",
                            "ASAN_OPTIONS":"detect_stack_use_after_return=1"})
                    match=re.fullmatch(r"PASS: (\d+) original mask/publisher assertions \(count="+str(count)+r"\)\n",result.stdout)
                    if not match or result.stderr:
                        raise AssertionError("Unclean original mask sanitizer execution")
                    total+=int(match[1])
                variant_totals.append(total)
                runtime.append({"standard":standard,"storage_variant":variant,"assertions":total,
                    "process_count":len(count_cases),"count_cases":list(count_cases),
                    "executable_sha256":sha(executable),"actual_objects":{str(p):sha(p) for p in selected_objects},
                    "scope":"Separate cold processes and joined immutable reader actors; no live reset/constructor races/native CPU execution"})
                print(standard+" "+variant+": "+str(total)+" clean original mask and unchanged V publisher assertions")
            if len(set(variant_totals))!=1:
                raise AssertionError("Original-C/V storage assertion totals differ")
        if initial!={str(path):sha(path) for path in observed}:
            raise AssertionError("Owned source/profile changed during isolated validation")
        for item in proofs:
            if "object_sha256" in item:
                obj=work/(item["standard"]+"-native-"+item["variant"]+".o")
                if sha(obj)!=item["object_sha256"]:
                    raise AssertionError("Saved native object differs from recorded compiler hash")
        report={"scope":__doc__,"source_sha256":initial,"bounds":provenance,
            "upstream_verification":verify.stdout.strip(),"original_cpu_source_sha256":sha(work/"original-kernel-cpu.c"),
            "original_constant_block_sha256":hashlib.sha256(constant_source.encode()).hexdigest(),
            "pinned_warning_policy_sha256":sha(work/"original-Makefile.extrawarn"),
            "v":str(v),"v_sha256":sha(v),"generation_argv":generation,"generated_c_sha256":sha(native_c),
            "actual_selected_body_sha256":{name:hashlib.sha256(body.encode()).hexdigest() for name,body in bodies.items()},
            "original_storage_revision":ORIGINAL_STORAGE_REVISION,"original_storage_path":ORIGINAL_STORAGE_PATH,
            "original_storage_sha256":hashlib.sha256(original_storage).hexdigest(),
            "actual_storage_definitions":data_definitions,"host_storage_definitions":host_data_definitions,
            "native_storage_cold_bytes":mutable_bytes,"producer_metadata_rejections":rejection_cases,
            "native_proofs":proofs,"runtime":runtime,
            "host_foreign_aliases":foreign,"host_cache_metadata_adapter_sha256":sha(host_include/"asm/cache.h"),
            "host_section_metadata_adapter_sha256":sha(host_include/"linux/compiler_attributes.h"),
            "strict_query_scaffold":"Original Linux owns the identical u32 typedef; all selected native/host bodies remain byte-identical",
            "alias_policy":"Actual kernel -fno-strict-aliasing on host; genuine x86 uint64_t/unsigned-long type identity explicitly compiled"}
        (work/"result.json").write_text(json.dumps(report,indent=2)+"\n")
    finally:
        if temporary:
            temporary.cleanup()


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-dir",type=Path)
    run(parser.parse_args().keep_dir)
