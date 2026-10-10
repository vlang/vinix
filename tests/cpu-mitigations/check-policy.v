// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
import fixturehost
import hosttest
import os

#include <fcntl.h>
#include <unistd.h>
fn C.fcntl(i32, i32, ...i32) i32
fn C.open(&char, i32, ...i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32

const adapters = r'
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned vendor, max_leaf, max_subleaf, ext_max;
static uint32_t leaf7, leaf72, amd_bits;
static uint64_t arch_bits, control, expected_control;
static unsigned arch_reads, ctrl_reads, ctrl_writes;
static bool ignored_write;
static unsigned allocations;
static bool fail_allocation;
void *vinix_mitigation_test_calloc(size_t count, size_t size) {
    allocations++;
    assert(count == 2 && size == 32);
    return fail_allocation ? NULL : calloc(count, size);
}
void vinix_mitigation_test_cpuid(uint32_t leaf, uint32_t subleaf,
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
uint64_t vinix_mitigation_test_rdmsr(uint32_t msr) {
    if (msr == 0x10a) { assert(vendor == 1 && (leaf7 & (1u << 29))); arch_reads++; return arch_bits; }
    assert(msr == 0x48 && expected_control); ctrl_reads++; return control;
}
void vinix_mitigation_test_wrmsr(uint32_t msr, uint64_t value) {
    assert(msr == 0x48 && expected_control);
    assert(value == (UINT64_C(0x8000000000000000) | expected_control));
    ctrl_writes++; if (!ignored_write) control = value;
}
int kprintf(const char *fmt, ...) { (void)fmt; return 0; }
'
const tests = r'
int main(void) {
    assert(!vinix_x86_mitigations_setup(0));
    assert(!vinix_x86_mitigations_setup(UINT64_MAX));
    assert(!allocations);
    fail_allocation = true;
    assert(!vinix_x86_mitigations_setup(2));
    assert(!vinix_x86_mitigation_policies);
    assert(!vinix_x86_mitigations_initialise(0));
    fail_allocation = false;
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
    assert(allocations == 2); /* One failed attempt and one boot allocation. */
    free(vinix_x86_mitigation_policies);
    puts("CPU MITIGATION POLICY PASS: 12288 vendor/leaf/control cases, MSR gates and readback failure");
}
'

struct Config {
 text_encoding string
 root string
 work string
 caller string
 environment map[string]string
}
fn append_path(parent string, name string) string { return parent.trim_right('/') + '/' + name }
fn (c Config) path(name string) string { return append_path(c.root, name) }
fn (c Config) output(name string) string { return append_path(c.work, name) }
fn (c Config) inherited(argv []string, environment map[string]string) ! {
 fixturehost.inherited_command_environment_preferred(argv, environment, c.caller)!
}
fn (c Config) capture(argv []string) !string {
 // Reserve a closed stdout while the unchanged single-stream capture owns
 // its pipes. This leaves caller stdin and inherited command slots intact.
 closed := C.fcntl(1, C.F_GETFD) < 0
 if closed {
  descriptor := C.open(c'/dev/null', C.O_WRONLY)
  if descriptor < 0 { return error('Unable to reserve closed stdout') }
  if descriptor != 1 {
   if C.dup2(descriptor, 1) < 0 { C.close(descriptor); return error('Unable to reserve closed stdout') }
   C.close(descriptor)
  }
  if C.fcntl(1, C.F_SETFD, C.FD_CLOEXEC) != 0 { C.close(1); return error('Unable to protect stdout reservation') }
 }
 defer { if closed { C.close(1) } }
 return fixturehost.capture_in_preferred(argv, '', c.environment, false, '', false, c.caller)!
}
fn imports_forbidden(text string) bool {
 mut word := ''
 for ch in (text + ' ').runes() {
  if hosttest.module_word_rune(ch) { word += ch.str(); continue }
  name := if word.starts_with('_') { word[1..] } else { word }
  if name in ['malloc','calloc','realloc','free','memdup'] || name.starts_with('new_array') { return true }
  word = ''
 }
 return false
}
fn (c Config) execute() ! {
 fixturehost.write(c.output('v.mod'), "Module { name: 'vinix_cpu_policy_tests' }\n")!
 source := c.path('kernel/x86/cpu/initialisation')
 hosttest.module_copy_tree(append_path(source, 'mitigations_amd64.v'), c.output('policy.v'))!
 hosttest.module_copy_tree(append_path(source, 'mitigation_ports_amd64.v'), c.output('ports.v'))!
 compiler := c.capture(['sh','-c','. "$1/build-support/find-v.sh"; printf "%s" "$V"','find-v',c.root])!
 mut environment := c.environment.clone()
 environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
 c.inherited([compiler,'-shared','-no-builtin','-os','vinix','-target-libc-headers','-nofloat','-gc','none','-manualfree','-d','mitigation_test','-o',c.output('policy.c'),c.work], environment)!
 cc := hosttest.env_default('CC','clang')
 fixturehost.write(c.output('host_ports.h'), '#include <stddef.h>\nint kprintf(const char *, ...);\nvoid *vinix_mitigation_test_calloc(size_t, size_t);\n')!
 common := [cc,'-std=gnu11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-iquote',c.path('kernel/c')]
 c.inherited([...common, '-I',c.path('kernel/c'),'-Wno-unused-function','-ffreestanding','-fno-builtin','-Dcalloc=vinix_mitigation_test_calloc','-fno-strict-aliasing','-include',c.output('host_ports.h'),'-c',c.output('policy.c'),'-o',c.output('policy.o')], c.environment)!
 // Decode nm with the actual invoking Python codec and newline policy.
 // This mechanical text/process leaf receives zero migration credit.
 decode := 'import json,subprocess,sys;value=subprocess.check_output(sys.argv[2:],text=True,encoding=sys.argv[1]);sys.stdout.buffer.write(json.dumps(value).encode("ascii"))'
 wire := c.capture(['python3','-c',decode,c.text_encoding,'nm','-u',c.output('policy.o')])!
 imports := hosttest.decode_json(wire)!.str()
 if imports_forbidden(imports) { return error('unexpected allocator import in CPU policy:\n' + imports) }
 fixturehost.write(c.output('test.c'), '#include "x86_mitigations.h"\n' + adapters + tests)!
 c.inherited([...common, c.output('test.c'),c.output('policy.o'),'-o',c.output('test')], c.environment)!
 c.inherited([c.output('test')], c.environment)!
}
fn main() {
 parsed := hosttest.parse_arguments(os.args[1..], [hosttest.Option{'--root',true,[]},hosttest.Option{'--work',true,[]},hosttest.Option{'--caller-arch',true,['arm64','amd64']},hosttest.Option{'--parent-stdin',true,[]},hosttest.Option{'--text-encoding',true,[]}], 0, 'CPU policy host controller', 'Private frontend-owned source and output directories') or { eprintln(err); exit(2) }
 v := parsed.options
 if '--root' !in v || '--work' !in v { eprintln('Missing root/work directory'); exit(2) }
 input := fixturehost.read('/dev/stdin') or { eprintln(err.msg()); exit(1) }
 request := hosttest.decode_json(input) or { eprintln(err.msg()); exit(1) }
 mut environment := map[string]string{}
 for value in request.as_array() {
  pair := value.as_array()
  key := hex.decode(pair[0].str()) or { eprintln(err.msg()); exit(1) }
  content := hex.decode(pair[1].str()) or { eprintln(err.msg()); exit(1) }
  environment[key.bytestr()] = content.bytestr()
 }
 descriptor := (v['--parent-stdin'] or { eprintln('Missing parent descriptor'); exit(2) }).int()
 if descriptor >= 0 {
  if C.dup2(i32(descriptor), 0) < 0 { eprintln('Unable to restore parent stdin'); exit(1) }
  C.close(i32(descriptor))
 } else { C.close(0) }
 c := Config{text_encoding:v['--text-encoding'],root:v['--root'],work:v['--work'],caller:v['--caller-arch'],environment:environment}
 c.execute() or { eprintln(err.msg()); exit(1) }
}
