// SPDX-License-Identifier: GPL-2.0-or-later
// Exact worker-priority algorithm with independently observed V transports.
module main

import os
import json2
import hosttest

const scope = 'Execute unchanged production worker_set_nice and public ABI adapter with V CPU/task/IRQ/atomic/scheduler transports and smaller record metadata. Separate historical controls reproduce structural Process ownership acceptance and forbidden IRQ-frame publication. No native dispatch, scheduling-weight or retained-allocation claim.'

fn stage(work string) !([]string, json2.Any) {
	root := hosttest.root()
	where := work + '/stage'
	for directory in ['linuxkpi', 'workerpriorityfixture', 'proc', 'sched', 'katomic', 'errno',
		'x86/cpu/local', 'x86/cpu'] {
		os.mkdir_all(where + '/' + directory)!
	}
	path := root + '/kernel/linuxkpi/priority_amd64.v'
	actual := hosttest.v_function(os.read_file(path)!, 'worker_set_nice')!
	identity := 'voidptr(t.process) != voidptr(kernel_process)'
	irq := ' || local.maskable_irq_depth != 0'
	if actual.count(identity) != 1 || actual.count(irq) != 1 {
		return error('Missing unique native identity/IRQ guards')
	}
	old_identity := actual.replace('fn worker_set_nice(', 'fn historical_identity(').replace("'vinix_linuxkpi_worker_set_nice'", "'wph_historical_identity'").replace(identity, 't.process != kernel_process')
	old_irq := actual.replace('fn worker_set_nice(', 'fn historical_irq(').replace("'vinix_linuxkpi_worker_set_nice'", "'wph_historical_irq'").replace(irq, '')
	os.write_file(where + '/linuxkpi/priority_selected.v', '@[has_globals]\nmodule linuxkpi\nimport errno\nimport katomic\nimport proc\nimport sched\nimport x86.cpu\nimport x86.cpu.local as cpulocal\n__global preempt_depth [256]u32\n' + actual + '\n// Labeled historical controls; actual production body above is unchanged.\n' + old_identity + '\n' + old_irq +
		"\n@[export:'wph_set_preempt']pub fn fixture_set(index u32,value u32){preempt_depth[index]=value;sched.fixture_owner()}\n@[export:'wph_get_preempt']pub fn fixture_get(index u32)u32{return preempt_depth[index]}\n")!
	for name in ['core.v', 'contract.h'] {
		os.cp(os.dir(@FILE) + '/workerpriorityfixture/' + name, where + '/workerpriorityfixture/' + name)!
	}
	os.write_file(where + '/proc/transport.v', 'module proc\nimport workerpriorityfixture as model\npub type Thread=model.Thread\npub type Process=model.Process\npub fn current_thread()&Thread{return model.current()}\n')!
	os.write_file(where + '/sched/transport.v', '@[has_globals]\nmodule sched\nimport proc\nimport workerpriorityfixture as model\n__global kernel_process &proc.Process\npub fn fixture_owner(){kernel_process=model.kernel_owner()}\npub fn reschedule(){model.reschedule()}\n')!
	os.write_file(where + '/x86/cpu/local/transport.v', 'module local\nimport workerpriorityfixture as model\npub type Local=model.Local\npub fn current()&Local{return model.cpu_local()}\n')!
	os.write_file(where + '/x86/cpu/transport.v', 'module cpu\nimport workerpriorityfixture as model\npub fn interrupt_toggle(next bool)bool{return model.interrupt_toggle(next)}\n')!
	os.write_file(where + '/katomic/transport.v', 'module katomic\nimport workerpriorityfixture as model\npub fn load[T](value &T)T{return model.load(value)}\npub fn store[T](mut value T,item T){model.store(unsafe{&value},item)}\n')!
	os.write_file(where + '/errno/transport.v', 'module errno\npub const einval=22\npub const ewouldblock=11\npub const eperm=1\n')!
	os.write_file(where + '/v.mod', "Module{name:'worker_priority_fixture'}\n")!
	os.write_file(where + '/entry.v', 'module main\nimport workerpriorityfixture as _\nimport linuxkpi as _\nfn main(){}\n')!
	return [path, @FILE, root + '/kernel/linuxkpi/include/vinix/runtime.h'], {
		'actual_v_body_sha256':              json2.Any(hosttest.text_sha(actual))
		'historical_identity_v_body_sha256': hosttest.text_sha(old_identity)
		'historical_irq_v_body_sha256':      hosttest.text_sha(old_irq)
		'scope':                             'Only separately named historical controls replace identity comparison or omit IRQ-depth rejection; actual staged production function is unchanged.'
	}
}

fn select_source(raw string) !string {
	mut bodies := []string{}
	for body in hosttest.c_bodies(raw) {
		line := body.all_before('\n')
		if hosttest.named_body(body, 'main') && !body.contains('workerpriorityfixture__run') {
			continue
		}
		if ['workerpriorityfixture__', 'linuxkpi__', 'sched__', 'proc__', 'cpu__', 'local__',
			'katomic__'].any(line.contains(it))
			|| line.contains(' wph_') || hosttest.named_body(body, 'main') || hosttest.named_body(body, 'vinix_linuxkpi_worker_set_nice') {
			bodies << body
		}
	}
	if bodies.len < 30 { return error('Missing priority fixture bodies') }
	joined := bodies.join('\n')
	mut metadata := []string{}
	mut globals := []string{}
	mut constants := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && line.contains('workerpriorityfixture__') && !line.contains('Array_fixed_') && line !in metadata {
			metadata << line
		}
		if line.starts_with('typedef ') && line.contains('Array_fixed_') {
			name := line.fields().last().all_before('[').all_before(';')
			if joined.contains(name) { metadata << line }
		}
		if line.starts_with('#define ') && ['errno__', 'linuxkpi__', 'workerpriorityfixture__'].any(line.contains(it)) {
			constants << line
		}
		if line.ends_with(';') && !line.contains('(') && !line.starts_with('typedef ') && !line.starts_with(' ') && !line.starts_with('\t')
			&& ['workerpriorityfixture__', 'linuxkpi__', 'sched__'].any(line.contains(it)) {
			globals << line
		}
	}
	mut records := []string{}
	for name in ['workerpriorityfixture__Process', 'workerpriorityfixture__Thread',
		'workerpriorityfixture__Local'] {
		records << hosttest.record(raw, name)!
	}
	declarations := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	prefix := '#include "workerpriorityfixture/contract.h"\ntypedef int32_t i32; typedef int64_t i64; typedef void *voidptr;\n#define VNORETURN __attribute__((noreturn))\n' + metadata.join('\n') + '\n' + records.join('\n') + '\n' + globals.join('\n') + '\n' + constants.join('\n') + '\n' + declarations.join('\n') + '\n'
	selected := prefix + bodies.join('\n\n') + '\n'
	if hosttest.c_bodies(selected) != bodies { return error('Changed selected generated body') }
	return selected
}

fn compile_input(argv []string, source string, object string, log string, environment map[string]string) !json2.Any {
	preprocessed := object + '.i'
	depfile := object + '.d'
	hosttest.command([...argv, '-E', '-dD', '-MD', '-MF', depfile, '-MQ', object, source, '-o',
		preprocessed], log + '.preprocess', 180, environment)!
	before := hosttest.hashes(hosttest.dependency_paths(os.read_file(depfile)!, object)!)!
	hosttest.command([...argv, '-c', source, '-o', object], log, 180, environment)!
	if before != hosttest.hashes(before.keys())! { return error('Compiler inputs changed') }
	return {
		'source':              json2.Any(source)
		'source_sha256':       hosttest.sha(source)!
		'object':              object
		'object_sha256':       hosttest.sha(object)!
		'preprocessed':        preprocessed
		'preprocessed_sha256': hosttest.sha(preprocessed)!
		'dependency_sha256':   hosttest.string_map(before)
		'compiler_argv':       hosttest.strings(argv)
	}
}

fn run(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	hosttest.verify_upstream(linux, hosttest.upstream_pin()!)!
	work := hosttest.work_dir(keep, 'vinix-worker-priority-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	mut inputs, history := stage(work)!
	inputs << os.walk_ext(os.dir(@FILE) + '/workerpriorityfixture', '.v')
	inputs << os.walk_ext(os.dir(@FILE) + '/workerpriorityfixture', '.h')
	for extension in ['.v', '.h'] {
		inputs << os.walk_ext(root + '/tests/linuxkpi/hosttest', extension)
	}
	before := hosttest.hashes(inputs)!
	compiler := os.real_path(hosttest.command(['sh', '-c',
		'. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root], '', 30, os.environ())!.stdout)
	compiler_hash := hosttest.sha(compiler)!
	mut environment := os.environ()
	environment['VCACHE'] = work + '/vcache'
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
	environment['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	raw_path := work + '/generated.c'
	generation := [compiler, '-nocache', '-no-closures', '-os', 'vinix', '-arch', 'amd64',
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-d', 'nofloat', '-d', 'linuxkpi',
		'-o', raw_path, work + '/stage']
	hosttest.command(generation, work + '/generation.log', 180, environment)!
	raw := os.read_file(raw_path)!
	selected_text := select_source(raw)!
	selected := work + '/selected.c'
	os.write_file(selected, selected_text)!
	names := ['linuxkpi__worker_set_nice', 'vinix_linuxkpi_worker_set_nice']
	mut production_bodies := []string{}
	mut production_hashes := map[string]string{}
	for name in names {
		body := hosttest.extract_body(raw, name)!
		if body != hosttest.extract_body(selected_text, name)! || ['__eq_lhs_', '__eq_rhs_', '__ptr_eq_',
			'Process__eq'].any(body.contains(it)) {
			return error('Changed/copied actual priority body ' + name)
		}
		for allocator in ['malloc', 'calloc', 'realloc', 'memdup', 'v_malloc', 'new_array', 'array_push',
			'array_clone'] {
			if hosttest.has_word(body, allocator) {
				return error('Allocator in actual priority body')
			}
		}
		production_bodies << body
		production_hashes[name] = hosttest.text_sha(body)
	}
	first := hosttest.c_bodies(selected_text)[0]
	metadata := selected_text.all_before(first).replace('#include "workerpriorityfixture/contract.h"', '#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\ntypedef uint8_t u8; typedef uint32_t u32; typedef uint64_t u64;\n')
	production := work + '/production.c'
	os.write_file(production, metadata + '\ni64 v_fixed_index(i64,i64);\ni64 v_fixed_index_u64(u64,i64);\n' + production_bodies.join('\n\n') + '\n')!
	if hosttest.c_bodies(os.read_file(production)!) != production_bodies {
		return error('Production-only body changed')
	}
	mut include_args := ['-D__KERNEL__', '-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-include',
		root + '/tests/linuxkpi/host_types.h']
	for path in [work + '/stage', root + '/kernel/linuxkpi/include', linux + '/include',
		linux + '/include/uapi', linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] {
		include_args << ['-I', path]
	}
	mut common := ['clang', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv', '-Wall', '-Wextra',
		'-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer']
	$if macos {
		common << ['-arch', 'x86_64']
	}
	mut profiles := []json2.Any{}
	mut objects := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O1', 'O2'] {
			tag := standard + '-' + optimization
			object := work + '/' + tag + '.o'
			proof := compile_input([...common, '-std=' + standard, '-' + optimization, ...include_args], selected, object, object + '.compile.log', environment)!
			imports := hosttest.command(['nm', '-u', object], object + '.imports.log', 30, environment)!.stdout
			if hosttest.allocation_symbols(imports) { return error('Fixture imports allocator') }
			executable := work + '/' + tag
			hosttest.command([...common, object, '-o', executable], executable + '.link.log', 180, environment)!
			result := hosttest.command([executable], executable + '.run.log', 180, environment)!
			if !result.stdout.contains('PASS: V worker nice ownership') || !result.stdout.contains('cases=64590 historical=2') || result.stderr != '' {
				return error('Incomplete/diagnosed priority regression')
			}
			profiles << json2.Any({
				'standard':          json2.Any(standard)
				'optimization':      optimization
				'compiled':          proof
				'executable_sha256': hosttest.sha(executable)!
				'run_log':           executable + '.run.log'
				'output':            result.stdout
			})
			native_object := work + '/production-' + tag + '.o'
			native_argv := ['clang', '--target=x86_64-unknown-none', '-std=' + standard,
				'-' + optimization, '-ffreestanding', '-fno-builtin', '-fwrapv', '-Wall', '-Wextra',
				'-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-nostdinc', '-isystem',
				root + '/kernel/freestnd-c-hdrs']
			native_proof := compile_input(native_argv, production, native_object, native_object + '.compile.log', environment)!
			undefined := hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only', native_object], native_object + '.imports.log', 30, environment)!.stdout
			mut actual := []string{}
			for line in undefined.split_into_lines() {
				if line.fields().len > 0 { actual << line.fields().last() }
			}
			actual.sort()
			mut expected := ['cpu__interrupt_toggle', 'katomic__load_T_bool', 'katomic__store_T_bool',
				'katomic__store_T_v_int', 'local__current', 'proc__current_thread', 'sched__reschedule',
				'v_fixed_index_u64']
			expected.sort()
			if actual != expected || hosttest.allocation_symbols(undefined) {
				return error('Unexpected production-only imports: ' + undefined)
			}
			objects << json2.Any({
				'standard':     json2.Any(standard)
				'optimization': optimization
				'compiled':     native_proof
				'imports':      hosttest.strings(actual)
			})
			println(tag + ': ' + result.stdout.trim_space())
		}
	}
	if before != hosttest.hashes(before.keys())! || compiler_hash != hosttest.sha(compiler)! {
		return error('Priority source/compiler changed')
	}
	hosttest.write_json(work + '/result.json', {
		'scope':                   json2.Any(scope)
		'source_sha256':           hosttest.string_map(before)
		'compiler':                compiler
		'compiler_sha256':         compiler_hash
		'generation_argv':         hosttest.strings(generation)
		'generated_sha256':        hosttest.sha(raw_path)!
		'selected_sha256':         hosttest.sha(selected)!
		'production_body_sha256':  hosttest.string_map(production_hashes)
		'historical_controls':     history
		'profiles':                profiles
		'production_only_objects': objects
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: worker_priority.v [--keep-dir NEW]', scope) or {
		eprintln(err)
		exit(2)
	}
	run(keep) or {
		eprintln(err)
		exit(1)
	}
}
