// SPDX-License-Identifier: GPL-2.0-or-later
// Actual generated V IRQ work, original records and independent IPI transport.
module main

import os
import json2
import hosttest

const scope = 'Execute unchanged generated production IRQ-work V bodies and original Linux records with independent CPU/IPI transport. Native IRQ entry, scheduler placement, IRET and native retained allocations require separate guest evidence.'

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
	if before != hosttest.hashes(dependencies)! {
		return error('Compiler dependency changed during object build: ${object}')
	}
	return map[string]json2.Any{
		'object':                        json2.Any(object)
		'object_sha256':                 hosttest.sha(object)!
		'actual_source_sha256':          hosttest.sha(source)!
		'compiler_visible_input_sha256': hosttest.sha(preprocessed)!
		'dependency_sha256':             hosttest.string_map(before)
	}
}

fn selected_source(raw string, prefix string, header string, global_prefixes []string) !string {
	mut bodies := []string{}
	mut declarations := []string{}
	for body in hosttest.c_bodies(raw) {
		line := body.all_before('\n')
		if line.contains(prefix) || line.contains(' vkiw_') || line.contains(' irq_work_') || line.contains(' arch_irq_work_raise(') || line.contains(' vkm_')
			|| line.contains(' __bitmap_weight(') || line.contains(' arch_atomic_read(') || line.contains(' arch_atomic_set(') {
			bodies << body
			declarations << line[..line.len - 2] + ';'
		}
	}
	if bodies.len == 0 { return error('No actual generated production bodies') }
	mut globals := []string{}
	for line in raw.split_into_lines() {
		if !line.ends_with(';') || line.starts_with('extern ') || line.starts_with('typedef ')
			|| line.starts_with('\t') || line.starts_with(' ') {
			continue
		}
		declaration := if line.starts_with('__attribute__((visibility("default"))) ') {
			line.all_after('__attribute__((visibility("default"))) ')
		} else {
			line
		}
		if declaration.contains('(') { continue }
		if global_prefixes.any(line.contains(it)) || line.contains(prefix + 'v3_no_main_initialized') {
			globals << line
		}
	}
	mut callback_types := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && line.contains('(*_fn_ptr_') { callback_types << line }
	}
	mut record_metadata := []string{}
	if prefix == 'compatcore__' {
		record_metadata << 'typedef struct compatcore__IrqWorkRun compatcore__IrqWorkRun;'
		record_metadata << hosttest.record(raw, 'compatcore__IrqWorkRun')!
	}

	mut zero_metadata := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('#define E_STRUCT ') { zero_metadata << line }
	}
	text := '#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n' +
		(if prefix == 'headercore__' {
			'typedef uint64_t u64;\n'
		} else {
			'typedef uint8_t u8; typedef uint32_t u32; typedef uint64_t u64; typedef uint16_t u16;\n'
		}) +
		'typedef int32_t i32; typedef int64_t i64; typedef size_t usize; typedef void *voidptr;\n' +
		header + callback_types.join('\n') + '\n' + record_metadata.join('\n') + '\n' + zero_metadata.join('\n') + '\n' + globals.join('\n') + '\n' +
		declarations.join('\n') + '\n' + bodies.join('\n\n') + '\n'
	if hosttest.c_bodies(text) != bodies {
		return error('Metadata extraction changed an actual generated V body')
	}
	return text
}

fn stage_sources(work string) ![]string {
	root := hosttest.root()
	mut owned := []string{}
	for name in ['compatcore', 'headercore'] { os.mkdir(os.join_path(work, name))! }
	for module_name, paths in {
		'compatcore': ['irq_work.v', 'smp_masks.v']
		'headercore': ['irq_work.v', 'smp_masks.v', 'smp_masks_storage.v']
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
	mut bindings := '@[translated]\nmodule compatcore\n#include "linuxkpi_irq_work_v_primitives.h"\nstruct C.irq_work{}\n' +
		'fn C.vkm_cpu_masks_ready()bool\nfn C.vkm_cpu_ids()u32\nfn C.vkm_online_count()u32\nfn C.vks_smp_ready()bool\nfn C.vinix_linuxkpi_smp_boot_context()bool\nfn C.vinix_linuxkpi_smp_task_present()bool\nfn C.vinix_linuxkpi_cpu_id()u32\nfn C.vinix_linuxkpi_maskable_irq_depth()u32\nfn C.vinix_linuxkpi_preempt_count()u32\nfn C.vinix_linuxkpi_preempt_disable()\nfn C.vinix_linuxkpi_preempt_enable()\n' +
		'fn C.vinix_linuxkpi_bug(&char,i32)\nfn C.vinix_linuxkpi_irq_flags()u64\nfn C.vinix_linuxkpi_irq_save()u64\nfn C.vinix_linuxkpi_irq_restore(u64)\nfn C.vinix_linuxkpi_may_sleep()bool\nfn C.vinix_linuxkpi_spin_wait()\nfn C.vinix_linuxkpi_cond_resched()i32\nfn C.vkp_spin_init(voidptr)\nfn C.vkp_spin_lock_irqsave(voidptr)u64\nfn C.vkp_spin_unlock_irqrestore(voidptr,u64)\n'
	for name in ['require', 'is_null', 'native_hweight_long'] {
		bindings += hosttest.v_function(os.read_file(primitive)!, name)!
	}
	bindings += hosttest.v_function(os.read_file(bitmap)!, 'bitmap_weight')!
	bindings += '__global vkiw_host_guard_anchor i32=-1\n'
	os.write_file(os.join_path(work, 'compatcore/bindings.v'), bindings)!
	os.write_file(os.join_path(work, 'headercore/bindings.v'), '@[translated]\nmodule headercore\n#include "linuxkpi_header_primitive_v_contract.h"\nfn C.vinix_linuxkpi_cpu_id()u32\n@[typedef]\nstruct C.atomic_t{counter i32}\n@[typedef]\nstruct C.vhp_const_atomicp{}\nfn C.test_bit(i32,voidptr)bool\n' +
		"@[c:'__atomic_load_n']\nfn C.vhp_load32(&i32,i32)i32\n@[c:'__atomic_store_n']\nfn C.vhp_store32(&i32,i32,i32)\n" + hosttest.v_function(os.read_file(atomic_path)!, 'atomic_read')! + hosttest.v_function(os.read_file(atomic_path)!, 'atomic_set')!)!
	return owned
}

fn run_cases(executable string, standard string, work string, env map[string]string, mut results []json2.Any) ! {
	for cpus in [1, 2, 4, 64, 65, 128, 256] {
		log := os.join_path(work, '${standard}-${cpus}-safe.log')
		passed := command([executable, cpus.str(), '0'], log, env)!
		if passed.stderr != '' || !passed.stdout.starts_with('PASS: ') {
			return error('Missing clean IRQ-work verdict: ' + log)
		}
		results << map[string]json2.Any{
			'standard':          json2.Any(standard)
			'cpus':              cpus
			'output':            passed.stdout.trim_space()
			'executable_sha256': hosttest.sha(executable)!
		}
	}
	for mode := 10; mode <= 18; mode++ {
		log := os.join_path(work, '${standard}-invalid-${mode}.log')
		failed := hosttest.capture([executable, '4', mode.str()], log, 30, env)!
		if failed.code == 0 || !failed.stderr.contains('IRQ work invariant:') || !failed.stderr.contains('IRQ work validation preserved node') || failed.stderr.contains('ERROR: AddressSanitizer') || failed.stderr.contains('runtime error:') {
			return error('Missing explicit prepublication/context failure: ' + log)
		}
		results << map[string]json2.Any{
			'standard':          json2.Any(standard)
			'invalid_mode':      mode
			'exit_code':         failed.code
			'output':            failed.stderr.trim_space()
			'executable_sha256': hosttest.sha(executable)!
		}
	}
}

fn body_name(body string) string {
	line := body.all_before('\n').all_before_last('(')
	return line.all_after_last(' ').trim_left('*')
}

fn full_module_parity(name string, selected string, work string) !json2.Any {
	root := hosttest.root()
	path := os.join_path(work, name + '-full-reference.c')
	hosttest.generate_module(os.join_path(root, 'kernel/linuxkpi', name), path, 'amd64', [
		'linuxkpi_host_test',
		'nofloat',
	])!
	full := hosttest.c_bodies(os.read_file(path)!)
	mut identical := map[string]string{}
	for body in hosttest.c_bodies(selected) {
		symbol := body_name(body)
		matches := full.filter(hosttest.named_body(it, symbol))
		if matches.len != 1 || matches[0] != body {
			return error('Changed full-module production body or initialization guard: ' + symbol)
		}
		identical[symbol] = hosttest.text_sha(body)
	}
	return map[string]json2.Any{
		'reference_c_sha256':         json2.Any(hosttest.sha(path)!)
		'byte_identical_body_sha256': hosttest.string_map(identical)
	}
}

fn profile(work string, linux string, compiler []string, standard string) []string {
	root := hosttest.root()
	mut argv := compiler.clone()
	$if macos {
		argv << ['-arch', 'x86_64']
	}
	argv << ['-std=' + standard, '-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv',
		'-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-Wno-sign-compare',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-D_FORTIFY_SOURCE=0',
		'-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-D__KERNEL__', '-include',
		os.join_path(root, 'tests/linuxkpi/host_types.h'), '-include', 'linux/kconfig.h', '-include',
		os.join_path(linux, 'include/linux/compiler_types.h')]
	for directory in [os.join_path(work, 'include'),
		os.join_path(root, 'tests/linuxkpi/irqworkfixture'),
		os.join_path(root, 'kernel/linuxkpi/include'), os.join_path(linux, 'include'),
		os.join_path(linux, 'include/uapi'), os.join_path(linux, 'arch/x86/include'),
		os.join_path(linux, 'arch/x86/include/uapi')] {
		argv << ['-I', directory]
	}
	argv << ['-iquote', os.join_path(root, 'kernel/c')]
	return argv
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
	compiler := hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
	work := hosttest.work_dir(keep, 'vinix-irq-work-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	mut env := os.environ()
	env['VCACHE'] = os.join_path(work, 'vcache')
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	stage := os.join_path(work, 'stage')
	os.mkdir(stage)!
	mut observed := stage_sources(stage)!
	observed << [@FILE, os.join_path(root, 'tests/linuxkpi/irqworkfixture/README.md')]
	observed << os.walk_ext(os.join_path(root, 'tests/linuxkpi/irqworkfixture'), '.v')
	observed << os.walk_ext(os.join_path(root, 'tests/linuxkpi/irqworkfixture'), '.h')
	observed << os.walk_ext(os.join_path(root, 'tests/linuxkpi/hosttest'), '.v')
	observed << os.walk_ext(os.join_path(root, 'kernel/linuxkpi/include'), '.h')
	for module_name in ['compatcore', 'headercore'] {
		observed << os.walk_ext(os.join_path(root, 'kernel/linuxkpi', module_name), '.v')
	}
	observed << os.walk_ext(os.join_path(root, 'kernel/c'), '.h')
	for name in ['linuxkpi_irq_work_v_primitives.h', 'linuxkpi_irq_work_v_contract.h',
		'linuxkpi_smp_masks_v_primitives.h', 'linuxkpi_smp_masks_v_contract.h'] {
		observed << os.join_path(root, 'kernel/c', name)
	}
	initial := hosttest.hashes(observed)!
	compiler_path := os.real_path(os.find_abs_path_of_executable(compiler[0]) or { compiler[0] })
	v_selection := hosttest.env_default('V', 'v')
	v_path := os.real_path(os.find_abs_path_of_executable(v_selection) or { v_selection })
	tools := map[string]json2.Any{
		'V_path':    json2.Any(v_path)
		'V_sha256':  hosttest.file_digest(v_path)!
		'C_path':    compiler_path
		'C_sha256':  hosttest.file_digest(compiler_path)!
		'C_version': command([...compiler, '--version'], os.join_path(work, 'compiler-version.log'), env)!.stdout
	}
	pin := hosttest.upstream_pin()!
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(os.join_path(work, 'initial-source-sha256.json'), hosttest.string_map(initial))!
	include := os.join_path(work, 'include')
	for schema, name in {
		'atomic-exchange': 'atomic_exchange'
		'overflow':        'integer_policy'
		'spinlock':        'spinlock_adapters'
	} {
		hosttest.generate_abi(os.join_path(root, 'kernel/linuxkpi/abi', schema + '.json'),
			os.join_path(root, 'kernel/linuxkpi'), os.join_path(include, 'vinix', name + '.h'))!
	}
	mut proofs := []json2.Any{}
	for name in ['compatcore', 'headercore'] {
		generated := os.join_path(work, name + '-actual.c')
		hosttest.generate_module(os.join_path(stage, name), generated, 'amd64', [
			'linuxkpi_host_test',
			'nofloat',
		])!
		raw := os.read_file(generated)!
		header := if name == 'headercore' {
			'#include "linuxkpi_irq_work_v_contract.h"\n#include "linuxkpi_smp_masks_v_contract.h"\n' +
				'#include "linuxkpi_header_primitive_v_contract.h"\n' +
				'typedef struct cpumask cpumask;\n' +
				hosttest.scalar_metadata(os.join_path(stage, name), '')!
		} else {
			'#include "linuxkpi_irq_work_v_primitives.h"\n#include "linuxkpi_smp_masks_v_primitives.h"\n' +
				'#include <string.h>\n'
		}
		prefixes := if name == 'headercore' {
			['cpu_bit_bitmap', 'cpu_all_bits', '__cpu_', '__num_online_cpus', 'nr_cpu_ids']
		} else {
			['compatcore__vkiw_', 'compatcore__vkms_ready']
		}
		selected := selected_source(raw, name + '__', header, prefixes)!
		os.write_file(os.join_path(work, name + '-selected.c'), selected)!
		proofs << map[string]json2.Any{
			'module':                    json2.Any(name)
			'actual_generated_c_sha256': hosttest.sha(generated)!
			'selected_c_sha256':         hosttest.text_sha(selected)
			'actual_body_count':         hosttest.c_bodies(selected).len
			'full_module_parity':        full_module_parity(name, selected, work)!
		}
	}
	fixture_source := os.join_path(work, 'irqworkfixture')
	os.mkdir(fixture_source)!
	os.cp(os.join_path(root, 'tests/linuxkpi/irqworkfixture/core.v'), os.join_path(fixture_source, 'core.v'))!
	hosttest.generate_module(fixture_source, os.join_path(work, 'fixture.c'), 'amd64', ['nofloat'])!
	mut results := []json2.Any{}
	mut inputs := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		base := profile(work, linux, compiler, standard)
		mut objects := []string{}
		for group in ['compatcore', 'headercore'] {
			obj := os.join_path(work, standard + '-' + group + '.o')
			mut group_flags := base.clone()
			if group == 'compatcore' { group_flags << '-DVINIX_V_RUNTIME' }
			inputs << compile_input(group_flags, os.join_path(work, group + '-selected.c'), obj,
				os.join_path(work, standard + '-' + group + '-compile.log'), env)!
			imports := command([hosttest.tool('llvm-nm'), '-u', obj], '', env)!.stdout
			os.write_file(os.join_path(work, standard + '-' + group + '-imports.txt'), imports)!
			if hosttest.allocation_symbols(imports) {
				return error('Implicit production allocator import')
			}
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
		run_cases(executable, standard, work, env, mut results)!
	}
	if initial != hosttest.hashes(observed)! {
		return error('Production/test source changed during checks')
	}
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope':                          json2.Any(scope)
		'source_sha256':                  hosttest.string_map(initial)
		'production_algorithm_adapters':  hosttest.strings([])
		'ordering_scope':                 json2.Any('Acquire/release transport witnesses and authentic generated full-fence bodies; this host matrix is not an independent relaxed payload publication litmus. Actual native full-fence object and IRQ-return evidence are required separately.')
		'ownership_scope':                json2.Any('Original caller-owned IRQ-work records; no callback self-free is permitted before post-callback BUSY retirement. Cross-CPU overlapping callback tests retain stable storage until native sync joins all stack records.')
		'actual_generated_body_proofs':   proofs
		'runs':                           results
		'compiler':                       tools
		'object_and_native_input_proofs': inputs
		'upstream_pin':                   pin
		'fixture_c_sha256':               hosttest.sha(os.join_path(work, 'fixture.c'))!
	})!
	println('LinuxKPI IRQ work: actual V backend, original heads, strict GNU99/GNU11 and host ASan/UBSan passed')
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-directory'], 'Usage: irq_work.v [--keep-directory DIRECTORY]', scope) or {
		eprintln(err)
		exit(2)
	}
	run_profile(options['--keep-directory']) or {
		eprintln(err)
		exit(1)
	}
}
