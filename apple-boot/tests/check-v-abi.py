#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare generated V storage against the unchanged public C structures."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

loader = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path)
arguments = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="vinix-apple-abi-") as directory:
    work = Path(directory)
    generated = arguments.source or work / "core.c"
    if not arguments.source:
        subprocess.run(["python3", str(loader / "compile-v.py"), "--host", str(generated)], check=True)
    text = generated.read_text()
    # Use only compiler-emitted storage declarations, so libc and wrappers
    # cannot affect this comparison or redeclare the independent C prototypes.
    declarations = text[text.index("typedef struct applecore__"):]
    declarations = declarations[:declarations.index("\nstatic void v3_eprint_lit")]
    source = "#include <stddef.h>\n#include <stdint.h>\n#include <stdbool.h>\n"
    source += "typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64; typedef int32_t i32;\n"
    source += "\n".join(re.findall(r"typedef struct [^{]+\{[^}]*\} \w+;|typedef [^;{]+;|struct [^{;]+ \{[^}]*\};", declarations))
    source += '\n#include "adt.h"\n#include "fdt.h"\n#include "loader.h"\n'
    checked = 0
    for c_name in ("adt", "adt_property", "fdt_builder", "adt_fdt_extras",
                   "boot_video", "boot_info", "payload_header", "allocator", "pagemap",
                   "loaded_kernel", "memmap_entry", "memmap", "reserved_range",
                   "reserved_set", "limine_inputs"):
        v_name = "applecore__" + c_name[0].upper() + c_name[1:]
        match = re.search(r"struct " + v_name + r" \{(.*?)\n\};", text, re.S)
        if not match:
            continue  # Stage one builds just the tree implementation.
        source += '_Static_assert(sizeof(' + v_name + ') == sizeof(struct ' + c_name + '), "' + c_name + ' size");\n'
        source += '_Static_assert(_Alignof(' + v_name + ') == _Alignof(struct ' + c_name + '), "' + c_name + ' alignment");\n'
        for declaration in match[1].splitlines():
            field = re.search(r"\b([A-Za-z_]\w*)\s*(?:\[[^]]*\])?;", declaration)
            if not field:
                continue
            v_field = field[1]
            c_field = "type" if v_field == "type_" else v_field
            source += '_Static_assert(offsetof(' + v_name + ', ' + v_field + ') == offsetof(struct ' + c_name + ', ' + c_field + '), "' + c_name + '.' + c_field + '");\n'
            checked += 1
    output = work / "abi.c"
    output.write_text(source)
    subprocess.run([os.environ.get("CC", "clang"), "-std=gnu11", "-ffreestanding", "-fno-builtin", "-fsyntax-only",
                    "-I" + str(loader / "src"), str(output)], check=True)
    print("Apple loader: C/V structure ABI matched (" + str(checked) + " fields)", flush=True)
