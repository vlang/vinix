#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check original SMP/CSD compiler closure and native CPU query relocations.

Original headers own every CSD, cpumask and smp_ops representation. These tests
compare observable ABI bytes and preserve genuinely unresolved dispatch, mask
and early-map references. They neither implement SMP calls nor validate Linux
stack ownership, CPU hotplug, runtime masks or hardware interrupt delivery.
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


csd = load("smp_header_original_csd", ROOT / "tests/linuxkpi/smp_type_test.py")
audit = load("smp_header_audit", HERE / "audit.py")
bounds = load("smp_header_bounds", HERE / "generate-bounds.py")
HEADER = "#include <linux/smp.h>\n#include <linux/smp.h>\n#include <asm/smp.h>\n"
COLD = csd.NODE.split("unsigned long csd_node_bytes", 1)[0] + \
    csd.LAYOUT.split("static void callback", 1)[0] + r'''
_Static_assert(CONFIG_SMP == 1 && CONFIG_HAVE_ARCH_WITHIN_STACK_FRAMES == 1,
    "actual x86 SMP compiler configuration");
_Static_assert(CONFIG_NR_CPUS == 256 && sizeof(struct cpumask) == 32,
    "genuine configured CPU mask width");
#if defined(CONFIG_FRAME_POINTER) || defined(CONFIG_HARDENED_USERCOPY)
#error This compiler profile supplies no Linux stack validation
#endif
'''
QUERY = r'''
_Static_assert(__builtin_types_compatible_p(__typeof__(&raw_smp_processor_id),
    unsigned int (*)(void)), "native CPU accessor ABI");
_Static_assert(__builtin_types_compatible_p(__typeof__(&vinix_get_cpu),
    unsigned int (*)(void)), "native scheduler pin ABI");
unsigned int query_raw(void) { return raw_smp_processor_id(); }
unsigned int query_stable(void) { return smp_processor_id(); }
unsigned int query_arch_stable(void) { return __smp_processor_id(); }
unsigned int query_safe(void) { return safe_smp_processor_id(); }
unsigned int query_pinned(void) { return get_cpu(); }
void release_pin(void) { put_cpu(); }
unsigned int (*native_accessor_reference)(void) = raw_smp_processor_id;
'''
EARLY = r'''
_Static_assert(__builtin_types_compatible_p(__typeof__(x86_cpu_to_apicid_early_ptr), u16 *),
    "original early APIC pointer");
_Static_assert(__builtin_types_compatible_p(__typeof__(x86_cpu_to_acpiid_early_ptr), u32 *),
    "original early ACPI pointer");
_Static_assert(__builtin_types_compatible_p(__typeof__(&x86_cpu_to_apicid_early_map[0]), u16 *),
    "original early APIC map");
_Static_assert(__builtin_types_compatible_p(__typeof__(&x86_cpu_to_acpiid_early_map[0]), u32 *),
    "original early ACPI map");
u16 *apic_template_reference = &x86_cpu_to_apicid;
u32 *acpi_template_reference = &x86_cpu_to_acpiid;
u16 **apic_pointer_reference = &x86_cpu_to_apicid_early_ptr;
u32 **acpi_pointer_reference = &x86_cpu_to_acpiid_early_ptr;
u16 *apic_map_reference = x86_cpu_to_apicid_early_map;
u32 *acpi_map_reference = x86_cpu_to_acpiid_early_map;
'''
STACK = r'''
_Static_assert(NOT_STACK == 0, "original unable-to-determine result");
int original_stack_query(const void *s, const void *e, const void *p, unsigned long n) {
    return arch_within_stack_frames(s,e,p,n);
}
'''
RUNTIME_IMPORTS = {"__cpu_online_mask", "__smp_call_single_queue", "on_each_cpu_cond_mask",
    "smp_call_function", "smp_call_function_many", "smp_call_function_single",
    "smp_call_function_single_async", "smp_ops"}
EARLY_IMPORTS = {"x86_cpu_to_apicid", "x86_cpu_to_acpiid", "x86_cpu_to_apicid_early_ptr",
    "x86_cpu_to_acpiid_early_ptr", "x86_cpu_to_apicid_early_map", "x86_cpu_to_acpiid_early_map"}
QUERY_IMPORTS = {"raw_smp_processor_id", "vinix_get_cpu", "vinix_linuxkpi_preempt_enable"}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def tool(name):
    return shutil.which(name) or str(Path("/opt/homebrew/opt/llvm/bin") / name)


def command(argv, log, success=True):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=180)
    Path(log).write_text(json.dumps(argv) + "\n" + result.stdout + result.stderr)
    if success and result.returncode:
        raise AssertionError("Compiler failed; see " + str(log))
    return result


def macros(text, name):
    lines = text.splitlines(keepends=True)
    output = []
    for index, line in enumerate(lines):
        if not re.match(r"^#define\s+"+name+r"\(",line):
            continue
        value=line
        while line.rstrip().endswith("\\"):
            index+=1
            line=lines[index]
            value+=line
        output.append(value)
    return output


def flags(linux, generated, overlay, standard):
    base=csd.flags(linux,generated,"x86_64-unknown-none",standard)
    return [str(overlay) if item==str(HERE/"include") else item for item in base]+["-Wno-sign-compare"]


def run(keep_dir):
    temporary=tempfile.TemporaryDirectory(prefix="vinix-smp-headers-") if keep_dir is None else None
    work=Path(temporary.name) if temporary else Path(keep_dir).resolve()
    if not temporary:
        work.mkdir(parents=True,exist_ok=False)
    linux=Path(os.environ.get("LINUXKPI_SOURCE_DIR",bounds.upstream.DEFAULT /
        ("linux-"+bounds.upstream.PIN["version"]))).resolve()
    archive=linux.parent/("linux-"+bounds.upstream.PIN["version"]+".tar.xz")
    compiler_text=os.environ.get("CC","clang")
    compiler=shlex.split(compiler_text)
    owned=("linux/smp.h","asm/percpu.h","asm/smp.h","generated/autoconf.h")
    observed=tuple(HERE/"include"/name for name in owned)+(Path(__file__),
        ROOT/"tests/linuxkpi/smp_type_test.py",HERE/"audit.py",HERE/"generate-bounds.py",
        HERE/"upstream.py",HERE/"upstream.json")
    initial={str(path):sha(path) for path in observed}
    results=[]
    try:
        verification=command([sys.executable,str(HERE/"upstream.py"),"verify","--base",str(linux.parent)],
            work/"upstream-verification.log")
        generated=work/"generated"
        audit.generate_headers(generated)
        production=work/"production"
        shutil.copytree(HERE/"include",production)
        reference=work/"original-profile"
        shutil.copytree(production,reference)
        # Let the actual original asm/smp.h own all architecture declarations
        # and its pcpu_hot query. No alternative representation is supplied.
        (reference/"asm/smp.h").unlink()
        (reference/"linux/smp.h").write_text("#include_next <linux/smp.h>\n")
        provenance=bounds.generate(linux,archive,generated/"generated/bounds.h",
            generated/"generated/bounds.h.d",generated/"generated/bounds.h.json",compiler_text,
            flags(linux,generated,production,"gnu11"))
        if sha(archive)!=bounds.upstream.PIN["sha256"]:
            raise AssertionError("Pinned archive changed before reference extraction")
        originals=work/"archive-reference"
        archive_names=("arch/x86/Kconfig","scripts/Makefile.extrawarn")
        archive_hashes={}
        with tarfile.open(archive,"r:xz") as source:
            for name in archive_names:
                member=source.getmember(linux.name+"/"+name)
                if not member.isfile():
                    raise AssertionError("Reference is not an original regular file")
                destination=originals/name
                destination.parent.mkdir(parents=True,exist_ok=True)
                destination.write_bytes(source.extractfile(member).read())
                archive_hashes[name]=sha(destination)
        kconfig=(originals/"arch/x86/Kconfig").read_text()
        selection=re.search(r"^\s*select HAVE_ARCH_WITHIN_STACK_FRAMES\s*$",kconfig,re.M)
        warning=(originals/"scripts/Makefile.extrawarn").read_text()
        policy=re.search(r"^KBUILD_CFLAGS \+= -Wno-sign-compare\s*$",warning,re.M)
        if not selection or not policy:
            raise AssertionError("Actual original Kconfig/Kbuild compiler prerequisites changed")
        original_percpu=(linux/"arch/x86/include/asm/percpu.h").read_text()
        exact_early=macros(original_percpu,"DECLARE_EARLY_PER_CPU_READ_MOSTLY")
        if len(exact_early)!=2 or macros((production/"asm/percpu.h").read_text(),
            "DECLARE_EARLY_PER_CPU_READ_MOSTLY")!=exact_early:
            raise AssertionError("SMP/non-SMP early declaration macros differ from pinned source")
        arch_smp=(linux/"arch/x86/include/asm/smp.h").read_text()
        ops=re.search(r"struct smp_ops \{(.*?)\n\};",arch_smp,re.S)
        members=re.findall(r"\(\*(\w+)\)",ops[1])
        if len(members)!=14 or len(set(members))!=len(members):
            raise AssertionError("Original smp_ops field inventory changed")
        abi_words=["sizeof(struct __call_single_node)","_Alignof(struct __call_single_node)",
            "sizeof(struct __call_single_data)","_Alignof(struct __call_single_data)",
            "sizeof(call_single_data_t)","_Alignof(call_single_data_t)",
            "offsetof(struct __call_single_data,node)","offsetof(struct __call_single_data,func)",
            "offsetof(struct __call_single_data,info)","sizeof(struct smp_ops)","_Alignof(struct smp_ops)",
            "sizeof(struct cpumask)","CSD_FLAG_LOCK","CSD_TYPE_SYNC","CSD_TYPE_ASYNC",
            *["offsetof(struct smp_ops,"+name+")" for name in members]]
        abi="const unsigned long original_abi_words[] = {\n"+",\n".join(abi_words)+"\n};\n"
        baseline='#include "'+str(linux/"include/linux/smp.h")+'"\n'

        def probe(standard,name,code,expected=(),overlay=production,cold=False,reject=None):
            source=work/(standard+"-"+name+".c")
            source.write_text(code)
            obj=source.with_suffix(".o")
            dep=source.with_suffix(".d")
            argv=compiler+flags(linux,generated,overlay,standard)+["-MD","-MF",str(dep),
                "-MQ",str(obj),"-c",str(source),"-o",str(obj)]
            outcome=command(argv,source.with_suffix(".log"),success=reject is None)
            item={"probe":name,"standard":standard,"argv":argv,"exit":outcome.returncode}
            if reject:
                if not outcome.returncode or reject not in outcome.stderr:
                    raise AssertionError("Genuine prerequisite rejection missing: "+name)
                item["diagnostics"]=outcome.stderr
            else:
                undefined=subprocess.check_output([tool("llvm-nm"),"--undefined-only",str(obj)],text=True)
                imports={line.split()[-1] for line in undefined.splitlines() if line.strip()}
                if imports!=set(expected):
                    raise AssertionError("Genuine runtime imports changed: "+name+" "+undefined)
                symbols=subprocess.check_output([tool("llvm-nm"),str(obj)],text=True)
                if cold and symbols.strip():
                    raise AssertionError("Declaration-only include order emitted an object symbol")
                inputs=bounds.dependency_paths(dep.read_text(),obj)
                for path in (linux/"include/linux/smp.h",linux/"include/linux/smp_types.h",
                             linux/"arch/x86/include/asm/smp.h"):
                    if path.resolve() not in inputs:
                        raise AssertionError("Original dependency was bypassed: "+str(path))
                disassembly=subprocess.check_output([tool("llvm-objdump"),"-dr",
                    "--no-show-raw-insn",str(obj)],text=True)
                source.with_suffix(".disassembly").write_text(disassembly)
                relocations=subprocess.check_output([tool("llvm-readelf"),"--relocations",str(obj)],text=True)
                source.with_suffix(".relocations").write_text(relocations)
                if name=="cpu-queries":
                    if "pcpu_hot" in relocations+symbols+disassembly:
                        raise AssertionError("Foreign Linux GS query escaped into native accessor probe")
                    targets={"query_raw":"raw_smp_processor_id","query_stable":"raw_smp_processor_id",
                        "query_arch_stable":"raw_smp_processor_id","query_safe":"raw_smp_processor_id",
                        "query_pinned":"vinix_get_cpu","release_pin":"vinix_linuxkpi_preempt_enable"}
                    for function,target in targets.items():
                        body=re.search(r"<"+function+r">:\n(.*?)(?=\n[0-9a-f]+ <|\Z)",disassembly,re.S)
                        if not body or len(re.findall(r"\b"+target+r"\b",body[1]))!=1:
                            raise AssertionError("Wrong actual query/pin relocation: "+function)
                if name=="stack-disabled":
                    body=disassembly.split("<original_stack_query>:",1)[1]
                    if not re.search(r"\bxorl\s+%eax, %eax",body) or not re.search(r"\bretq",body):
                        raise AssertionError("Disabled original frame helper did not return NOT_STACK")
                item.update(object_sha256=sha(obj),undefined_symbols=undefined,symbols=symbols,
                    input_sha256={str(path):sha(path) for path in inputs},
                    relocations_sha256=hashlib.sha256(relocations.encode()).hexdigest())
                if name.endswith("abi"):
                    output=source.with_suffix(".abi-bytes")
                    derived=source.with_suffix(".dump-copy.o")
                    # An input-only objcopy invocation rewrites the input.
                    # Keep the compiler object immutable and record the
                    # separately derived copy rather than hashing stale bytes.
                    command([tool("llvm-objcopy"),"--dump-section",".rodata="+str(output),str(obj),str(derived)],
                        source.with_suffix(".objcopy.log"))
                    if sha(obj)!=item["object_sha256"]:
                        raise AssertionError("Section dump changed the original compiler object")
                    if output.stat().st_size!=len(abi_words)*8:
                        raise AssertionError("ABI vector was not exactly one original 64-bit word per field")
                    item["observable_abi_sha256"]=sha(output)
                    item["abi_dump_derived_object_sha256"]=sha(derived)
                    item["observable_abi_words"]=[int.from_bytes(output.read_bytes()[i:i+8],"little")
                        for i in range(0,output.stat().st_size,8)]
            results.append(item)
            return item

        for standard in ("gnu99","gnu11"):
            probe(standard,"cold",HEADER+COLD,cold=True)
            reference_abi=probe(standard,"original-abi",baseline+COLD+abi,overlay=reference)
            actual_abi=probe(standard,"production-abi",HEADER+COLD+abi)
            if reference_abi["observable_abi_sha256"]!=actual_abi["observable_abi_sha256"]:
                raise AssertionError("Production changed actual original CSD/smp_ops ABI bytes")
            probe(standard,"cpu-queries",HEADER+QUERY,QUERY_IMPORTS)
            probe(standard,"early-references",HEADER+EARLY,EARLY_IMPORTS)
            probe(standard,"runtime-references",HEADER+csd.REFERENCE,RUNTIME_IMPORTS)
            probe(standard,"stack-disabled",HEADER+STACK)
            for index,order in enumerate(("#include <asm/percpu.h>\n", "#include <asm/smp.h>\n",
                                          "#include <linux/percpu.h>\n")):
                probe(standard,"include-order-"+str(index),order+HEADER+COLD,cold=True)
            probe(standard,"missing-config","#undef CONFIG_HAVE_ARCH_WITHIN_STACK_FRAMES\n"+HEADER,
                reject="redefinition of 'arch_within_stack_frames'")
            probe(standard,"missing-declaration","#include <asm/percpu.h>\n"
                "#undef DECLARE_EARLY_PER_CPU_READ_MOSTLY\n"+HEADER,reject="type specifier missing")
            probe(standard,"foreign-pcpu-query",baseline+
                "unsigned int foreign_query(void) { return raw_smp_processor_id(); }\n",overlay=reference,
                reject="undeclared identifier 'pcpu_hot'")

        controls={name:int(re.search(r"^#define\s+"+name+r"\s+(0x[0-9a-fA-F]+)",arch_smp,re.M)[1],16)
                  for name in ("STARTUP_READ_APICID","STARTUP_PARALLEL_MASK")}
        assembly=[]
        for name,overlay in (("production",production),("original",reference)):
            source=work/(name+"-assembly.S")
            source.write_text("#include <asm/smp.h>\n.equ probe_read_apicid, STARTUP_READ_APICID\n"
                ".equ probe_parallel_mask, STARTUP_PARALLEL_MASK\n")
            obj=source.with_suffix(".o");dep=source.with_suffix(".d")
            argv=compiler+["--target=x86_64-unknown-none","-nostdinc","-D__KERNEL__","-D__ASSEMBLY__",
                "-include","linux/kconfig.h","-I",str(overlay),"-I",str(linux/"include"),
                "-I",str(linux/"arch/x86/include"),"-Wall","-Wextra","-Werror","-MD","-MF",str(dep),
                "-MQ",str(obj),"-c",str(source),"-o",str(obj)]
            command(argv,source.with_suffix(".log"))
            undefined=subprocess.check_output([tool("llvm-nm"),"--undefined-only",str(obj)],text=True)
            if undefined.strip():
                raise AssertionError("Original assembler profile imported a C runtime")
            symbols=subprocess.check_output([tool("llvm-nm"),str(obj)],text=True)
            values={line.split()[-1]:int(line.split()[0],16) for line in symbols.splitlines() if line.strip()}
            if values!={"probe_read_apicid":controls["STARTUP_READ_APICID"],
                        "probe_parallel_mask":controls["STARTUP_PARALLEL_MASK"]}:
                raise AssertionError("Forwarding header changed original assembler control constants")
            inputs=bounds.dependency_paths(dep.read_text(),obj)
            if (linux/"arch/x86/include/asm/smp.h").resolve() not in inputs:
                raise AssertionError("Original assembly header was not discovered")
            assembly.append({"profile":name,"argv":argv,"object_sha256":sha(obj),
                "input_sha256":{str(path):sha(path) for path in inputs},"symbols":symbols,"undefined_symbols":undefined})
        if initial!={str(path):sha(path) for path in observed}:
            raise AssertionError("Production/test/profile changed during isolated compiler checks")
        for item in results:
            if item["exit"]==0 and sha(work/(item["standard"]+"-"+item["probe"]+".o"))!=item["object_sha256"]:
                raise AssertionError("Saved compiler object no longer matches its recorded hash")
        report={"scope":__doc__,"source_sha256":initial,"bounds":provenance,
            "upstream_verification":verification.stdout.strip(),"archive_reference_sha256":archive_hashes,
            "genuine_early_macros":exact_early,"original_smp_ops_members":members,
            "pinned_configuration_selection":selection[0].strip(),"pinned_warning_policy":policy[0].strip(),
            "probes":results,"assembly":assembly,
            "positive_objects":sum(item["exit"]==0 for item in results)+len(assembly),
            "genuine_rejections":sum(item["exit"]!=0 for item in results)}
        (work/"result.json").write_text(json.dumps(report,indent=2)+"\n")
        print("PASS: "+str(report["positive_objects"])+" original SMP compiler/assembly objects; "+
            str(report["genuine_rejections"])+" genuine prerequisite rejections")
    finally:
        if temporary:
            temporary.cleanup()


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-dir",type=Path)
    run(parser.parse_args().keep_dir)
