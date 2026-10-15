// SPDX-License-Identifier: GPL-2.0-or-later
// Actual generated V RCU, original callback records and independent transport.
module main

import os
import json2
import hosttest

const scope = 'Exercise actual generated production RCU with genuine original callback heads. Host pthread transport observes implicit CPU scopes and trusted quiescent boundaries; actual IRQ gates, IRET, native scheduler placement and retained kernel allocations require the separate kernel guest fixture.'

fn command(argv []string, log string, env map[string]string) !hosttest.Result {
	return hosttest.command(argv, log, 180, env)
}

fn compile_input(argv []string, source string, object string, log string, env map[string]string) !json2.Any {
	// Keep actual compiler-visible inputs and all native include dependencies.
	preprocessed := object + '.i'
	depfile := object + '.d'
	command([...argv, '-E', '-dD', '-MD', '-MF', depfile, '-MT', object, source, '-o', preprocessed], log + '.preprocess', env)!
	dependencies := hosttest.dependency_paths(os.read_file(depfile)!, object)!
	before := hosttest.hashes(dependencies)!
	command([...argv, '-c', source, '-o', object], log, env)!
	if before != hosttest.hashes(dependencies)! { return error('Compiler dependency changed during object build: ${object}') }
	return map[string]json2.Any{
		'object': json2.Any(object)
		'object_sha256': hosttest.sha(object)!
		'actual_source_sha256': hosttest.sha(source)!
		'compiler_visible_input_sha256': hosttest.sha(preprocessed)!
		'dependency_sha256': hosttest.string_map(before)
	}
}

fn selected_source(raw string, prefix string, header string, global_prefixes []string) !string {
	mut bodies := []string{}
	mut declarations := []string{}
	for body in hosttest.c_bodies(raw) {
		line := body.all_before('\n')
		if line.contains(prefix) || line.contains(' vkr_rcu_') || line.contains(' vkm_') ||
			line.contains(' call_rcu(') || line.contains(' synchronize_rcu') || line.contains(' rcu_barrier(') || line.contains(' get_state_synchronize_rcu(') || line.contains(' start_poll_synchronize_rcu(') || line.contains(' poll_state_synchronize_rcu(') || line.contains(' cond_synchronize_rcu(') ||
			line.contains(' __bitmap_weight(') || line.contains(' arch_atomic_read(') {
			bodies << body
			declarations << line[..line.len - 2] + ';'
		}
	}
	if bodies.len == 0 { return error('No actual generated production bodies') }
	mut globals := []string{}
	for line in raw.split_into_lines() {
		if !line.ends_with(';') || line.starts_with('extern ') || line.starts_with('typedef ') ||
			line.starts_with('\t') || line.starts_with(' ') { continue }
		declaration := if line.starts_with('__attribute__((visibility("default"))) ') {
			line.all_after('__attribute__((visibility("default"))) ')
		} else { line }
		if declaration.contains('(') { continue }
		if global_prefixes.any(line.contains(it)) || line.contains(prefix + 'v3_no_main_initialized') { globals << line }
	}
	mut callback_types := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && line.contains('(*_fn_ptr_') { callback_types << line }
	}
	mut record_metadata := []string{}
	if prefix == 'compatcore__' {
		record_metadata << 'typedef struct compatcore__RcuWorker compatcore__RcuWorker;'
		record_metadata << hosttest.record(raw, 'compatcore__RcuWorker')!
	}
	mut zero_metadata := []string{}
	for line in raw.split_into_lines() { if line.starts_with('#define E_STRUCT ') { zero_metadata << line } }
	text := '#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n' +
		(if prefix == 'headercore__' { 'typedef uint64_t u64;\n' } else { 'typedef uint32_t u32; typedef uint64_t u64; typedef uint16_t u16;\n' }) +
		'typedef int32_t i32; typedef int64_t i64; typedef size_t usize; typedef void *voidptr;\n' +
		header + record_metadata.join('\n') + '\n' + zero_metadata.join('\n') + '\n' + callback_types.join('\n') + '\n' + globals.join('\n') + '\n' +
		declarations.join('\n') + '\n' + bodies.join('\n\n') + '\n'
	if hosttest.c_bodies(text) != bodies { return error('Metadata extraction changed an actual generated V body') }
	return text
}

fn stage_sources(work string) ![]string {
	root := hosttest.root()
	mut owned := []string{}
	for name in ['compatcore', 'headercore'] { os.mkdir(os.join_path(work, name))! }
	for module_name, paths in {
		'compatcore': ['rcu.v', 'smp_masks.v']
		'headercore': ['rcu.v', 'smp_masks.v', 'smp_masks_storage.v']
	} {
		for path in paths {
			original := os.join_path(root, 'kernel/linuxkpi', module_name, path)
			os.cp(original, os.join_path(work, module_name, path))!
			owned << original
		}
	}
	primitive := os.join_path(root, 'kernel/linuxkpi/compatcore/primitives.v')
	bitmap := os.join_path(root, 'kernel/linuxkpi/compatcore/bitmap.v')
	atomic_path := os.join_path(root, 'kernel/linuxkpi/headercore/primitive.v')
	owned << [primitive, bitmap, atomic_path]
	mut bindings := '@[translated]\nmodule compatcore\n#include "linuxkpi_rcu_v_primitives.h"\n' +
		'struct C.callback_head {}\nstruct C.vkw_list {}\n' +
		'struct C.vkw_swait_head { lock u32, task_list C.vkw_list }\n' +
		'struct C.vkw_completion { done u32, @wait C.vkw_swait_head }\n' +
		'fn C.kzalloc(usize,u32) voidptr\nfn C.kfree(voidptr)\nfn C.memset(voidptr,i32,usize) voidptr\nfn C.memcpy(voidptr,voidptr,usize) voidptr\n' +
		'fn C.vinix_linuxkpi_bug(&char,i32)\nfn C.vinix_linuxkpi_irq_flags() usize\n' +
		'fn C.vinix_linuxkpi_may_sleep() bool\nfn C.vinix_linuxkpi_spin_wait()\nfn C.vinix_linuxkpi_cond_resched() i32\n' +
		'fn C.vinix_linuxkpi_preempt_disable()\nfn C.vinix_linuxkpi_preempt_enable()\n' +
		'fn C.vkp_spin_init(voidptr)\nfn C.vkp_spin_lock_irqsave(voidptr) usize\n' +
		'fn C.vkp_spin_unlock_irqrestore(voidptr,usize)\nfn C.msleep(u32)\n' +
		'fn C.rcuh_completion_init(voidptr)\nfn C.rcuh_completion_complete(voidptr)\nfn C.rcuh_completion_wait(voidptr)\n' +
		'fn init_swait_queue_head(p voidptr,_name voidptr,_key voidptr) { C.rcuh_completion_init(p) }\n' +
		'fn complete(p voidptr) { C.rcuh_completion_complete(p) }\n' +
		'fn wait_for_completion(p voidptr) { C.rcuh_completion_wait(p) }\n'
	for name in ['require', 'is_null', 'native_hweight_long'] { bindings += hosttest.v_function(os.read_file(primitive)!, name)! }
	bindings += hosttest.v_function(os.read_file(bitmap)!, 'bitmap_weight')!
	os.write_file(os.join_path(work, 'compatcore/bindings.v'), bindings)!
	os.write_file(os.join_path(work, 'headercore/bindings.v'), '@[translated]\nmodule headercore\n' +
		'#include "linuxkpi_header_primitive_v_contract.h"\n@[typedef]\nstruct C.atomic_t { counter i32 }\n' +
		'@[typedef]\nstruct C.vhp_const_atomicp {}\nfn C.test_bit(i32,voidptr) bool\n' +
		'@[typedef]\nstruct C.vhp_const_voidp {}\nstruct C.callback_head {}\nstruct C.task_struct { vinix_thread voidptr, __state u32 }\n' +
		'@[typedef]\nstruct C.pthread_t {}\ntype HeaderThreadFn = fn(voidptr) voidptr\n' +
		'fn C.pthread_create(voidptr,voidptr,HeaderThreadFn,voidptr) i32\nfn C.pthread_join(C.pthread_t,voidptr) i32\n' +
		'fn C.pthread_exit(voidptr)\nfn C.memcpy(voidptr,voidptr,usize) voidptr\n' +
		'fn C.get_task_struct(&C.task_struct) &C.task_struct\nfn C.put_task_struct(&C.task_struct)\n' +
		'fn C.__atomic_load_n(&u32,i32) u32\n@[c_extern]\n__global C.current &C.task_struct\n' +
		'@[c_extern]\n__global C.TASK_DEAD u32\n' +
		"@[c: '__atomic_load_n']\nfn C.vhp_load32(&i32,i32) i32\n" +
		hosttest.v_function(os.read_file(atomic_path)!, 'atomic_read')!)!
	return owned
}

fn profile(work string, linux string, compiler []string, standard string) []string {
	root := hosttest.root()
	mut argv := compiler.clone()
	$if macos { argv << ['-arch', 'x86_64'] }
	argv << ['-std=' + standard, '-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv',
		'-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-Wno-sign-compare',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-D_FORTIFY_SOURCE=0',
		'-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-D__KERNEL__',
		'-include', os.join_path(root, 'tests/linuxkpi/host_types.h'), '-include', 'linux/kconfig.h',
		'-include', os.join_path(linux, 'include/linux/compiler_types.h')]
	for directory in [os.join_path(work, 'include'), os.join_path(root, 'tests/linuxkpi/rcucallfixture'),
		os.join_path(root, 'kernel/linuxkpi/include'),
		os.join_path(linux, 'include'), os.join_path(linux, 'include/uapi'),
		os.join_path(linux, 'arch/x86/include'), os.join_path(linux, 'arch/x86/include/uapi')] {
		argv << ['-I', directory]
	}
	argv << ['-iquote', os.join_path(root, 'kernel/c')]
	return argv
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
	compiler := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	work := hosttest.work_dir(keep, 'vinix-rcu-callbacks-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	mut env := os.environ()
	env['VCACHE'] = os.join_path(work, 'vcache')
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	stage := os.join_path(work, 'stage')
	os.mkdir(stage)!
	mut observed := stage_sources(stage)!
	observed << [@FILE, os.join_path(root, 'tests/linuxkpi/rcucallfixture/core.v'),
		os.join_path(root, 'tests/linuxkpi/rcucallfixture/rcucall_host_contract.h')]
	observed << os.walk_ext(os.join_path(root, 'tests/linuxkpi/hosttest'), '.v')
	observed << os.walk_ext(os.join_path(root, 'kernel/linuxkpi/include'), '.h')
	for name in ['linuxkpi_rcu_v_primitives.h', 'linuxkpi_rcu_v_contract.h',
		'linuxkpi_smp_masks_v_primitives.h', 'linuxkpi_smp_masks_v_contract.h'] {
		observed << os.join_path(root, 'kernel/c', name)
	}
	initial := hosttest.hashes(observed)!
	compiler_path := os.real_path(os.find_abs_path_of_executable(compiler[0]) or { compiler[0] })
	v_selection := hosttest.env_default('V', 'v')
	v_path := os.real_path(os.find_abs_path_of_executable(v_selection) or { v_selection })
	tools := map[string]json2.Any{
		'V_path': json2.Any(v_path)
		'V_sha256': hosttest.file_digest(v_path)!
		'C_path': compiler_path
		'C_sha256': hosttest.file_digest(compiler_path)!
		'C_version': command([...compiler, '--version'], os.join_path(work, 'compiler-version.log'), env)!.stdout
	}
	pin := hosttest.upstream_pin()!
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(os.join_path(work, 'initial-source-sha256.json'), hosttest.string_map(initial))!
	include := os.join_path(work, 'include')
	for schema, name in {'atomic-exchange': 'atomic_exchange', 'overflow': 'integer_policy', 'spinlock': 'spinlock_adapters'} {
		hosttest.generate_abi(os.join_path(root, 'kernel/linuxkpi/abi', schema + '.json'),
			os.join_path(root, 'kernel/linuxkpi'), os.join_path(include, 'vinix', name + '.h'))!
	}
	mut proofs := []json2.Any{}
	for name in ['compatcore', 'headercore'] {
		generated := os.join_path(work, name + '-actual.c')
		hosttest.generate_module(os.join_path(stage, name), generated, 'amd64', ['linuxkpi_host_test', 'nofloat'])!
		raw := os.read_file(generated)!
		header := if name == 'headercore' {
			'#include "linuxkpi_rcu_v_contract.h"\n#include "linuxkpi_smp_masks_v_contract.h"\n' +
			'#include "linuxkpi_header_primitive_v_contract.h"\n' +
			'typedef struct cpumask cpumask;\n' +
			hosttest.scalar_metadata(os.join_path(stage, name), '')!
		} else { '#include "linuxkpi_rcu_v_primitives.h"\n#include "linuxkpi_smp_masks_v_primitives.h"\n' +
			'void msleep(unsigned int); void rcuh_completion_init(void *); void rcuh_completion_complete(void *); void rcuh_completion_wait(void *);\n#include <string.h>\n' }
		prefixes := if name == 'headercore' { ['cpu_bit_bitmap', 'cpu_all_bits', '__cpu_', '__num_online_cpus', 'nr_cpu_ids'] }
			else { ['compatcore__vkr_rcu_', 'compatcore__vkms_ready'] }
		selected := selected_source(raw, name + '__', header, prefixes)!
		os.write_file(os.join_path(work, name + '-selected.c'), selected)!
		proofs << map[string]json2.Any{'module': json2.Any(name), 'actual_generated_c_sha256': hosttest.sha(generated)!,
			'selected_c_sha256': hosttest.text_sha(selected), 'actual_body_count': hosttest.c_bodies(selected).len}
	}
	fixture_source := os.join_path(work, 'rcucallfixture')
	os.mkdir(fixture_source)!
	os.cp(os.join_path(root, 'tests/linuxkpi/rcucallfixture/core.v'), os.join_path(fixture_source, 'core.v'))!
	hosttest.generate_module(fixture_source, os.join_path(work, 'fixture.c'), 'amd64', ['nofloat'])!
	mut results := []json2.Any{}
	mut inputs := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		base := profile(work, linux, compiler, standard)
		mut objects := []string{}
		for group in ['compatcore', 'headercore'] {
			obj := os.join_path(work, standard + '-' + group + '.o')
			inputs << compile_input(base, os.join_path(work, group + '-selected.c'), obj,
				os.join_path(work, standard + '-' + group + '-compile.log'), env)!
			imports := command([hosttest.tool('llvm-nm'), '-u', obj], '', env)!.stdout
			os.write_file(os.join_path(work, standard + '-' + group + '-imports.txt'), imports)!
			if hosttest.allocation_symbols(imports) { return error('Implicit production allocator import') }
			objects << obj
		}
		// Fixture compiler metadata can repeat foreign declarations under GNU11;
		// the selected unaltered production functions above are strict in both.
		fixture := os.join_path(work, standard + '-fixture.o')
		fixture_flags := profile(work, linux, compiler, 'gnu11')
		inputs << compile_input(fixture_flags, os.join_path(work, 'fixture.c'), fixture,
			os.join_path(work, standard + '-fixture-compile.log'), env)!
		objects << fixture
		executable := os.join_path(work, standard + '-test')
		dead_strip := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
		command([...base, ...objects, dead_strip, '-pthread', '-o', executable], os.join_path(work, standard + '-link.log'), env)!
		for count in [1, 2, 4, 64, 65, 128, 256] {
			for mode in [0, 1, 2, 3, 4] {
				log := os.join_path(work, '${standard}-${count}-${mode}-run.log')
				passed := command([executable, count.str(), mode.str()], log, env)!
				if passed.stderr != '' || !passed.stdout.starts_with('PASS: ') { return error('Missing clean RCU callback verdict: ${log}') }
				results << map[string]json2.Any{'standard': json2.Any(standard), 'cpus': count, 'mode': mode,
					'output': passed.stdout.trim_space(), 'executable_sha256': hosttest.sha(executable)!}
			}
		}
		for mode in [10, 11, 12, 13, 14, 15] {
			log := os.join_path(work, '${standard}-invalid-${mode}-run.log')
			failed := hosttest.capture([executable, '4', mode.str()], log, 30, env)!
			if failed.code == 0 || !failed.stderr.contains('RCU invariant:') ||
				failed.stderr.contains('ERROR: AddressSanitizer') || failed.stderr.contains('runtime error:') {
				return error('Missing explicit invalid-context failure: ${log}')
			}
			results << map[string]json2.Any{'standard': json2.Any(standard), 'invalid_context_mode': mode,
				'exit_code': failed.code, 'output': failed.stderr.trim_space(),
				'executable_sha256': hosttest.sha(executable)!}
		}
	}
	if initial != hosttest.hashes(observed)! { return error('Production/test source changed during checks') }
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope': json2.Any(scope), 'source_sha256': hosttest.string_map(initial),
		'completion_transport_adapters': hosttest.strings(['init_swait_queue_head', 'complete', 'wait_for_completion']),
		'ordering_scope': json2.Any('Acquire/release transport witnesses and authentic generated full-fence bodies; this host matrix is not an independent relaxed payload publication litmus. Actual native full-fence object and IRQ-return evidence are required separately.'),
		'cookie_boundary_reference': map[string]json2.Any{
			'upstream_path': json2.Any('kernel/rcu/rcu.h:164 rcu_seq_done_exact; include/linux/rcupdate.h:35-36 ULONG_CMP_GE/LT'),
			'upstream_rcu_h_sha256': json2.Any('171ef5b7f14b6e39062d1c8cdac67f0c8a6738dd5b599cbffbc5a7d806e01eb8'),
			'cases': 26,
			'method': json2.Any('Literal expected boundaries derived from original unsigned half-range macros and STATE_MASK=3; fixture calls actual selected compatcore__rcu_sequence_exact_done, with no live epoch/ready-state seeds and no replacement comparison body.'),
		},
		'actual_generated_body_proofs': proofs, 'runs': results,
		'compiler': tools, 'object_and_native_input_proofs': inputs,
		'upstream_pin': pin,
		'fixture_c_sha256': hosttest.sha(os.join_path(work, 'fixture.c'))!
	})!
	println('LinuxKPI RCU callbacks: actual V backend, original heads, strict GNU99/GNU11 and host ASan/UBSan scenarios passed')
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-directory'], 'Usage: rcu_callbacks.v [--keep-directory DIRECTORY]', scope) or { eprintln(err); exit(2) }
	run_profile(options['--keep-directory']) or { eprintln(err); exit(1) }
}
