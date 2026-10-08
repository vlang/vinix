// SPDX-License-Identifier: GPL-2.0-or-later
// Original independent x86 instruction compiler fixtures; no instruction execution.
module insnfixture

pub const originals = ['arch/x86/include/asm/processor.h',
'arch/x86/include/asm/special_insns.h',
'arch/x86/include/asm/alternative.h',
'arch/x86/include/asm/io.h',
'arch/x86/include/asm/cpufeatures.h']

pub const includes = ['linux/errno.h',
'asm/cpufeatures.h',
'asm/alternative.h',
'asm/special_insns.h']

pub const declarations = '
#include <asm/processor.h>
#include <asm/io.h>
#include <asm/processor.h>
#include <asm/io.h>
_Static_assert(CONFIG_MMU == 1 && CONFIG_X86_5LEVEL == 1 &&
               CONFIG_PGTABLE_LEVELS == 5, "configured original x86 types");
_Static_assert(X86_FEATURE_MOVDIR64B == 16 * 32 + 28 &&
               X86_FEATURE_ENQCMD == 16 * 32 + 29, "original CPUID word IDs");
_Static_assert(sizeof(void *) == 8 && sizeof(size_t) == 8, "x86-64 ABI");
#define FUNCTION_ABI(name, type) \\
    _Static_assert(__builtin_types_compatible_p(__typeof__(&(name)), type), \\
                   "original " #name " ABI")
FUNCTION_ABI(movdir64b, void (*)(void __iomem *, const void *));
FUNCTION_ABI(iosubmit_cmds512, void (*)(void __iomem *, const void *, size_t));
FUNCTION_ABI(native_write_cr0, void (*)(unsigned long));
FUNCTION_ABI(native_write_cr4, void (*)(unsigned long));
FUNCTION_ABI(apply_alternatives, void (*)(struct alt_instr *, struct alt_instr *));
'

pub const scope = 'Compile genuine pinned x86 instruction helpers without claiming MMIO support.

Sixteen strict objects check original declarations, instruction bytes and
unimplemented privileged/alternative symbols. Four rejected probes retain the
old missing-helper and incomplete original-header dependency failures. Nothing
executes MOVDIR64B or supplies CPU capability, mapping or patching services.
'

pub const probes = {
	'declarations': ''
	'movdir-call': 'void instruction(void __iomem *d, const void *s) { movdir64b(d, s); }
'
	'movdir-address': 'void (*instruction_address)(void __iomem *, const void *) = movdir64b;
'
	'iosubmit-zero': 'void submit_zero(void __iomem *d, const void *s) { iosubmit_cmds512(d, s, 0); }
'
	'iosubmit-one': 'void submit_one(void __iomem *d, const void *s) { iosubmit_cmds512(d, s, 1); }
'
	'iosubmit-count': 'void submit_count(void __iomem *d, const void *s, size_t n) { iosubmit_cmds512(d, s, n); }
'
	'privileged-references': 'void privileged_refs(unsigned long v) { write_cr0(v); __write_cr4(v); }
'
	'alternative-references': '
void alternative_refs(volatile void *p, struct alt_instr *a, struct alt_instr *b) {
    clflushopt(p);
    clwb(p);
    apply_alternatives(a, b);
}
'
}

pub const imports = {
	'privileged-references': ['native_write_cr0', 'native_write_cr4']
	'alternative-references': ['apply_alternatives']
}

pub struct Rejection {
pub:
 code string
 errors []string
}

pub const negative = {
	'old-processor': Rejection{ '#include <linux/init.h>
#include <asm/io.h>
', ['undeclared function \'movdir64b\''] }
	'incomplete-special-insns': Rejection{ '#include <linux/init.h>
#include <asm/cpufeatures.h>
#include <asm/special_insns.h>
', ['alternative_io', 'EAGAIN'] }
}
