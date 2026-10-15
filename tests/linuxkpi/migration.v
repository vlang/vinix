// SPDX-License-Identifier: GPL-2.0-or-later
// Exact native migration, scheduler policy and scanner bodies with V transport.
module main

import os
import json2
import hosttest

const scope = 'Execute actual production V migration/context APIs, scheduler eligibility/placement/capacity/parking and release/wake helpers, worker binding, preemption gates and runqueue scanning. Explicit V CPU/IRQ/task/atomic/IPI/lock/rank transport models do not prove real native CPU dispatch, idle wake, lock ownership or kernel allocation recovery. Labeled historical controls isolate the missing post-acquisition scanner check and inconsistent release-affinity observations.'

fn selected_source(raw string) !string {
	mut bodies := []string{}
	for body in hosttest.c_bodies(raw) {
		line := body.all_before('\n')
		if hosttest.named_body(body, 'array_get') && !body.contains('migrationfixture__borrowed_index') {
			continue
		}
		if hosttest.named_body(body, 'v_panic') && !body.contains('migrationfixture__unexpected_panic') {
			continue
		}
		if hosttest.named_body(body, '_v_panic') && !body.contains('migrationfixture__unexpected_assert') {
			continue
		}
		if hosttest.named_body(body, 'main') && !body.contains('migrationfixture__run') { continue }
		if hosttest.named_body(body, 'v_fixed_index') && !body.contains('migrationfixture__fixed_index(') {
			continue
		}
		if hosttest.named_body(body, 'v_fixed_index_u64') && !body.contains('migrationfixture__fixed_index_unsigned(') {
			continue
		}
		if hosttest.named_body(body, 'v3_eprint_lit') && !body.contains('migrationfixture__generated_diagnostic(') {
			continue
		}
		if ['linuxkpi__', 'sched__', 'migrationfixture__', 'cpu__', 'local__', 'proc__', 'katomic__',
			'lib__', 'apic__', 'klock__'].any(line.contains(it))
			|| line.contains(' mh_') || ['migrate_disable', 'migrate_enable',
			'vinix_linuxkpi_worker_bind', 'vinix_linuxkpi_test_worker_route',
			'vinix_linuxkpi_preempt_disable', 'vinix_linuxkpi_preempt_enable',
			'vinix_linuxkpi_preempt_enable_no_resched', 'vinix_linuxkpi_preempt_check_resched',
			'vinix_linuxkpi_preempt_count', 'vinix_linuxkpi_cpu_id', 'array_get', 'v_panic', '_v_panic',
			'v_fixed_index', 'v_fixed_index_u64', 'v3_eprint_lit', 'main', '_vno_main_init_caller'].any(hosttest.named_body(body, it)) {
			bodies << body
		}
	}
	if bodies.len < 60 { return error('Missing real migration/fixture bodies') }
	joined := bodies.join('\n')
	mut metadata := []string{}
	mut names := []string{}
	for line in raw.split_into_lines() {
		if !line.starts_with('typedef ') || line.contains('Array_fixed_') || line.contains('(*_fn_ptr_') {
			continue
		}
		if line.starts_with('typedef struct multi_return_') {
			name := line.all_after('typedef struct ').all_before(' ')
			if joined.contains(name) && line !in metadata {
				metadata << line
				names << name
			}
			continue
		}
		if ['migrationfixture__', 'sched__RunQueue', 'struct string ', 'struct array ',
			'typedef array Array;', 'multi_return_', 'local__Local', 'proc__Thread', 'proc__Process',
			'klock__Lock'].any(line.contains(it)) && !line.starts_with('typedef struct __v_') && line !in metadata {
			metadata << line
			if line.starts_with('typedef struct ') && !line.contains('{') {
				name := line.all_after('typedef struct ').all_before(' ')
				if name !in names { names << name }
			}
		}
	}
	mut records := []string{}
	for name in ['string', 'array', 'migrationfixture__Lock', 'migrationfixture__Params',
		'migrationfixture__State', 'migrationfixture__Process', 'migrationfixture__Thread',
		'migrationfixture__Local', 'sched__RunQueue'] {
		records << hosttest.record(raw, name)!
	}
	for name in names {
		if name.starts_with('multi_return_') { records << hosttest.record(raw, name)! }
	}
	mut late := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && (line.contains('Array_fixed_') || line.contains('(*_fn_ptr_')) {
			name := if line.contains('(*') {
				line.all_after('(*').all_before(')')
			} else {
				line.fields().last().all_before('[').all_before(';')
			}
			if joined.contains(name) && line !in late { late << line }
		}
	}
	mut constants := []string{}
	mut globals := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('#define ') && (['linuxkpi__', 'sched__', 'migrationfixture__', 'proc__',
			'errno__'].any(line.contains(it)) || line.starts_with('#define E_STRUCT ') || line.starts_with('#define _S(s) ')) {
			constants << line
		}
		if line.ends_with(';') && !line.contains('(') && !line.starts_with('typedef ') && !line.starts_with('extern ') && !line.starts_with('\t') && !line.starts_with(' ')
			&& ['linuxkpi__', 'sched__', 'local__', 'migrationfixture__', '_v3_no_main_initialized'].any(line.contains(it)) {
			globals << line
		}
	}
	declarations := bodies.map(it.all_before('\n').all_before_last(' {') + ';')
	prefix := '#include "migrationfixture/contract.h"\ntypedef uint8_t byte; typedef int32_t i32; typedef int64_t i64; typedef size_t usize; typedef void *voidptr;\n#define VNORETURN __attribute__((noreturn))\n' +
		metadata.join('\n') + '\n' + records.join('\n') + '\n' + late.join('\n') + '\n' + globals.join('\n') + '\n' + constants.join('\n') + '\n' + declarations.join('\n') + '\n'
	selected := prefix + bodies.join('\n\n') + '\n'
	if hosttest.c_bodies(selected) != bodies {
		return error('Metadata selection changed an actual generated body')
	}
	return selected
}

fn stage(work string) !([]string, []string, json2.Any) {
	root := hosttest.root()
	where := work + '/stage'
	for name in ['linuxkpi', 'sched', 'proc', 'x86/cpu/local', 'x86/cpu', 'x86/apic', 'katomic',
		'lib', 'klock', 'errno', 'time', 'migrationfixture'] {
		os.mkdir_all(where + '/' + name)!
	}
	mut inputs := [root + '/kernel/linuxkpi/migration_amd64.v',
		root + '/kernel/sched/migration_amd64.v', root + '/kernel/linuxkpi/worker_amd64.v',
		root + '/kernel/sched/policy.v', root + '/kernel/sched/runqueue.v',
		root + '/kernel/sched/sched_amd64.v', root + '/kernel/sched/park_amd64.v',
		root + '/kernel/linuxkpi/bridge_amd64.v']
	for path in ['kernel/linuxkpi/migration_amd64.v', 'kernel/sched/migration_amd64.v'] {
		os.cp(root + '/' + path, where + '/' + path.all_after('kernel/'))!
	}
	for path in ['core.v', 'contract.h'] {
		os.cp(root + '/tests/linuxkpi/migrationfixture/' + path, where + '/migrationfixture/' + path)!
	}
	worker := os.read_file(root + '/kernel/linuxkpi/worker_amd64.v')!
	os.write_file(where + '/linuxkpi/worker_selected.v', 'module linuxkpi\nimport errno\nimport katomic\nimport proc\nimport sched\nimport x86.cpu\nimport x86.cpu.local as cpulocal\n' + hosttest.v_function(worker, 'worker_bind')! + hosttest.v_function(worker, 'test_worker_route')!)!
	bridge := os.read_file(root + '/kernel/linuxkpi/bridge_amd64.v')!
	mut bridge_source := '@[has_globals]\nmodule linuxkpi\nimport lib\nimport x86.cpu\nimport x86.cpu.local as cpulocal\nimport sched\n__global (preempt_depth [256]u32 preempt_pending [256]bool)\n'
	for name in ['preempt_disable', 'preempt_enable', 'preempt_enable_no_resched', 'release_preemption',
		'native_preempt_count', 'native_cpu_id', 'preempt_check_resched'] {
		bridge_source += hosttest.v_function(bridge, name)!
	}
	bridge_source += "@[export:'mh_configure_bridge'] pub fn fixture_configure(){for i in 0..256 {preempt_depth[i]=0;preempt_pending[i]=false}}\n" +
		"@[export:'mh_get_bridge'] pub fn fixture_get(index u32,field u32)u64{return if field==0 {u64(preempt_depth[index])}else{u64(preempt_pending[index])}}\n" +
		"@[export:'mh_set_bridge'] pub fn fixture_set(index u32,field u32,value u64){if field==0 {preempt_depth[index]=u32(value)}else{preempt_pending[index]=value!=0}}\n"
	os.write_file(where + '/linuxkpi/bridge_selected.v', bridge_source)!
	runqueue := os.read_file(root + '/kernel/sched/runqueue.v')!
	mut queue_source := runqueue.all_before('pub fn cpu_capacity(')
	for name in ['cpu_capacity', 'set_cpu_capacity', 'placement_cpu', 'placement_cpu_with_affinity',
		'capacity_preferred', 'queue_append', 'queue_unlink', 'scan_run_queue'] {
		queue_source += hosttest.v_function(runqueue, name)!
	}
	scanner := hosttest.v_function(runqueue, 'scan_run_queue')!
	postcheck := '\t\t\tif katomic.load(&candidate.is_dead) || !may_run_here(candidate, cpu_number) {\n\t\t\t\tcandidate.l.release()\n\t\t\t\tcontinue\n\t\t\t}\n'
	if scanner.count(postcheck) != 1 {
		return error('Missing unique genuine post-lock scanner check')
	}
	historical := scanner.replace('fn scan_run_queue(', 'fn historical_scan_run_queue(').replace(postcheck, '')
	queue_source += '\n// Explicit historical test control: only the post-acquisition mandatory check is removed.\n' + historical
	os.write_file(where + '/sched/queue_selected.v', queue_source)!
	policy := os.read_file(root + '/kernel/sched/policy.v')!
	park := hosttest.v_function(os.read_file(root + '/kernel/sched/park_amd64.v')!, 'parking')!
	sched_prefix := '@[has_globals]\nmodule sched\nimport katomic\nimport proc\nimport migrationfixture as model\nimport x86.apic\n'
	os.write_file(where + '/sched/policy_selected.v', sched_prefix + hosttest.v_function(policy, 'may_run_here')! + hosttest.v_function(policy, 'may_run_here_with_affinity')! + '\n@[inline]\n' + park +
		hosttest.v_function(os.read_file(root + '/kernel/sched/sched_amd64.v')!, 'wake_cpu')!)!
	release := hosttest.v_function(os.read_file(root + '/kernel/sched/migration_amd64.v')!, 'request_migration_reschedule')!
	snapshot := '\taffinity := katomic.load(&task.affinity_mask)\n'
	if release.count(snapshot) != 1 || release.count('may_run_here_with_affinity(task,') != 2 || release.count('placement_cpu_with_affinity(task, affinity)') != 1 {
		return error('Missing unique genuine release-affinity snapshot')
	}
	// Explicit historical orchestration control: restore the prior independently
	// sampled source/placement/revalidation operations, keeping current genuine
	// shared policy/scorer implementations. No actual production body changes.
	old_release := release.replace('pub fn request_migration_reschedule(', 'fn historical_request_migration_reschedule(').replace(snapshot, '')
		.replace('may_run_here_with_affinity(task, u64(source_cpu), affinity)', 'may_run_here(task, u64(source_cpu))')
		.replace('placement_cpu_with_affinity(task, affinity)', 'placement_cpu(task)')
		.replace('may_run_here_with_affinity(task, target, affinity)', 'may_run_here(task, target)')
	os.write_file(where + '/sched/historical_release.v', 'module sched\nimport katomic\nimport lib\nimport proc\nimport x86.cpu\nimport x86.cpu.local as cpulocal\n' + old_release)!
	os.write_file(where + '/sched/transport.v', '@[has_globals]\nmodule sched\nimport proc\nimport migrationfixture as model\n__global(kernel_process &proc.Process sched_parking u32 sched_park_keeper u64 scheduler_vector u8)\n' +
		'fn clock_ns()u64{return 1}\nfn realtime_throttled(_cpu u64,_now u64)bool{return false}\nfn cgroup_parks(_task &proc.Thread,_state &model.State)bool{return false}\nfn runnable_rank(mut _task proc.Thread,_now u64,_throttled bool)int{return 0}\npub fn reschedule(){model.dispatch()}\n' +
		"@[export:'mh_configure_policy'] pub fn fixture_init(){kernel_process=model.kernel_owner_pointer();sched_parking=0;sched_park_keeper=0;scheduler_vector=49;for i in 0..256 {runqueues[i]=RunQueue{};cpu_capacities[i]=1024}}\n" +
		"@[export:'mh_queue_load'] pub fn fixture_load(index u32,count u64,capacity u32){runqueues[index].count=count;cpu_capacities[index]=capacity}\n" +
		"@[export:'mh_configure_queue'] pub fn fixture_queue(index u32,owner voidptr){mut t:=unsafe{&proc.Thread(owner)};runqueues[index].head=t;runqueues[index].tail=t;runqueues[index].count=1;t.queue_cpu=index;t.queue_previous=unsafe{nil};t.queue_next=unsafe{nil}}\n" +
		"@[export:'mh_parking'] pub fn fixture_park(value u32,keeper u64){sched_parking=value;sched_park_keeper=keeper}\n" +
		"@[export:'mh_may_run'] pub fn fixture_may(owner voidptr,number u64)bool{return may_run_here(unsafe{&proc.Thread(owner)},number)}\n" +
		"@[export:'mh_place'] pub fn fixture_place(owner voidptr)u64{return placement_cpu(unsafe{&proc.Thread(owner)})}\n" +
		"@[export:'mh_preferred'] pub fn fixture_prefer(owner voidptr,number u64)bool{return capacity_preferred(unsafe{&proc.Thread(owner)},number)}\n" +
		"@[export:'mh_request'] pub fn fixture_request(owner voidptr,number u32)bool{return request_migration_reschedule(unsafe{&proc.Thread(owner)},number)}\n" +
		"@[export:'mh_historical_request'] pub fn fixture_historical_request(owner voidptr,number u32)bool{return historical_request_migration_reschedule(unsafe{&proc.Thread(owner)},number)}\n" +
		"@[export:'mh_scan'] pub fn fixture_scan(number u64,last &int,historical bool)voidptr{return if historical {voidptr(historical_scan_run_queue(number,last,-1))}else{voidptr(scan_run_queue(number,last,-1))}}\n")!
	os.write_file(where + '/x86/cpu/local/transport.v', '@[has_globals]\nmodule local\nimport migrationfixture as model\npub type Local=model.Local\n__global cpu_locals []&Local\npub fn current()&Local{return model.cpu_local()}\n' + "@[export:'mh_configure_cpus'] pub fn configure(count i64){model.configure_cpus(unsafe{&cpu_locals},count)}\n")!
	os.write_file(where + '/proc/transport.v', 'module proc\nimport migrationfixture as model\npub type Thread=model.Thread\npub type Process=model.Process\npub const rank_deadline=200\npub fn current_thread()&Thread{return model.current_thread()}\npub fn scheduling_policies_in_use()bool{return false}\npub fn priority_donations_active()bool{return false}\n')!
	os.write_file(where + '/x86/cpu/transport.v', 'module cpu\nimport migrationfixture as model\npub fn interrupt_state()bool{return model.interrupt_state()}\npub fn interrupt_toggle(value bool)bool{return model.interrupt_toggle(value)}\n')!
	os.write_file(where + '/x86/apic/transport.v', 'module apic\nimport migrationfixture as model\npub fn lapic_send_ipi(lapic u32,vector u8){model.lapic_send_ipi(lapic,u64(vector))}\n')!
	os.write_file(where + '/katomic/transport.v', 'module katomic\nimport migrationfixture as model\npub fn load[T](value &T)T{return model.load(value)}\npub fn store[T](mut value T,item T){model.store(unsafe{&value},item)}\n')!
	os.write_file(where + '/lib/transport.v', 'module lib\nimport migrationfixture as model\n@[noreturn]pub fn kpanic(_frame voidptr,message &char){model.fatal(message)}\n')!
	os.write_file(where + '/klock/transport.v', 'module klock\nimport migrationfixture as model\npub type Lock=model.Lock\n')!
	os.write_file(where + '/errno/transport.v', 'module errno\npub const ewouldblock=11\npub const eopnotsupp=95\npub const einval=22\npub const eperm=1\npub const ebusy=16\n')!
	os.write_file(where + '/time/transport.v', 'module time\n')!
	os.write_file(where + '/v.mod', "Module {name:'native_migration_fixture'}\n")!
	os.write_file(where + '/entry.v', 'module main\nimport migrationfixture as _\nimport linuxkpi as _\nimport sched as _\nfn main(){}\n')!
	production_names := ['linuxkpi__migration_context', 'linuxkpi__native_migrate_disable',
		'migrate_disable', 'linuxkpi__native_migrate_enable', 'migrate_enable',
		'sched__request_migration_reschedule', 'sched__may_run_here',
		'sched__may_run_here_with_affinity', 'sched__parking', 'sched__cpu_capacity',
		'sched__placement_cpu', 'sched__placement_cpu_with_affinity', 'sched__capacity_preferred',
		'sched__queue_append', 'sched__queue_unlink', 'sched__scan_run_queue', 'sched__wake_cpu',
		'linuxkpi__worker_bind', 'vinix_linuxkpi_worker_bind', 'linuxkpi__test_worker_route',
		'vinix_linuxkpi_test_worker_route', 'linuxkpi__preempt_disable',
		'vinix_linuxkpi_preempt_disable', 'linuxkpi__preempt_enable', 'vinix_linuxkpi_preempt_enable',
		'linuxkpi__preempt_enable_no_resched', 'vinix_linuxkpi_preempt_enable_no_resched',
		'linuxkpi__release_preemption', 'linuxkpi__native_preempt_count', 'vinix_linuxkpi_preempt_count',
		'linuxkpi__native_cpu_id', 'vinix_linuxkpi_cpu_id', 'linuxkpi__preempt_check_resched',
		'vinix_linuxkpi_preempt_check_resched']
	return inputs, production_names, {
		'current_scan_sha256':             json2.Any(hosttest.text_sha(scanner))
		'historical_scan_sha256':          hosttest.text_sha(historical)
		'removed_exact_check_sha256':      hosttest.text_sha(postcheck)
		'current_release_sha256':          hosttest.text_sha(release)
		'historical_release_sha256':       hosttest.text_sha(old_release)
		'removed_release_snapshot_sha256': hosttest.text_sha(snapshot)
		'scope':                           'Labeled historical scanner control removes only its post-acquisition eligibility block. Historical release orchestration removes only the single affinity capture and restores the three independently observed source/scorer/revalidation calls, sharing genuine current policy/scorer bodies. All actual production functions remain unchanged; native leaf transports are modeled explicitly.'
	}
}

fn compile_input(argv []string, source string, object string, log string, environment map[string]string) !json2.Any {
	preprocessed := object + '.i'
	depfile := object + '.d'
	hosttest.command([...argv, '-E', '-dD', '-MD', '-MF', depfile, '-MQ', object, source, '-o',
		preprocessed], log + '.preprocess', 180, environment)!
	dependencies := hosttest.dependency_paths(os.read_file(depfile)!, object)!
	before := hosttest.hashes(dependencies)!
	hosttest.command([...argv, '-c', source, '-o', object], log, 180, environment)!
	if before != hosttest.hashes(dependencies)! { return error('Compiler input changed') }
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

fn production_objects(work string, raw string, selected string, names []string, environment map[string]string) !json2.Any {
	mut bodies := []string{}
	for name in names { bodies << hosttest.extract_body(raw, name)! }
	first := hosttest.c_bodies(selected)[0]
	metadata := selected.all_before(first).replace('#include "migrationfixture/contract.h"',
		'#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\ntypedef uint8_t u8; typedef uint32_t u32; typedef uint64_t u64; typedef uintptr_t mh_thread; typedef struct array mh_array; typedef struct string mh_string;\n')
	source := work + '/production.c'
	os.write_file(source, metadata + '\ni64 v_fixed_index(i64, i64);\ni64 v_fixed_index_u64(u64, i64);\nvoid exit(int) __attribute__((noreturn));\n' + bodies.join('\n\n') + '\n')!
	if hosttest.c_bodies(os.read_file(source)!) != bodies {
		return error('Production-only extraction changed an actual body')
	}
	mut objects := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O1', 'O2'] {
			object := work + '/production-' + standard + '-' + optimization + '.o'
			argv := [hosttest.env_default('CC', 'clang'), '--target=x86_64-unknown-none',
				'-std=' + standard, '-' + optimization, '-ffreestanding', '-fno-builtin', '-fwrapv',
				'-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
				'-nostdinc', '-isystem', hosttest.root() + '/kernel/freestnd-c-hdrs']
			proof := compile_input(argv, source, object, object + '.compile.log', environment)!
			imports := hosttest.command([hosttest.tool('llvm-nm'), '--undefined-only', object], object + '.imports.log', 30, environment)!.stdout
			mut actual := []string{}
			for line in imports.split_into_lines() {
				if line.fields().len > 0 { actual << line.fields().last() }
			}
			mut expected := ['apic__lapic_send_ipi', 'array_get', 'cpu__interrupt_state',
				'cpu__interrupt_toggle', 'katomic__load_T_bool', 'katomic__load_T_u32',
				'katomic__load_T_u64', 'katomic__store_T_u64', 'katomic__store_T_v_int', 'lib__kpanic',
				'local__current', 'migrationfixture__Lock__acquire', 'migrationfixture__Lock__release',
				'migrationfixture__Lock__test_and_acquire', 'proc__current_thread',
				'proc__priority_donations_active', 'proc__scheduling_policies_in_use',
				'sched__cgroup_parks', 'sched__clock_ns', 'sched__realtime_throttled',
				'sched__reschedule', 'sched__runnable_rank', 'v_fixed_index', 'v_fixed_index_u64',
				'v3_eprint_lit', 'exit']
			// Native C99 inline parking and compiler scalar/aggregate diagnostics
			// remain external at O0; optimized objects fold these exact call sites.
			if optimization == 'O0' { expected << ['memset', 'sched__parking', 'v_panic'] }
			actual.sort()
			expected.sort()
			if actual != expected || hosttest.allocation_symbols(imports) {
				return error('Unexpected production-only imports: ' + imports)
			}
			objects << json2.Any({
				'standard':     json2.Any(standard)
				'optimization': optimization
				'compiled':     proof
				'imports':      hosttest.strings(actual)
			})
		}
	}
	return {
		'objects': json2.Any(objects)
		'scope':   'All 34 actual staged production algorithm and export bodies separately compiled without fixture implementations for freestanding x86_64-unknown-none. Compiler record/descriptor declarations and smaller explicit host Thread/Process/Local metadata remain; only listed native leaf transports, bounds checks and assertion diagnostics are unresolved. This is staged raw/selected/production body parity, not full native-kernel blob parity.'
	}
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	hosttest.verify_upstream(linux, hosttest.upstream_pin()!)!
	work := hosttest.work_dir(keep, 'vinix-migration-v-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	mut inputs, names, historical := stage(work)!
	inputs << [@FILE, root + '/kernel/linuxkpi/include/linux/preempt.h',
		root + '/kernel/linuxkpi/include/vinix/runtime.h', root + '/kernel/linuxkpi/upstream.json']
	for directory in ['tests/linuxkpi/migrationfixture', 'tests/linuxkpi/hosttest'] {
		for extension in ['.v', '.h'] { inputs << os.walk_ext(root + '/' + directory, extension) }
	}
	before := hosttest.hashes(inputs)!
	compiler := os.real_path(hosttest.command(['sh', '-c',
		'. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root], '', 30, os.environ())!.stdout)
	compiler_before := hosttest.sha(compiler)!
	mut environment := os.environ()
	environment['VCACHE'] = work + '/vcache'
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	environment['UBSAN_OPTIONS'] = 'halt_on_error=1'
	environment['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	raw_path := work + '/generated.c'
	generation := [compiler, '-nocache', '-no-closures', '-os', 'vinix', '-arch', 'amd64',
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-d', 'nofloat', '-d', 'linuxkpi',
		'-d', 'linuxkpi_host_test', '-o', raw_path, work + '/stage']
	hosttest.command(generation, work + '/generation.log', 180, environment)!
	raw := os.read_file(raw_path)!
	selected := work + '/selected.c'
	os.write_file(selected, selected_source(raw)!)!
	mut body_hashes := map[string]string{}
	for name in names {
		body := hosttest.extract_body(raw, name)!
		if body != hosttest.extract_body(os.read_file(selected)!, name)! {
			return error('Actual body changed ' + name)
		}
		if ['__eq_lhs_', '__eq_rhs_', '__ptr_eq_', 'Process__eq'].any(body.contains(it)) {
			return error('Generated structural comparison in actual production body ' + name)
		}
		for allocator in ['malloc', 'calloc', 'realloc', 'memdup', 'v_malloc', 'new_array',
			'array_clone', 'array_push'] {
			if hosttest.has_word(body, allocator) {
				return error('Allocation in actual production body ' + name)
			}
		}
		body_hashes[name] = hosttest.text_sha(body)
	}
	include := work + '/include'
	hosttest.audit_headers(include)!
	mut includes := ['-D__KERNEL__', '-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-include',
		root + '/tests/linuxkpi/host_types.h', '-include', 'linux/kconfig.h', '-include',
		linux + '/include/linux/compiler_types.h']
	for directory in [work + '/stage', include, root + '/kernel/linuxkpi/include', linux + '/include',
		linux + '/include/uapi', linux + '/arch/x86/include', linux + '/arch/x86/include/uapi'] {
		includes << ['-I', directory]
	}
	mut common := [hosttest.env_default('CC', 'clang'), '-g', '-ffreestanding', '-fno-builtin',
		'-fwrapv', '-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-parameter', '-pthread', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	$if macos {
		common << ['-arch', 'x86_64']
	}
	mut profiles := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for optimization in ['O0', 'O1', 'O2'] {
			tag := standard + '-' + optimization
			object := work + '/' + tag + '.o'
			executable := work + '/' + tag
			proof := compile_input([...common, '-std=' + standard, '-' + optimization, ...includes], selected, object, work + '/' + tag + '.compile.log', environment)!
			imports := hosttest.command(['nm', '-u', object], work + '/' + tag + '.imports.log', 30, environment)!.stdout
			if hosttest.allocation_symbols(imports) {
				return error('Migration fixture imports allocator ' + imports)
			}
			hosttest.command([...common, object, '-o', executable], work + '/' + tag + '.link.log', 180, environment)!
			result := hosttest.command([executable], work + '/' + tag + '.run.log', 180, environment)!
			if !result.stdout.contains('PASS: V sleep-preserving migration pins') || result.stderr != '' {
				return error('Incomplete/diagnosed migration fixture')
			}
			profiles << json2.Any({
				'standard':          json2.Any(standard)
				'optimization':      optimization
				'compiled':          proof
				'executable_sha256': hosttest.sha(executable)!
				'run_log':           work + '/' + tag + '.run.log'
				'output':            result.stdout
			})
			println(tag + ': ' + result.stdout.trim_space())
		}
	}
	production := production_objects(work, raw, os.read_file(selected)!, names, environment)!
	if before != hosttest.hashes(inputs)! || compiler_before != hosttest.sha(compiler)! {
		return error('Migration source/compiler changed during validation')
	}
	hosttest.write_json(work + '/result.json', {
		'scope':                   json2.Any(scope)
		'source_sha256':           hosttest.string_map(before)
		'compiler':                compiler
		'compiler_sha256':         compiler_before
		'generation_argv':         hosttest.strings(generation)
		'generated_sha256':        hosttest.sha(raw_path)!
		'selected_sha256':         hosttest.sha(selected)!
		'production_body_sha256':  hosttest.string_map(body_hashes)
		'historical_control':      historical
		'profiles':                profiles
		'production_only_objects': production
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: migration.v [--keep-dir NEW]', scope) or {
		eprintln(err)
		exit(2)
	}
	run_profile(keep) or {
		eprintln(err)
		exit(1)
	}
}
