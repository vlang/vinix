// SPDX-License-Identifier: GPL-2.0-or-later
// Host orchestration is V. The independent native policy observers remain exact.
module main

import os
import json2
import hosttest

struct Prefix {
	text  string
	array string
	local string
}

fn v_function(text string, name string) !string {
	needle := 'fn ${name}('
	mut start := 0
	mut found := -1
	for line in text.split_into_lines() {
		if line.starts_with(needle) && line.contains(') ') && line.ends_with('{') {
			found = start
			break
		}
		start += line.len + 1
	}
	if found < 0 {
		return error('Missing actual function: ${name}')
	}
	if found > 0 {
		previous := text[..found - 1].all_after_last('\n')
		if previous.starts_with('@[export: ') && previous.ends_with(']') {
			found -= previous.len + 1
		}
	}
	brace := found + (text[found..].index('{') or { return error('Missing function brace') })
	mut depth := 1
	mut end := brace + 1
	for depth > 0 && end < text.len {
		if text[end] == `{` { depth++ }
		if text[end] == `}` { depth-- }
		end++
	}
	if depth != 0 { return error('Unterminated actual function: ${name}') }
	return text[found..end] + '\n'
}

fn generated_prefix(raw string) !Prefix {
	array := hosttest.record(raw, 'array')!
	local := hosttest.record(raw, 'linuxkpi__Local')!
	tuple := hosttest.record(raw, 'multi_return_bool_u32_u32_u32_u32')!
	string_record := hosttest.record(raw, 'string')!
	mut literal := ''
	mut constants := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('#define _S(s) ') { literal = line }
		for name in ['directstore_mask', 'feature_movdiri', 'feature_movdir64b'] {
			if line.starts_with('#define linuxkpi__' + name) { constants << line }
		}
	}
	if literal == '' || !array.contains('i64 len;') || !local.contains('u64 online;') {
		return error('Missing actual native-width array/membership descriptors')
	}
	return Prefix{
		text: prefix_front + array + '\n' + local + '\n' + tuple + '\n' +
			string_record + '\n' + literal + '\n' + constants.join('\n') + prefix_tail
		array: array
		local: local
	}
}

fn native_proof(work string, raw string, cc string, includes []string, public string) !json2.Any {
	names := ['linuxkpi__directstore_has', 'linuxkpi__initialise_cpu_features',
		'linuxkpi__cpu_has', 'vinix_linuxkpi_cpu_has']
	mut bodies := map[string]string{}
	all_bodies := hosttest.c_bodies(raw)
	for name in names {
		matches := all_bodies.filter(hosttest.named_body(it, name))
		if matches.len != 1 {
			return error('Missing unique actual generated native body ${name}')
		}
		bodies[name] = matches[0]
		for allocator in ['malloc', 'calloc', 'realloc', 'memdup', 'v_malloc',
			'new_array', 'array_clone', 'array_push'] {
			if hosttest.has_word(matches[0], allocator) {
				return error('Allocation appeared in native policy body ${name}')
			}
		}
	}
	prefix := generated_prefix(raw)!
	variants := ['query', 'constructor', 'frontend']
	selected_names := [names[..1].clone(), names[1..2].clone(), names[2..].clone()]
	expected_imports := [
		['katomic__load_T_u32', 'lib__kpanic'],
		['array_get', 'katomic__load_T_u32', 'katomic__load_T_u64',
			'katomic__store_T_u32', 'lib__kpanic'],
		['cpu__cpuid', 'lib__kpanic', 'linuxkpi__directstore_has'],
	]
	mut results := []json2.Any{}
	for index, name in variants {
		source := os.join_path(work, 'native-${name}.c')
		selected := selected_names[index].map(bodies[it])
		os.write_file(source, prefix.text + '\n\n' + selected.join('\n\n') + '\n')!
		for standard in ['gnu99', 'gnu11'] {
			for optimize in ['O0', 'O1', 'O2'] {
				obj := os.join_path(work, 'native-${name}-${standard}-${optimize}.o')
				argv := [cc, '--target=x86_64-unknown-none', '-std=' + standard,
					'-' + optimize, '-ffreestanding', '-fno-builtin', '-fwrapv',
					'-Wall', '-Wextra', '-Werror', '-nostdinc', '-isystem',
					os.join_path(hosttest.root(), 'kernel/freestnd-c-hdrs'),
					'-c', source, '-o', obj]
				hosttest.run(argv, hosttest.replace_suffix(obj, '.log'))!
				undefined := hosttest.run([hosttest.tool('llvm-nm'), '--undefined-only', obj], '')!.stdout
				mut observed := hosttest.undefined_symbols(undefined)
				mut imports := expected_imports[index].clone()
				if optimize == 'O0' && name in ['query', 'frontend'] { imports << 'v_panic' }
				observed.sort()
				imports.sort()
				if observed != imports || undefined.split_into_lines().len != imports.len {
					return error('Unexpected real native imports for ${obj}: ${undefined}')
				}
				disassembly := hosttest.run([hosttest.tool('llvm-objdump'), '-dr', obj], '')!.stdout
				os.write_file(hosttest.replace_suffix(obj, '.disassembly'), disassembly)!
				for instruction in ['cpuid', 'movdir64b', 'movdiri'] {
					if hosttest.has_word(disassembly, instruction) {
						return error('Instruction appeared in immutable policy/legacy frontend object')
					}
				}
				results << json2.Any(map[string]json2.Any{
					'variant': json2.Any(name)
					'standard': standard
					'optimization': optimize
					'argv': hosttest.strings(argv)
					'object_sha256': hosttest.sha(obj)!
					'undefined': hosttest.strings(observed)
				})
			}
		}
	}
	cold := os.join_path(work, 'native-public.c')
	os.write_file(cold, os.read_file(public)!.all_before('unsigned cpu_policy_feature_id') +
		'const unsigned genuine_directstore_ids[2] = {X86_FEATURE_MOVDIRI,X86_FEATURE_MOVDIR64B};\n')!
	mut cold_objects := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		obj := os.join_path(work, 'native-public-${standard}.o')
		mut argv := [cc, '--target=x86_64-unknown-none', '-std=' + standard, '-O2',
			'-ffreestanding', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter']
		argv << includes
		argv << ['-c', cold, '-o', obj]
		hosttest.run(argv, hosttest.replace_suffix(obj, '.log'))!
		undefined := hosttest.run([hosttest.tool('llvm-nm'), '--undefined-only', obj], '')!.stdout
		if undefined.trim_space() != '' {
			return error('Cold genuine feature/header ABI probe imported runtime symbols')
		}
		cold_objects << json2.Any(map[string]json2.Any{
			'standard': json2.Any(standard)
			'argv': hosttest.strings(argv)
			'object_sha256': hosttest.sha(obj)!
			'undefined': []json2.Any{}
		})
	}
	mut hashes := map[string]json2.Any{}
	for name, body in bodies { hashes[name] = hosttest.text_sha(body) }
	return map[string]json2.Any{
		'objects': json2.Any(results)
		'cold_original_header_objects': cold_objects
		'unchanged_selected_body_sha256': hashes
		'scope': 'Exact host-generated native backend/frontend bodies, scalar observer layout, and unresolved genuine callees. No native CPU boot, actual Local layout, or MOVDIR execution is established.'
	}
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	here := os.join_path(root, 'kernel/linuxkpi')
	policy := os.join_path(here, 'cpu_features_amd64.v')
	bridge := os.join_path(here, 'bridge_amd64.v')
	local := os.join_path(root, 'kernel/x86/cpu/local/local.v')
	linux := os.real_path(hosttest.env_default('LINUXKPI_SOURCE_DIR',
		os.join_path(root, 'third_party/linux-i915/linux-6.6.157')))
	work := hosttest.work_dir(keep, 'vinix-cpu-feature-policy-')!
	defer {
		if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } }
	}
	observed := [policy, bridge, local, @FILE,
		os.join_path(os.dir(@FILE), 'hosttest/core.v'),
		os.join_path(here, 'include/asm/cpufeature.h'),
		os.join_path(here, 'include/vinix/runtime.h'), os.join_path(here, 'include/linux/types.h'),
		os.join_path(here, 'include/generated/autoconf.h'), os.join_path(here, 'upstream.py'),
		os.join_path(here, 'upstream.json'), os.join_path(linux, 'arch/x86/include/asm/cpufeatures.h')]
	initial := hosttest.hashes(observed)!
	local_text := os.read_file(local)!
	for index, field in ['cpu_number', 'online', 'directstore_ecx'] {
		spelling := ['u64', 'u64', 'u32'][index]
		if !local_text.split_into_lines().any(it.fields() == [field, spelling]) {
			return error('Native field changed from the explicit scalar observer: ${field}')
		}
	}
	verification := [hosttest.env_default('PYTHON', 'python3'), os.join_path(here, 'upstream.py'),
		'verify', '--base', os.dir(linux)]
	verified := hosttest.run(verification, os.join_path(work, 'upstream-verification.log'))!
	stage := os.join_path(work, 'stage')
	for module_name in ['linuxkpi', 'katomic', 'lib', 'x86/cpu'] {
		os.mkdir_all(os.join_path(stage, module_name))!
	}
	os.write_file(os.join_path(stage, 'v.mod'), "Module { name: 'cpu_feature_policy_probe' }\n")!
	os.write_file(os.join_path(stage, 'entry.v'), 'module main\nimport linuxkpi as _\nfn main() {}\n')!
	os.cp(policy, os.join_path(stage, 'linuxkpi/policy.v'))!
	frontend := v_function(os.read_file(bridge)!, 'cpu_has')!
	os.write_file(os.join_path(stage, 'linuxkpi/frontend.v'), 'module linuxkpi\nimport x86.cpu\nimport lib\n' + frontend)!
	for module_name, text in {
		'linuxkpi': observers
		'katomic': atomic_observer
		'lib': fatal_observer
		'x86/cpu': cpu_observer
	} {
		os.write_file(os.join_path(stage, module_name, 'observer.v'), text)!
	}
	os.write_file(os.join_path(work, 'policy_model.h'), model_header)!
	v_selection := hosttest.env_default('V', 'v')
	resolved_v := os.real_path(os.find_abs_path_of_executable(v_selection) or { v_selection })
	v_hash := hosttest.sha(resolved_v)!
	arch := if os.uname().machine.to_lower() in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }
	generated := os.join_path(work, 'policy.c')
	array_source := os.join_path(os.dir(resolved_v), 'vlib/builtin/array.v')
	array_hash := hosttest.sha(array_source)!
	argv := [resolved_v, '-no-closures', '-os', 'vinix', '-arch', arch,
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-o', generated, stage]
	mut environment := os.environ()
	environment['VCACHE'] = os.join_path(work, 'vcache')
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	hosttest.command(argv, os.join_path(work, 'generation.log'), 120, environment)!
	raw := os.read_file(generated)!
	prefix := generated_prefix(raw)!
	os.write_file(os.join_path(work, 'model_types.h'), '#include <stdint.h>\ntypedef uint64_t u64; typedef uint32_t u32;\n' +
		'typedef int64_t i64;\ntypedef struct array array; typedef array Array;\n' + prefix.array + '\n' +
		'typedef struct linuxkpi__Local linuxkpi__Local;\n' + prefix.local + '\n')!
	mut names := ['cpu__cpuid', 'katomic__load_T_u32', 'katomic__load_T_u64', 'katomic__store_T_u32',
		'lib__kpanic', 'linuxkpi__cpu_has', 'vinix_linuxkpi_cpu_has', 'linuxkpi__directstore_has',
		'linuxkpi__initialise_cpu_features']
	for suffix in ['configure', 'initialize', 'reset', 'seed', 'state'] {
		names << ['linuxkpi__test_' + suffix, 'policy_test_' + suffix]
	}
	mut bodies := []string{}
	for body in hosttest.c_bodies(raw) {
		if names.any(hosttest.named_body(body, it)) { bodies << body }
	}
	if bodies.len != names.len {
		return error('Missing unique actual policy/observer/generated wrapper body')
	}
	compiled := prefix.text + '\n#include "policy_model.h"\n' + bodies.join('\n\n') + '\n'
	if hosttest.c_bodies(compiled) != bodies {
		return error('Body extraction changed a generated function body')
	}
	os.write_file(os.join_path(work, 'policy-compile.c'), compiled)!
	os.write_file(os.join_path(work, 'test.c'), c_test)!
	cc := hosttest.env_default('CC', 'clang')
	flags := ['-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv', '-fno-strict-aliasing',
		'-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-pthread',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-I', work]
	mut includes := ['-D__KERNEL__', '-include', 'linux/kconfig.h', '-include',
		os.join_path(linux, 'include/linux/compiler_types.h'), '-nostdinc', '-isystem',
		os.join_path(root, 'kernel/freestnd-c-hdrs')]
	for directory in [os.join_path(here, 'include'), os.join_path(linux, 'include'),
		os.join_path(linux, 'include/uapi'), os.join_path(linux, 'arch/x86/include'),
		os.join_path(linux, 'arch/x86/include/uapi')] {
		includes << ['-I', directory]
	}
	public := os.join_path(work, 'public.c')
	os.write_file(public, public_probe)!
	mut outcomes := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		obj := os.join_path(work, '${standard}-core.o')
		mut compile_argv := [cc, '-std=' + standard]
		compile_argv << flags
		compile_argv << ['-Dmain=policy_unused_main', '-Dmalloc=policy_unexpected_malloc',
			'-Dcalloc=policy_unexpected_calloc', '-Drealloc=policy_unexpected_realloc',
			'-Dfree=policy_unexpected_free', '-c', os.join_path(work, 'policy-compile.c'), '-o', obj]
		hosttest.run(compile_argv, os.join_path(work, '${standard}-compile.log'))!
		public_obj := os.join_path(work, '${standard}-public.o')
		mut public_argv := [cc, '-std=' + standard]
		public_argv << flags
		public_argv << includes
		public_argv << ['-c', public, '-o', public_obj]
		hosttest.run(public_argv, os.join_path(work, '${standard}-public.log'))!
		executable := os.join_path(work, '${standard}-runtime')
		mut link_argv := [cc, '-std=' + standard]
		link_argv << flags
		link_argv << [os.join_path(work, 'test.c'), obj, public_obj, '-o', executable]
		hosttest.run(link_argv, os.join_path(work, '${standard}-link.log'))!
		mut sanitizer_env := os.environ()
		sanitizer_env['UBSAN_OPTIONS'] = 'halt_on_error=1'
		sanitizer_env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'
		result := hosttest.command([executable], os.join_path(work, '${standard}-run.log'), 120, sanitizer_env)!
		if result.stderr != '' { return error('Unexpected runtime/sanitizer diagnostic: ${result.stderr}') }
		println(standard + ': ' + result.stdout.trim_space())
		outcomes << json2.Any(map[string]json2.Any{
			'standard': json2.Any(standard)
			'compile_argv': hosttest.strings(compile_argv)
			'public_header_argv': hosttest.strings(public_argv)
			'public_object_sha256': hosttest.sha(public_obj)!
			'link_argv': hosttest.strings(link_argv)
			'object_sha256': hosttest.sha(obj)!
			'output': result.stdout.trim_space()
		})
	}
	native := native_proof(work, raw, cc, includes, public)!
	if initial != hosttest.hashes(observed)! || hosttest.sha(resolved_v)! != v_hash ||
		hosttest.sha(array_source)! != array_hash {
		return error('Policy/profile/test/compiler changed during isolated checks')
	}
	hosttest.write_json(os.join_path(work, 'result.json'), json2.Any(map[string]json2.Any{
		'scope': json2.Any(scope)
		'source_sha256': hosttest.string_map(initial)
		'V_sha256': v_hash
		'generation_argv': hosttest.strings(argv)
		'generated_c_sha256': hosttest.sha(generated)!
		'upstream_verification': map[string]json2.Any{
			'argv': json2.Any(hosttest.strings(verification))
			'output': verified.stdout.trim_space()
		}
		'compiler_metadata': map[string]json2.Any{
			'selection': json2.Any('Exact named generated bodies and actual descriptors; unrelated builtin runtime is not linked into this host model.')
			'builtin_array_source': array_source
			'builtin_array_source_sha256': array_hash
			'unchanged_body_count': bodies.len
			'unchanged_body_sha256': hosttest.strings(bodies.map(hosttest.text_sha(it)))
		}
		'exact_frontend_sha256': hosttest.text_sha(frontend)
		'native_compiler_proof': native
		'host_results': outcomes
		'observer_scope': 'Scalar membership and atomics are private host observers. Policy and frontend bodies unchanged. Boot sampling, AP ordering, native Local layout and actual MOVDIR execution require separate native verification.'
	}))!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'usage: cpu_feature_policy.v [--keep-dir KEEP_DIR]', scope) or {
		eprintln(err); exit(2)
	}
	run_profile(keep) or { eprintln(err); exit(1) }
}

const scope = 'Run the unchanged native MOVDIR boot policy with explicit host observers.

Only CPU membership, leaf-one CPUID, atomic publication and fatal handling are
modeled. The real policy and real public cpu_has body run unchanged; genuine
Linux feature IDs and public macros are compiled. This does not execute MOVDIR,
boot APs, establish kernel GS, support hotplug, or implement other word-16 bits.
'

const observers = '
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
@[export: \'policy_test_configure\']
fn test_configure(members voidptr, count i64) {
    C.policy_model_configure(unsafe { &cpu_locals }, members, count)
}
@[export: \'policy_test_reset\']
fn test_reset() {
    boot_directstore_bits = 0
    boot_directstore_count = 0
    boot_directstore_ready = 0
}
@[export: \'policy_test_seed\']
fn test_seed(bits u32, count u32, ready u32) {
    boot_directstore_bits = bits
    boot_directstore_count = count
    boot_directstore_ready = ready
}
@[export: \'policy_test_initialize\']
fn test_initialize() { initialise_cpu_features() }
@[export: \'policy_test_state\']
fn test_state(field u32) u32 {
    if field == 0 { return boot_directstore_bits }
    if field == 1 { return boot_directstore_count }
    return katomic.load(&boot_directstore_ready)
}
'

const atomic_observer = '
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
'

const cpu_observer = '
module cpu
#include "policy_model.h"
fn C.policy_model_cpuid(u32, u32, &u32, &u32) bool
pub fn cpuid(leaf u32, subleaf u32) (bool, u32, u32, u32, u32) {
    mut ecx := u32(0)
    mut edx := u32(0)
    ok := C.policy_model_cpuid(leaf, subleaf, unsafe { &ecx }, unsafe { &edx })
    return ok, 0, 0, ecx, edx
}
'

const fatal_observer = '
module lib
#include "policy_model.h"
@[noreturn]
fn C.policy_model_panic(&char)
@[noreturn]
pub fn kpanic(frame voidptr, message &char) { C.policy_model_panic(message) }
'

const model_header = '
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
'

const c_test = '
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
#define CHECK(x) do { __atomic_fetch_add(&assertions, 1, __ATOMIC_RELAXED); \\
    if (!(x)) { fprintf(stderr,"CPU policy assertion line %d: %s\\n",__LINE__,#x); abort(); } } while(0)
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
    if (!expect_panic) { fprintf(stderr,"Unexpected policy panic: %s\\n",message); abort(); }
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
    printf("PASS: %llu MOVDIR policy assertions\\n", (unsigned long long)assertions);
    return 0;
}
'

const prefix_front = '#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef uint8_t u8; typedef uint32_t u32; typedef uint64_t u64; typedef int64_t i64;
#define VNORETURN __attribute__((noreturn))
typedef struct string string;
typedef struct array array;
typedef array Array;
typedef struct linuxkpi__Local linuxkpi__Local;
typedef struct multi_return_bool_u32_u32_u32_u32 multi_return_bool_u32_u32_u32_u32;
'

const prefix_tail = '
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
'

const public_probe = '#include <asm/cpufeature.h>
_Static_assert(X86_FEATURE_MOVDIRI == 539 && X86_FEATURE_MOVDIR64B == 540,
    "genuine pinned leaf-seven ECX IDs");
_Static_assert(__builtin_types_compatible_p(__typeof__(&vinix_linuxkpi_cpu_has),
    bool (*)(unsigned int)), "real public CPU feature ABI");
unsigned cpu_policy_feature_id(unsigned which) {
    return which == 0 ? X86_FEATURE_MOVDIRI : which == 1 ? X86_FEATURE_MOVDIR64B : X86_FEATURE_XMM4_1;
}
bool cpu_policy_boot_query(unsigned feature) { return boot_cpu_has(feature); }
bool cpu_policy_static_query(unsigned feature) { return static_cpu_has(feature); }
'
