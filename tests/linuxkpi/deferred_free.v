// SPDX-License-Identifier: GPL-2.0-or-later
// Actual generated V RCU, original callback records and independent transport.
module main

import os
import json2
import hosttest

const scope = 'Exercise actual generated production page allocator and RCU deferred frees, with original heads and independent V host CPU/page transport. Native IRQ-return and retained-kernel-allocation evidence remains separate.'

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
		if line.contains(prefix) || line.contains(' vkr_') || line.contains(' vkm_') ||
			line.contains(' vinix_linuxkpi_gfp_supported(') || line.contains(' vinix_linuxkpi_alloc_gfp_pages(') || line.contains(' vinix_linuxkpi_tigerlake_id(') ||
			line.contains(' kmalloc(') || line.contains(' kzalloc(') || line.contains(' kmalloc_array(') || line.contains(' kcalloc(') || line.contains(' ksize(') || line.contains(' kfree(') || line.contains(' krealloc(') || line.contains(' kmemdup(') || line.contains(' kmem_cache_') || line.contains(' kvfree(') || line.contains(' kvfree_call_rcu(') ||
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
		for name in ['RcuWorker','RuntimeAllocation','CacheList','CacheSlot','CacheSlab','Cache'] { record_metadata << 'typedef struct compatcore__${name} compatcore__${name};' }
		for name in ['RcuWorker','RuntimeAllocation','CacheList','CacheSlot','CacheSlab','Cache'] { record_metadata << hosttest.record(raw, 'compatcore__'+name)! }
	}
	mut zero_metadata := []string{}
	for line in raw.split_into_lines() { if line.starts_with('#define E_STRUCT ') || line.starts_with('#define compatcore__page_allocation_tag ') { zero_metadata << line } }
	text := '#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n' +
		(if prefix == 'headercore__' { 'typedef uint64_t u64;\n' } else { 'typedef uint8_t u8; typedef uint32_t u32; typedef uint64_t u64; typedef uint16_t u16;\n' }) +
		'typedef int32_t i32; typedef int64_t i64; typedef size_t usize; typedef void *voidptr;\n' +
		header + callback_types.join('\n') + '\n' + record_metadata.join('\n') + '\n' + zero_metadata.join('\n') + '\n' + globals.join('\n') + '\n' +
		declarations.join('\n') + '\n' + bodies.join('\n\n') + '\n'
	if hosttest.c_bodies(text) != bodies { return error('Metadata extraction changed an actual generated V body') }
	return text
}

fn stage_sources(work string) ![]string {
	root := hosttest.root()
	mut owned := []string{}
	for name in ['compatcore', 'headercore'] { os.mkdir(os.join_path(work, name))! }
	for module_name, paths in {
		'compatcore': ['rcu.v', 'smp_masks.v', 'runtime.v', 'cache.v']
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
		'fn C.kzalloc(usize,u32) voidptr\nfn C.kfree(voidptr)\nfn C.memset(voidptr,i32,usize) voidptr\nfn C.memcpy(voidptr,voidptr,usize) voidptr\nfn C.strlen(voidptr) usize\nfn C.kmalloc(usize,u32) voidptr\nfn C.vinix_linuxkpi_page_size() usize\nfn C.vinix_linuxkpi_free_pages(voidptr,usize)\nfn C.vinix_linuxkpi_alloc_gfp_pages(usize,u32) voidptr\nfn C.vinix_linuxkpi_gfp_supported(u32) bool\nfn C.vkp_cache_ctor_warning(bool)\n' +
		'fn C.vinix_linuxkpi_bug(&char,i32)\nfn C.vinix_linuxkpi_irq_flags() u64\n' +
		'fn C.vinix_linuxkpi_may_sleep() bool\nfn C.vinix_linuxkpi_spin_wait()\nfn C.vinix_linuxkpi_cond_resched() i32\n' +
		'fn C.vinix_linuxkpi_preempt_disable()\nfn C.vinix_linuxkpi_preempt_enable()\n' +
		'fn C.vkp_spin_init(voidptr)\nfn C.vkp_spin_lock_irqsave(voidptr) u64\n' +
		'fn C.vkp_spin_unlock_irqrestore(voidptr,u64)\nfn C.msleep(u32)\n' +
		'fn C.rcuh_completion_init(voidptr)\nfn C.rcuh_completion_complete(voidptr)\nfn C.rcuh_completion_wait(voidptr)\n' +
		'fn init_swait_queue_head(p voidptr,_name &char,_key voidptr) { C.rcuh_completion_init(p) }\n' +
		'fn complete(p voidptr) { C.rcuh_completion_complete(p) }\n' +
		'fn wait_for_completion(p voidptr) { C.rcuh_completion_wait(p) }\n' +
		'__global vkr_host_guard_anchor i32 = -1\n'
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
		"@[c: '__atomic_load_n']\nfn C.vhp_load32(&i32,i32) i32\n" +
		hosttest.v_function(os.read_file(atomic_path)!, 'atomic_read')!)!
	return owned
}

fn stage_fixture(directory string) ! {
	root := hosttest.root()
	os.mkdir(directory)!
	for file in os.walk_ext(os.join_path(root,'tests/linuxkpi/freefixture'),'.v') { os.cp(file,os.join_path(directory,os.file_name(file)))! }
	// Reuse the maintained independent V transport verbatim. Its allocation
	// wrappers and main are excluded because this fixture executes the actual
	// production page allocator. These are transport/test functions only.
	original := os.read_file(os.join_path(root,'tests/linuxkpi/rcucallfixture/core.v'))!
	mut transport := original.all_before('fn callback(head &C.callback_head) {').replace('module rcucallfixture','module freefixture')
	for attribute in ["@[export: 'kzalloc']", "@[export: 'kfree']", "@[export: 'vinix_linuxkpi_bug'; noreturn]", "@[export: 'vkr_page_allocation_size']", "@[export: 'vkr_kvfree']"] { transport = transport.replace(attribute + ' pub fn',attribute+'\npub fn') }
	for name in ['allocate','deallocate','bug','unsupported_page_owner','unsupported_page_free','await_return','await_poll'] { transport = transport.replace(hosttest.v_function(transport,name)!,'') }
	for name in ['start_waiter','wait_actor','join_waiter'] { transport += hosttest.v_function(original,name)! }
	os.write_file(os.join_path(directory,'transport.v'),transport)!
}

fn run_cases(executable string,standard string,work string,env map[string]string,mut results []json2.Any) ! {
	log := os.join_path(work,standard+'-safe.log')
	passed := command([executable,'0'],log,env)!
	if passed.stderr != '' || !passed.stdout.starts_with('PASS: ') { return error('Missing clean deferred-free verdict: '+log) }
	results << map[string]json2.Any{'standard':json2.Any(standard),'mode':0,'output':passed.stdout.trim_space(),'executable_sha256':hosttest.sha(executable)!}
	for mode := 10; mode <= 27; mode++ {
		fatal_log := os.join_path(work,'${standard}-invalid-${mode}.log')
		failed := hosttest.capture([executable,mode.str()],fatal_log,30,env)!
		if failed.code == 0 || !failed.stderr.contains('RCU invariant:') || !failed.stderr.contains('FREE validation preserved original head and allocation') || failed.stderr.contains('ERROR: AddressSanitizer') || failed.stderr.contains('runtime error:') { return error('Missing clean explicit pre-publication validation: '+fatal_log) }
		results << map[string]json2.Any{'standard':json2.Any(standard),'invalid_mode':mode,'exit_code':failed.code,'output':failed.stderr.trim_space(),'executable_sha256':hosttest.sha(executable)!}
	}
}

fn body_name(body string) string {
	line := body.all_before('\n').all_before_last('(')
	return line.all_after_last(' ').trim_left('*')
}

fn full_module_parity(name string,selected string,work string) !json2.Any {
	root := hosttest.root()
	path := os.join_path(work,name+'-full-reference.c')
	hosttest.generate_module(os.join_path(root,'kernel/linuxkpi',name),path,'amd64',['linuxkpi_host_test','nofloat'])!
	full := hosttest.c_bodies(os.read_file(path)!)
	mut identical := map[string]string{}
	for body in hosttest.c_bodies(selected) {
		symbol := body_name(body)
		if symbol in ['compatcore__init_swait_queue_head','compatcore__complete','compatcore__wait_for_completion'] { continue }
		matches := full.filter(hosttest.named_body(it,symbol))
		if matches.len != 1 || matches[0] != body { return error('Changed full-module production body or initialization guard: '+symbol) }
		identical[symbol] = hosttest.text_sha(body)
	}
	return map[string]json2.Any{'reference_c_sha256':json2.Any(hosttest.sha(path)!),'byte_identical_body_sha256':hosttest.string_map(identical)}
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
	for directory in [os.join_path(work, 'include'), os.join_path(root, 'tests/linuxkpi/freefixture'), os.join_path(root, 'tests/linuxkpi/rcucallfixture'),
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
	work := hosttest.work_dir(keep, 'vinix-deferred-free-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	mut env := os.environ()
	env['VCACHE'] = os.join_path(work, 'vcache')
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	stage := os.join_path(work, 'stage')
	os.mkdir(stage)!
	mut observed := stage_sources(stage)!
	observed << [@FILE, os.join_path(root,'tests/linuxkpi/rcucallfixture/core.v'),os.join_path(root,'tests/linuxkpi/rcucallfixture/rcucall_host_contract.h')]
	observed << os.walk_ext(os.join_path(root,'tests/linuxkpi/freefixture'),'.v')
	observed << os.walk_ext(os.join_path(root,'tests/linuxkpi/freefixture'),'.h')
	observed << os.walk_ext(os.join_path(root, 'tests/linuxkpi/hosttest'), '.v')
	observed << os.walk_ext(os.join_path(root, 'kernel/linuxkpi/include'), '.h')
	for module_name in ['compatcore','headercore'] { observed << os.walk_ext(os.join_path(root,'kernel/linuxkpi',module_name),'.v') }
	observed << os.walk_ext(os.join_path(root,'kernel/c'),'.h')
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
			'void msleep(unsigned int); void rcuh_completion_init(void *); void rcuh_completion_complete(void *); void rcuh_completion_wait(void *);\n#include <string.h>\nvoid *vinix_linuxkpi_alloc_pages(size_t,bool);\n' }
		prefixes := if name == 'headercore' { ['cpu_bit_bitmap', 'cpu_all_bits', '__cpu_', '__num_online_cpus', 'nr_cpu_ids'] }
			else { ['compatcore__vkr_rcu_', 'compatcore__vkms_ready'] }
		selected := selected_source(raw, name + '__', header, prefixes)!
		os.write_file(os.join_path(work, name + '-selected.c'), selected)!
		proofs << map[string]json2.Any{'module': json2.Any(name), 'actual_generated_c_sha256': hosttest.sha(generated)!,
			'selected_c_sha256': hosttest.text_sha(selected), 'actual_body_count': hosttest.c_bodies(selected).len,
			'full_module_parity':full_module_parity(name,selected,work)!}
	}
	fixture_source := os.join_path(work, 'freefixture')
	stage_fixture(fixture_source)!
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
		run_cases(executable, standard, work, env, mut results)!

	}
	if initial != hosttest.hashes(observed)! { return error('Production/test source changed during checks') }
	hosttest.verify_upstream(linux, pin)!
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope': json2.Any(scope), 'source_sha256': hosttest.string_map(initial),
		'completion_transport_adapters': hosttest.strings(['init_swait_queue_head', 'complete', 'wait_for_completion']),
		'ordering_scope': json2.Any('Acquire/release transport witnesses and authentic generated full-fence bodies; this host matrix is not an independent relaxed payload publication litmus. Actual native full-fence object and IRQ-return evidence are required separately.'),
		'ownership_scope': json2.Any('Real tagged page-backed allocations and real cache objects; unsupported cache owners fail explicitly. This test supplies low-level page transport and never implements allocator-prefix or deferred-free logic.'),
		'actual_generated_body_proofs': proofs, 'runs': results,
		'compiler': tools, 'object_and_native_input_proofs': inputs,
		'upstream_pin': pin,
		'fixture_c_sha256': hosttest.sha(os.join_path(work, 'fixture.c'))!
	})!
	println('LinuxKPI deferred free: actual page allocator and RCU bodies, original heads, strict GNU99/GNU11 and host ASan/UBSan scenarios passed')
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-directory'], 'Usage: deferred_free.v [--keep-directory DIRECTORY]', scope) or { eprintln(err); exit(2) }
	run_profile(options['--keep-directory']) or { eprintln(err); exit(1) }
}
