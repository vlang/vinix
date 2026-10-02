#!/usr/bin/env python3
"""Run exact production CPUID/MSR policy with only hardware-port adapters."""
from pathlib import Path
import re
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[2]


def replace_function(source, name, replacement):
    match = re.search(r'(?m)^static [\w *]+ ' + name + r'\([^;]*?\) \{', source)
    if not match:
        raise RuntimeError(f'missing hardware adapter {name}')
    start = source.index('{', match.start())
    depth, end = 1, start + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[:match.start()] + replacement + source[end:]


ADAPTERS = r'''
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned vendor, max_leaf, max_subleaf, ext_max;
static uint32_t leaf7, leaf72, amd_bits;
static uint64_t arch_bits, control, expected_control;
static unsigned arch_reads, ctrl_reads, ctrl_writes;
static bool ignored_write;
static void mitigation_cpuid(uint32_t leaf, uint32_t subleaf,
                             uint32_t *a, uint32_t *b, uint32_t *c, uint32_t *d) {
    *a = *b = *c = *d = 0;
    if (!leaf) {
        *a = max_leaf;
        if (vendor == 1) { *b = 0x756e6547; *d = 0x49656e69; *c = 0x6c65746e; }
        if (vendor == 2) { *b = 0x68747541; *d = 0x69746e65; *c = 0x444d4163; }
    } else if (leaf == 7 && !subleaf) { assert(max_leaf >= 7); *a = max_subleaf; *d = leaf7; }
    else if (leaf == 7 && subleaf == 2) { assert(max_subleaf >= 2); *d = leaf72; }
    else if (leaf == 0x80000000) { assert(vendor == 2); *a = ext_max; }
    else if (leaf == 0x80000008) { assert(vendor == 2 && ext_max >= leaf); *b = amd_bits; }
    else assert(!"unexpected CPUID port");
}
static uint64_t mitigation_rdmsr(uint32_t msr) {
    if (msr == 0x10a) { assert(vendor == 1 && (leaf7 & (1u << 29))); arch_reads++; return arch_bits; }
    assert(msr == 0x48 && expected_control); ctrl_reads++; return control;
}
static void mitigation_wrmsr(uint32_t msr, uint64_t value) {
    assert(msr == 0x48 && expected_control);
    assert(value == (UINT64_C(0x8000000000000000) | expected_control));
    ctrl_writes++; if (!ignored_write) control = value;
}
int kprintf(const char *fmt, ...) { (void)fmt; return 0; }
'''

TESTS = r'''
int main(void) {
    assert(!vinix_x86_mitigations_setup(0));
    assert(!vinix_x86_mitigations_setup(UINT64_MAX));
    assert(vinix_x86_mitigations_setup(2));
    assert(!vinix_x86_mitigations_setup(2));
    assert(!vinix_x86_mitigations_initialise(2));
    unsigned cases = 0;
    for (vendor = 0; vendor < 3; vendor++) {
      for (unsigned mask = 0; mask < 1024; mask++) {
       for (unsigned leaves = 0; leaves < 4; leaves++) {
        max_leaf = leaves & 1 ? 7 : 1;
        max_subleaf = leaves & 2 ? 2 : 0;
        ext_max = leaves & 1 ? 0x80000008 : 0x80000001;
        leaf7 = ((mask & 1) ? 1u << 26 : 0) | ((mask & 2) ? 1u << 27 : 0)
              | ((mask & 4) ? 1u << 31 : 0) | ((mask & 8) ? 1u << 10 : 0)
              | ((mask & 16) ? 1u << 29 : 0);
        leaf72 = ((mask & 32) ? 1u << 4 : 0) | ((mask & 64) ? 1u << 2 : 0);
        amd_bits = ((mask & 1) ? 1u << 14 : 0) | ((mask & 2) ? 1u << 15 : 0)
                 | ((mask & 4) ? 1u << 24 : 0) | ((mask & 8) ? 1u << 12 : 0)
                 | ((mask & 128) ? 1u << 16 : 0) | (1u << 25); /* VIRT_SSBD is not SSBD. */
        arch_bits = ((mask & 128) ? UINT64_C(1) << 1 : 0)
                  | ((mask & 256) ? UINT64_C(1) << 28 : 0)
                  | ((mask & 512) ? UINT64_C(1) << 5 : 0); /* MDS_NO cannot suppress RFDS. */
        unsigned flags = 0; uint64_t user = 0;
        bool present = leaves & 1;
        bool arch = vendor == 1 && present && (mask & 16);
        bool ibrs = vendor && present && (mask & 1);
        bool enhanced = ibrs && (mask & 128) && (vendor == 2 || arch);
        bool ibpb = vendor == 1 ? ibrs : vendor == 2 && present && (mask & 8);
        if (ibpb) flags |= 1 | 256;
        if (enhanced) { flags |= 4; user |= 1; } else if (ibrs) flags |= 2;
        if (vendor && present && (mask & 2)) { flags |= 16; user |= 2; }
        if (vendor && present && (mask & 4)) { flags |= 32; user |= 4; }
        if (vendor == 1 && present) {
            if ((mask & 8) || (arch && (mask & 256))) flags |= 8;
            if (max_subleaf >= 2 && (mask & 32)) { flags |= 64; user |= 1024; }
            if (max_subleaf >= 2 && (mask & 64)) { flags |= 128; user |= 64; }
        }
        expected_control = user | (ibrs ? 1 : 0);
        arch_reads = ctrl_reads = ctrl_writes = 0;
        control = UINT64_C(0x8000000000000000); ignored_write = false;
        assert(vinix_x86_mitigations_initialise(cases & 1));
        struct vinix_x86_mitigation_policy p = vinix_x86_mitigation_policies[cases & 1];
        assert(p.flags == flags);
        assert(p.kernel_control == (expected_control ? control : 0));
        assert(p.user_control == (user | (expected_control ? UINT64_C(0x8000000000000000) : 0)));
        assert(arch_reads == (unsigned)arch);
        assert(ctrl_reads == (expected_control ? 2u : 0u));
        assert(ctrl_writes == (expected_control ? 1u : 0u));
        cases++;
       }
      }
    }
    vendor = 1; max_leaf = 7; max_subleaf = 0; leaf7 = 1u << 26;
    expected_control = 1; control = UINT64_C(0x8000000000000000); ignored_write = true;
    /* A virtual CPU that enumerates a control but ignores it cannot report success. */
    assert(!vinix_x86_mitigations_initialise(0));
    free(vinix_x86_mitigation_policies);
    puts("CPU MITIGATION POLICY PASS: 12288 vendor/leaf/control cases, MSR gates and readback failure");
}
'''


def main():
    source = (ROOT / 'kernel/c/x86_mitigations.c').read_text()
    for name in ('mitigation_cpuid', 'mitigation_rdmsr', 'mitigation_wrmsr'):
        source = replace_function(source, name, '')
    source = source.replace('#include "x86_mitigations.h"', '')
    source = source.replace('#if defined(__x86_64__)', '', 1)
    if not source.rstrip().endswith('#endif'):
        raise RuntimeError('unexpected architecture guard')
    source = source.rstrip()[:-6]
    header = (ROOT / 'kernel/c/x86_mitigations.h').read_text()
    with tempfile.TemporaryDirectory(prefix='vinix-cpu-policy-') as directory:
        work = Path(directory)
        (work / 'test.c').write_text(header + ADAPTERS + source + TESTS)
        subprocess.run(['clang', '-std=gnu11', '-O1', '-g', '-Wall', '-Wextra', '-Werror',
                        '-fsanitize=address,undefined', str(work / 'test.c'), '-o', str(work / 'test')], check=True)
        subprocess.run([str(work / 'test')], check=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
