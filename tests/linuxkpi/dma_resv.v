// SPDX-License-Identifier: GPL-2.0-or-later
// Actual V reservation/WD/fence/IRQ/RCU bodies and bounded host transport.
module main

import os
import json2
import hosttest

const scope = 'Execute actual production V reservation, WD writer locks, base/array fences, IRQ-work, page allocator, ordinary RCU, task and time algorithms with original Linux records. Native CPU/IRQ/page/clock transport is modeled; native IRQ-return and retained-kernel-allocation evidence remains separate.'

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
		if line.contains(prefix) || line.contains(' dma_resv_') || line.contains(' vdr_') || line.contains(' vkw_') || line.contains(' ww_mutex_') || line.contains(' __mutex_init(') || line.contains(' mutex_is_locked(') || line.contains(' mutex_destroy(') || line.contains(' kmalloc_size_roundup(') || line.contains(' krealloc_array(') || line.contains(' cpu_relax(') || line.contains(' vdf_') || line.contains(' vfa_') || line.contains(' vfc_') || line.contains(' vkiw_') || line.contains(' irq_work_') || line.contains(' arch_irq_work_raise(') || line.contains(' dma_fence_') || line.contains(' vinix_linuxkpi_set_task_state(') || line.contains(' vinix_linuxkpi_time_') || line.contains(' wake_up_') || line.contains(' schedule(') || line.contains(' schedule_timeout(') || line.contains(' ktime_get(') || line.contains(' get_task_struct(') || line.contains(' put_task_struct(') || line.contains(' signal_pending') || line.contains(' vkp_') || line.contains(' refcount_warn_saturate(') || line.contains(' add_taint(') || line.contains(' test_taint(') || line.contains(' get_taint(') || line.contains(' vinix_linuxkpi_warn(') || line.contains(' vinix_linuxkpi_refcount_warning(') || line.contains(' vinix_linuxkpi_task_in_iowait(') || line.contains(' vkr_') || line.contains(' vkm_')
			|| line.contains(' vinix_linuxkpi_gfp_supported(') || line.contains(' vinix_linuxkpi_alloc_gfp_pages(') || line.contains(' vinix_linuxkpi_tigerlake_id(')
			|| line.contains(' kmalloc(') || line.contains(' kzalloc(') || line.contains(' kmalloc_array(') || line.contains(' kcalloc(') || line.contains(' ksize(') || line.contains(' kfree(') || line.contains(' krealloc(') || line.contains(' kmemdup(') || line.contains(' kmem_cache_') || line.contains(' kvfree(') || line.contains(' kvfree_call_rcu(')
			|| line.contains(' call_rcu(') || line.contains(' synchronize_rcu') || line.contains(' rcu_barrier(') || line.contains(' get_state_synchronize_rcu(') || line.contains(' start_poll_synchronize_rcu(') || line.contains(' poll_state_synchronize_rcu(') || line.contains(' cond_synchronize_rcu(')
			|| line.contains(' __bitmap_weight(') || line.contains(' arch_atomic64_add_return_relaxed(') || line.contains(' arch_atomic_read(') || line.contains(' arch_atomic_set(') || line.contains(' arch_atomic_fetch_add_relaxed(') || line.contains(' arch_atomic_fetch_sub_relaxed(') || line.contains(' arch_atomic_cmpxchg_relaxed(') {
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
		if declaration.contains('(') && !declaration.contains(' = ') { continue }
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
		for name in ['RcuWorker', 'RuntimeAllocation', 'CacheList', 'CacheSlot', 'CacheSlab', 'Cache',
			'VktDeadline', 'IrqWorkRun', 'WwWaiter'] {
			record_metadata << 'typedef struct compatcore__${name} compatcore__${name};'
		}
		for name in ['RcuWorker', 'RuntimeAllocation', 'CacheList', 'CacheSlot', 'CacheSlab', 'Cache',
			'VktDeadline', 'IrqWorkRun', 'WwWaiter'] {
			record_metadata << hosttest.record(raw, 'compatcore__' + name)!
		}
	}
	mut zero_metadata := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('#define E_STRUCT ') || line.starts_with('#define compatcore__page_allocation_tag ') {
			zero_metadata << line
		}
	}
	text := '#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n' +
		(if prefix == 'headercore__' {
			'typedef uint64_t u64;\n'
		} else {
			'typedef uint8_t u8; typedef uint32_t u32; typedef uint64_t u64; typedef uint16_t u16;\n'
		}) +
		'typedef int32_t i32; typedef int64_t i64; typedef size_t usize; typedef intptr_t isize; typedef void *voidptr;\n' +
		header + callback_types.join('\n') + '\n' + record_metadata.join('\n') + '\n' + zero_metadata.join('\n') + '\n' + declarations.join('\n') + '\n' + globals.join('\n') + '\n' +
		bodies.join('\n\n') + '\n'
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
		'compatcore': ['rcu.v', 'smp_masks.v', 'runtime.v', 'cache.v', 'dma_fence.v',
			'dma_fence_array.v', 'dma_fence_chain.v', 'dma_resv.v', 'allocation_helpers.v', 'ww_mutex.v',
			'irq_work.v', 'taint.v', 'refcount.v']
		'headercore': ['rcu.v', 'smp_masks.v', 'smp_masks_storage.v', 'dma_fence.v', 'dma_fence_array.v',
			'dma_fence_chain.v', 'dma_resv.v', 'irq_work.v']
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
		'struct C.callback_head {}\nstruct C.vkw_list { mut: next &C.vkw_list, prev &C.vkw_list }\n' +
		'struct C.vkw_swait_head { lock u32, task_list C.vkw_list }\n' +
		'struct C.vkw_completion { done u32, @wait C.vkw_swait_head }\n' +
		'fn C.kzalloc(usize,u32) voidptr\nfn C.kfree(voidptr)\nfn C.memset(voidptr,i32,usize) voidptr\nfn C.memcpy(voidptr,voidptr,usize) voidptr\nfn C.strlen(voidptr) usize\nfn C.kmalloc(usize,u32) voidptr\nfn C.vinix_linuxkpi_page_size() usize\nfn C.vinix_linuxkpi_free_pages(voidptr,usize)\nfn C.vinix_linuxkpi_alloc_gfp_pages(usize,u32) voidptr\nfn C.vinix_linuxkpi_gfp_supported(u32) bool\nfn C.vkp_cache_ctor_warning(bool)\n' +
		'fn C._printk(&char,...)i32\nfn C.vinix_linuxkpi_bug(&char,i32)\nfn C.vinix_linuxkpi_irq_flags() u64\n' +
		'fn C.vinix_linuxkpi_may_sleep() bool\nfn C.vinix_linuxkpi_spin_wait()\nfn C.vinix_linuxkpi_cond_resched() i32\n' +
		'fn C.vinix_linuxkpi_preempt_disable()\nfn C.vinix_linuxkpi_preempt_enable()\n' +
		'fn C.vkp_spin_init(voidptr)\nfn C.vkp_spin_lock_irqsave(voidptr) u64\n' +
		'fn C.vkp_spin_unlock_irqrestore(voidptr,u64)\nfn C.msleep(u32)\n' +
		'fn C.rcuh_completion_init(voidptr)\nfn C.rcuh_completion_complete(voidptr)\nfn C.rcuh_completion_wait(voidptr)\n' +
		'fn init_swait_queue_head(p voidptr,_name &char,_key voidptr) { C.rcuh_completion_init(p) }\n' +
		'fn complete(p voidptr) { C.rcuh_completion_complete(p) }\n' +
		'fn wait_for_completion(p voidptr) { C.rcuh_completion_wait(p) }\n' +
		'__global vkr_host_guard_anchor i32 = -1\n'
	for name in ['require', 'is_null', 'native_hweight_long'] {
		bindings += hosttest.v_function(os.read_file(primitive)!, name)!
	}
	bindings += hosttest.v_function(os.read_file(bitmap)!, 'bitmap_weight')!
	bindings += '\nfn C.vinix_linuxkpi_cpu_id()u32\nfn C.vinix_linuxkpi_maskable_irq_depth()u32\nfn C.vinix_linuxkpi_preempt_count()u32\nfn C.vinix_linuxkpi_irq_save()u64\nfn C.vinix_linuxkpi_irq_restore(u64)\nfn C.vinix_linuxkpi_smp_task_present()bool\nfn C.vinix_linuxkpi_smp_boot_context()bool\nfn C.vks_smp_ready()bool\n'

	// The original WD writer lock executes unchanged; only selected mutex
	// initialization/destruction bodies are needed below the upstream inline.
	sync_path := os.join_path(root, 'kernel/linuxkpi/compatcore/sync.v')
	bit_path := os.join_path(root, 'kernel/linuxkpi/compatcore/wait_bit.v')
	owned << [sync_path, bit_path]
	mut sync_stage := '@[translated]\nmodule compatcore\n#include "linuxkpi_wait_v_primitives.h"\n'
	for name in ['mutex_init', 'mutex_is_locked', 'mutex_destroy'] {
		sync_stage += hosttest.v_function(os.read_file(sync_path)!, name)!
	}
	sync_stage += hosttest.v_function(os.read_file(bit_path)!, 'wait_list_init')!
	os.write_file(os.join_path(work, 'compatcore/mutex_selected.v'), sync_stage)!
	bindings += '\n@[c: "__atomic_load_n"]\nfn C.vkw_load_pointer(&voidptr,i32)voidptr\n@[c: "__atomic_store_n"]\nfn C.vkw_store_pointer(&voidptr,voidptr,i32)\nfn C.vkp_schedule()\n'
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
	// Exact production task/time wait bodies; host code supplies only the native
	// run queue, park, signal, CPU scope, page and clock transport below them.
	task_path := os.join_path(root, 'kernel/linuxkpi/compatcore/task.v')
	time_path := os.join_path(root, 'kernel/linuxkpi/compatcore/time.v')
	io_path := os.join_path(root, 'kernel/linuxkpi/compatcore/io.v')
	common_path := os.join_path(root, 'kernel/linuxkpi/headercore/common.v')
	owned << [task_path, time_path, io_path, common_path]
	task_raw := os.read_file(task_path)!
	mut task_stage := task_raw.all_before('fn vkt_copy_comm(')
	for name in ['set_task_state', 'vkt_signal_pending', 'task_schedule', 'task_wake_state',
		'task_wake_process'] {
		task_stage += hosttest.v_function(task_raw, name)!
	}
	os.write_file(os.join_path(work, 'compatcore/task_selected.v'), task_stage)!
	time_raw := os.read_file(time_path)!
	mut time_stage := time_raw.all_before('fn vkt_deadline_add(')
	for name in ['vkt_deadline_add', 'vkt_deadline_remove', 'time_tick', 'time_waiters',
		'time_task_waiters', 'time_schedule_timeout', 'time_ktime_get'] {
		time_stage += hosttest.v_function(time_raw, name)!
	}
	os.write_file(os.join_path(work, 'compatcore/time_selected.v'), time_stage)!
	mut extra := '\nfn C.vkp_load32(&u32,i32)u32\nfn C.vkp_store32(&u32,u32,i32)\nfn C.vkp_store_signed(&i32,i32,i32)\nfn C.vkp_load_signed(&i32,i32)i32\nfn C.vkp_compare_signed(&i32,&i32,i32,bool,i32,i32)bool\nfn C.vkp_or64(&u64,u64,i32)u64\nfn C.vkp_load64(&u64,i32)u64\nfn C.vkp_spin_lock(voidptr)\nfn C.vkp_spin_unlock(voidptr)\nfn C.vkp_refcount_dec_and_test(voidptr)bool\nfn C.vkp_mutex_lock(voidptr)\nfn C.vkp_mutex_unlock(voidptr)\nfn C.vkp_current()voidptr\nfn C.vkp_iowait_field(voidptr)voidptr\nfn C.vkp_schedule_timeout(i64)i64\nfn C.vkp_signal_pending(i32)bool\nfn C.vkp_jiffies()u64\nfn C.kmalloc_array(usize,usize,u32)voidptr\nfn C.vkp_warn(&char,i32)\nfn C.vkp_warn_note(&char,i32)\nfn C.vkp_refcount_warning(i32)\nfn C.vkp_refcount_note(i32)\n'
	// Preserve the compiler intrinsic attributes from the real declarations.
	for line in extra.split_into_lines() {
		if (line.starts_with('fn C.vkp_') && line.contains('(&')) || line.starts_with('fn C.vkp_or64(') {
			extra = extra.replace(line + '\n', '')
		}
	}
	extra += os.read_file(primitive)!.all_before('fn native_isspace(').all_after('module compatcore')
	extra += hosttest.v_function(os.read_file(io_path)!, 'task_in_iowait')!
	os.write_file(os.join_path(work, 'compatcore/extra.v'), '@[translated]\nmodule compatcore\n' + extra)!
	mut h := os.read_file(os.join_path(work, 'headercore/bindings.v'))!
	h += '\n@[typedef]\nstruct C.spinlock_t { locked u32 }\nfn C.vinix_linuxkpi_task_get(voidptr)\nfn C.vinix_linuxkpi_task_put(voidptr)\nfn C.vinix_linuxkpi_task_signal_pending(voidptr,bool)bool\nfn C.schedule_timeout(isize)isize\nfn C.signal_pending_state(u32,&C.task_struct)i32\nfn C.READ_ONCE(usize)usize\n@[c_extern]\n__global C.jiffies usize\n'
	h += "@[c:'__atomic_fetch_add']\nfn C.vhp_add32(&i32,i32,i32)i32\n@[c:'__atomic_fetch_sub']\nfn C.vhp_sub32(&i32,i32,i32)i32\n@[c:'__atomic_store_n']\nfn C.vhp_store32(&i32,i32,i32)\n@[c:'__atomic_compare_exchange_n']\nfn C.vhp_compare32(&i32,&i32,i32,bool,i32,i32)bool\n"
	h += '\nfn C.vinix_linuxkpi_spin_wait()\n'
	h += '\nfn C.vinix_linuxkpi_cpu_id()u32\n'
	for name in ['cpu_relax', 'atomic_set', 'atomic_cmpxchg', 'atomic_fetch_add_relaxed',
		'atomic_fetch_sub_relaxed', 'get_task', 'put_task', 'signal_pending', 'fatal_signal_pending',
		'signal_pending_state'] {
		h += hosttest.v_function(os.read_file(atomic_path)!, name)!
	}
	for name in ['common_current', 'common_iowait_field', 'common_schedule', 'common_schedule_timeout',
		'common_signal_pending', 'common_jiffies'] {
		h += hosttest.v_function(os.read_file(common_path)!, name)!
	}
	h = h.replace('struct C.task_struct { vinix_thread voidptr, __state u32 }', 'struct C.task_struct { vinix_thread voidptr, __state u32, in_iowait u32 }')

	wait_path := os.join_path(root, 'kernel/linuxkpi/headercore/wait.v')
	owned << wait_path
	for name in ['wait_signal_state', 'wait_current_state', 'wait_wake_task'] {
		h += hosttest.v_function(os.read_file(wait_path)!, name)!
	}
	h += '\nfn C.set_current_state(u32)\nfn C.wake_up_process(&C.task_struct)i32\n'
	h += '\nfn C.schedule()\n'
	h += '\n@[typedef]\nstruct C.atomic64_t { counter i64 }\n@[typedef]\nstruct C.vhp_s64 {}\n' +
		"@[c: '__atomic_add_fetch']\nfn C.vhp_add_return64(&i64,i64,i32)i64\n"
	for name in ['bits', 'native64', 'atomic64_add_return_relaxed'] {
		h += hosttest.v_function(os.read_file(atomic_path)!, name)!
	}
	os.write_file(os.join_path(work, 'headercore/bindings.v'), h)!

	return owned
}

fn stage_fixture(directory string) ! {
	root := hosttest.root()
	os.mkdir(directory)!
	os.cp(os.join_path(root, 'tests/linuxkpi/resvfixture/core.v'), os.join_path(directory, 'core.v'))!
	original := os.read_file(os.join_path(root, 'tests/linuxkpi/rcucallfixture/core.v'))!
	mut transport := original.all_before('fn callback(head &C.callback_head) {').replace('module rcucallfixture', 'module resvfixture')
	for attribute in ["@[export: 'kzalloc']", "@[export: 'kfree']",
		"@[export: 'vinix_linuxkpi_bug'; noreturn]", "@[export: 'vkr_page_allocation_size']",
		"@[export: 'vkr_kvfree']", "@[export: 'get_task_struct']", "@[export: 'put_task_struct']",
		"@[export: 'vkp_spin_lock_irqsave']"] {
		transport = transport.replace(attribute + ' pub fn', attribute + '\npub fn')
	}
	for name in ['allocate', 'deallocate', 'bug', 'unsupported_page_owner', 'unsupported_page_free',
		'await_return', 'await_poll', 'get_task', 'put_task'] {
		transport = transport.replace(hosttest.v_function(transport, name)!, '')
	}
	transport = transport.replace('\tconstructor bool', '\tpresent bool = true\n\tqueued u32 = 1\n\tpending u32\n\tparks u32\n\tirq_guard_count u32\n\tirq_pause_at u32\n\tirq_pause_entered &u32 = unsafe { nil }\n\tirq_pause_release &u32 = unsafe { nil }\n\tconstructor bool')
	transport = transport.replace('pub fn task_present() bool { return true }', 'pub fn task_present() bool { return context().present }')
	transport = transport.replace('ctx.refs = 1', 'ctx.refs = 1\n\t\tctx.present = true\n\t\tctx.queued = 1')
	os.write_file(os.join_path(directory, 'transport.v'), transport)!
	container := os.read_file(os.join_path(root, 'tests/linuxkpi/fencecontainerfixture/core.v'))!
	mut native := '@[translated]\nmodule resvfixture\n'
	for name in ['native_task_get', 'native_task_put', 'native_pending', 'native_dequeue',
		'native_enqueue', 'native_dead', 'native_park', 'unsupported_iowait', 'native_clock',
		'timer_observation', 'plain_lock', 'plain_unlock', 'warning', 'warning_note', 'refcount_warning',
		'refcount_note', 'unsupported_refcount_lock', 'unsupported_mutex', 'unsupported_mutex_unlock',
		'advance'] {
		native += hosttest.v_function(container, name)!
	}
	os.write_file(os.join_path(directory, 'native.v'), native)!
	free_raw := os.read_file(os.join_path(root, 'tests/linuxkpi/freefixture/core.v'))!
	mut pages := free_raw.all_before('fn live()').replace('module freefixture', 'module resvfixture')
	pages = pages.replace("@[export:'vinix_linuxkpi_bug'; noreturn] pub fn", "@[export:'vinix_linuxkpi_bug'; noreturn]\npub fn")
	pages = pages.replace(hosttest.v_function(pages, 'bug')!, '')
	pages = pages.replace('if C.rcuh_load32(&page_fail) != 0 { return nil }',
		'if C.rcuh_load32(&page_fail) != 0 || page_should_fail() { return nil }')
	pages = pages.replace('check(C.posix_memalign(&base, 4096, pages * 4096) == 0 && base != nil, @LINE)',
		'if reused_page != nil { check(pages == 1,@LINE); base = reused_page; reused_page = nil } else { check(C.posix_memalign(&base,4096,pages * 4096) == 0 && base != nil,@LINE) }')
	pages = pages.replace('page_unlock(); C.free(base)',
		'page_unlock(); if capture_page { check(reused_page == nil && pages == 1,@LINE); capture_page = false; reused_page = base } else { C.free(base) }')
	os.write_file(os.join_path(directory, 'pages.v'), pages)!
}

fn run_cases(executable string, standard string, work string, env map[string]string, mut results []json2.Any) ! {
	log := os.join_path(work, standard + '-safe.log')
	passed := command([executable, '0'], log, env)!
	if passed.stderr != '' || !passed.stdout.contains('PASS: ') {
		return error('Missing clean DMA-fence verdict: ' + log)
	}
	results << map[string]json2.Any{
		'standard':          json2.Any(standard)
		'mode':              0
		'output':            passed.stdout.trim_space()
		'executable_sha256': hosttest.sha(executable)!
	}
	for mode := 10; mode <= 15; mode++ {
		fatal_log := os.join_path(work, '${standard}-invalid-${mode}.log')
		failed := hosttest.capture([executable, mode.str()], fatal_log, 30, env)!
		if failed.code == 0 || !failed.stderr.contains('Reservation invariant:')
			|| !failed.stderr.contains('Reservation validation preserved original48/64 storage and allocation count')
			|| failed.stderr.contains('ERROR: AddressSanitizer') || failed.stderr.contains('runtime error:') {
			return error('Missing clean reservation validation: ' + fatal_log)
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

fn identifier_byte(ch u8) bool {
	return ch == `_` || ch >= `a` && ch <= `z` || ch >= `A` && ch <= `Z` || ch >= `0` && ch <= `9`
}

// Parse the declaration's outer identifier, excluding balanced compiler
// attributes. Callback parameter names cannot overwrite another function's
// proof entry. Production names are unique; fixture alternatives get ordinals.
fn body_name(body string) !string {
	line := body.all_before('\n')
	mut index := 0
	for index < line.len {
		if line[index] != `(` {
			index++
			continue
		}
		mut begin := index
		for begin > 0 && identifier_byte(line[begin - 1]) { begin-- }
		name := line[begin..index]
		if name == '__attribute__' || name == '__declspec' {
			mut depth := 1
			index++
			for index < line.len && depth != 0 {
				if line[index] == `(` { depth++ }
				if line[index] == `)` { depth-- }
				index++
			}
			if depth != 0 { return error('Unbalanced generated declaration attribute') }
			continue
		}
		if name.len == 0 { return error('Missing outer generated function identifier') }
		return name
	}
	return error('Missing generated function declaration')
}

// Independently enumerate fixture definitions, including one-line compiler
// helpers and both conditional implementations sharing a C identifier.
fn fixture_bodies(raw string) ![]string {
	mut bodies := []string{}
	mut start := 0
	for start < raw.len {
		line_end := start + (raw[start..].index('\n') or { raw.len - start })
		line := raw[start..line_end]
		brace := line.index('{') or {
			start = line_end + 1
			continue
		}
		header := line[..brace]
		if line.len == 0 || line[0].is_space() || line[0] == `#`
			|| !header.contains('(') || header.contains(';') || header.contains('=') {
			start = line_end + 1
			continue
		}
		mut index := start + brace
		mut depth := 0
		mut quote := u8(0)
		mut block_comment := false
		mut line_comment := false
		for index < raw.len {
			ch := raw[index]
			if line_comment {
				if ch == `\n` { line_comment = false }
				index++
				continue
			}
			if block_comment {
				if ch == `*` && index + 1 < raw.len && raw[index + 1] == `/` {
					block_comment = false
					index += 2
				} else {
					index++
				}
				continue
			}
			if quote != 0 {
				if ch == `\\` {
					index += 2
					continue
				}
				if ch == quote { quote = 0 }
				index++
				continue
			}
			if ch == `/` && index + 1 < raw.len {
				if raw[index + 1] == `/` {
					line_comment = true
					index += 2
					continue
				}
				if raw[index + 1] == `*` {
					block_comment = true
					index += 2
					continue
				}
			}
			if ch == `"` || ch == `'` {
				quote = ch
				index++
				continue
			}
			if ch == `{` { depth++ }
			if ch == `}` {
				depth--
				if depth == 0 {
					index++
					break
				}
			}
			index++
		}
		if depth != 0 { return error('Unclosed generated fixture body') }
		body := raw[start..index]
		body_name(body)!
		bodies << body
		start = index
		if start < raw.len && raw[start] == `\n` { start++ }
	}
	return bodies
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
		symbol := body_name(body)!
		if symbol in ['compatcore__init_swait_queue_head', 'compatcore__complete',
			'compatcore__wait_for_completion'] {
			continue
		}
		matches := full.filter(hosttest.named_body(it, symbol))
		if matches.len != 1 || matches[0] != body {
			return error('Changed full-module production body or initialization guard: ' + symbol)
		}
		if symbol in identical { return error('Duplicate production proof symbol: ' + symbol) }
		identical[symbol] = hosttest.text_sha(body)
	}
	return map[string]json2.Any{
		'reference_c_sha256':         json2.Any(hosttest.sha(path)!)
		'byte_identical_body_count':  identical.len
		'byte_identical_body_sha256': hosttest.string_map(identical)
	}
}

fn fixture_allocation_check(raw string) !json2.Any {
	mut hashes := map[string]string{}
	mut occurrences := map[string]int{}
	bodies := fixture_bodies(raw)!
	for body in bodies {
		symbol := body_name(body)!
		for forbidden in ['memdup(', 'new_array_from', 'builtin__malloc', 'builtin___v_malloc',
			'string__substr', 'string__inter', '__eq(', '__ptr_eq_'] {
			if body.contains(forbidden) {
				return error('Hidden fixture boxing/allocation or deep pointer comparison: ' + symbol + ': ' + forbidden)
			}
		}
		occurrence := occurrences[symbol] + 1
		occurrences[symbol] = occurrence
		key := symbol + '#' + occurrence.str()
		if key in hashes { return error('Duplicate fixture proof body key: ' + key) }
		hashes[key] = hosttest.text_sha(body)
	}
	if hashes.len != bodies.len || hashes.len < 60 {
		return error('Incomplete actual fixture body allocation inspection')
	}
	mut occurrence_metadata := map[string]json2.Any{}
	for symbol, count in occurrences { occurrence_metadata[symbol] = json2.Any(count) }
	return map[string]json2.Any{
		'actual_body_count':            json2.Any(bodies.len)
		'unique_body_key_count':        hashes.len
		'distinct_identifier_count':    occurrences.len
		'identifier_occurrence_counts': occurrence_metadata
		'actual_body_sha256':           json2.Any(hosttest.string_map(hashes))
		'scope':                        json2.Any('All generated fixture bodies are inspected for implicit V boxing/array/string allocations and deep pointer equality. Explicit calloc/free only supplies low-level native task-context transport; real page-backed allocations go through the unchanged production allocator. No native kernel allocation measurement is claimed.')
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
	// No reservation, refcount or iterator scheduling algorithm is replaced.
	for directory in [os.join_path(work, 'include'), os.join_path(root, 'tests/linuxkpi/resvfixture'),
		os.join_path(root, 'tests/linuxkpi/freefixture'),
		os.join_path(root, 'tests/linuxkpi/rcucallfixture'),
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
	work := hosttest.work_dir(keep, 'vinix-dma-resv-')!
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
		os.join_path(root, 'tests/linuxkpi/rcucallfixture/rcucall_host_contract.h'),
		os.join_path(root, 'tests/linuxkpi/fencecontainerfixture/core.v')]
	observed << os.join_path(root, 'kernel/asm/x86_64/linuxkpi_storage.S')
	observed << os.join_path(root, 'tests/linuxkpi/resvfixture/README.md')
	observed << os.walk_ext(os.join_path(root, 'tests/linuxkpi/freefixture'), '.v')
	observed << os.walk_ext(os.join_path(root, 'tests/linuxkpi/freefixture'), '.h')
	observed << os.walk_ext(os.join_path(root, 'tests/linuxkpi/resvfixture'), '.v')
	observed << os.walk_ext(os.join_path(root, 'tests/linuxkpi/resvfixture'), '.h')
	observed << os.walk_ext(os.join_path(root, 'tests/linuxkpi/hosttest'), '.v')
	observed << os.walk_ext(os.join_path(root, 'kernel/linuxkpi/include'), '.h')
	for module_name in ['compatcore', 'headercore'] {
		observed << os.walk_ext(os.join_path(root, 'kernel/linuxkpi', module_name), '.v')
	}
	observed << os.walk_ext(os.join_path(root, 'kernel/c'), '.h')
	for name in ['linuxkpi_rcu_v_primitives.h', 'linuxkpi_rcu_v_contract.h',
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
			'#include "linuxkpi_dma_resv_v_contract.h"\n#include "linuxkpi_dma_fence_v_contract.h"\n#include "linuxkpi_dma_fence_array_v_contract.h"\n#include "linuxkpi_dma_fence_chain_v_contract.h"\n#include "linuxkpi_irq_work_v_contract.h"\n#include "linuxkpi_header_primitive_v_contract.h"\n#include "linuxkpi_rcu_v_contract.h"\n#include "linuxkpi_smp_masks_v_contract.h"\n' +
				'#include "linuxkpi_header_primitive_v_contract.h"\n' +
				'typedef struct cpumask cpumask;\n' +
				hosttest.scalar_metadata(os.join_path(stage, name), '')!
		} else {
			'#include "linuxkpi_dma_resv_v_primitives.h"\n#include "linuxkpi_wait_v_primitives.h"\n#include "linuxkpi_dma_fence_v_primitives.h"\n#include "linuxkpi_dma_fence_array_v_primitives.h"\n#include "linuxkpi_dma_fence_chain_v_primitives.h"\n#include "linuxkpi_irq_work_v_primitives.h"\n#include "linuxkpi_task_v_primitives.h"\n#include "linuxkpi_rcu_v_primitives.h"\n#include "linuxkpi_smp_masks_v_primitives.h"\n' +
				'void msleep(unsigned int); void rcuh_completion_init(void *); void rcuh_completion_complete(void *); void rcuh_completion_wait(void *);\n#include <string.h>\n#include <stdio.h>\n#define _printk(f,a,b,c,d) printf((f),(const char *)(a),(const char *)(b),(unsigned long long)(uintptr_t)(c),(unsigned long long)(uintptr_t)(d))\nvoid *vinix_linuxkpi_alloc_pages(size_t,bool);\nvoid *rsh_load_ptr_gate(void **);\n#undef vdr_load_ptr\n#define vdr_load_ptr(p) rsh_load_ptr_gate((void **)(p))\n'
		}
		prefixes := if name == 'headercore' {
			['headercore__vdf_', 'headercore__vfa_', 'headercore__vfc_', 'dma_fence_array_ops',
				'dma_fence_chain_ops', 'reservation_ww_class', 'cpu_bit_bitmap', 'cpu_all_bits',
				'__cpu_', '__num_online_cpus', 'nr_cpu_ids']
		} else {
			['compatcore__']
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
	fixture_source := os.join_path(work, 'resvfixture')
	stage_fixture(fixture_source)!
	hosttest.generate_module(fixture_source, os.join_path(work, 'fixture.c'), 'amd64', ['nofloat'])!
	fixture_allocations := fixture_allocation_check(os.read_file(os.join_path(work, 'fixture.c'))!)!
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
		storage := os.join_path(work, standard + '-storage.o')
		mut storage_flags := compiler.clone()
		$if macos {
			storage_flags << ['-arch', 'x86_64']
		}
		command([...storage_flags, '-DVINIX_LINUXKPI', '-c',
			os.join_path(root, 'kernel/asm/x86_64/linuxkpi_storage.S'), '-o', storage], os.join_path(work, standard + '-storage.log'), env)!
		objects << storage
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
		'completion_transport_adapters':  hosttest.strings(['init_swait_queue_head', 'complete',
			'wait_for_completion'])
		'ordering_scope':                 json2.Any('Acquire/release transport witnesses and authentic generated full-fence bodies; this host matrix is not an independent relaxed payload publication litmus. Actual native full-fence object and IRQ-return evidence are required separately.')
		'ownership_scope':                json2.Any('Real tagged page-backed callback/fence allocations and actual ordinary RCU default frees. Native page, task-retention and CPU observations are transport only; cache algorithms are linked production bodies but this focused suite makes no cache-ownership coverage claim.')
		'scheduler_scope':                json2.Any('Actual unchanged task state/wake/schedule and deadline/schedule_timeout bodies execute. Independent native enqueue/dequeue/park-by-yield, signal observation and explicit clock tick transport provide the boundary. No fence wait algorithm is modeled.')
		'reservation_matrix':             hosttest.strings([
			'Original mutable WD class, owner/trylock/EALREADY, blocked handoff, interruptible cancellation and two-object EDEADLK/slow recovery',
			'Usage tags0..3, original usage_rw, exact requested list capacity, reserve fit/grow/prune/overflow/OOM, add promotion/nondegradation/signaled reuse and replace-all references',
			'Locked borrowed including signaled fences; unlocked retained references and filtering; empty restart drops and clears current owner',
			'Real oldcount4 -> empty copy -> RCU barrier -> same physical page/newcount1 restart; ordinary in-place append preserves cached snapshot',
			'Two-actor old tagged entry loaded under real RCU; writer drops last fence reference; original get-unless-zero rejects zero and restarts; no free until reader scope ends',
			'Copy/self-copy/get/singleton0/1/ALL ownership and vector/list/array OOM cleanup, including partial copy/get mutation restart success/OOM and preserved weak prefixes after empty restart',
			'Actual empty/filtered/zero/finite-budget/interrupted/custom-result waits, deadlines and test-signaled early-reference cleanup',
			'Exact kmalloc_size_roundup boundaries; krealloc_array overflow/OOM preservation, NULL/16/zero products, new grow/shrink requested-size owners and preserved bytes',
			'Six explicit invalid-call controls preserve original object, fence, list storage and allocator count before abort',
		])
		'reservation_transport':          json2.Any('The sole reservation pointer-load macro adapter executes the same acquire __atomic_load_n, optionally pauses one selected actor after that load, and returns the untouched observed pointer bits. Actual RCU, zero-ref acquisition and retry determine all references. Producer signaled callbacks may pause as host debugging gates while the actual RCU/preemption scope remains live. Physical page transport can return OOM at one ordinal or retain one actually freed one-page span and return it to the next allocation; the production tagged allocator reconstructs its owner metadata. No reservation/list/cursor/refcount/lock/wait/rollback/grace-period state is fabricated or rewritten.')
		'console_transport':              json2.Any('A metadata-only adapter maps the original five-argument pending-release diagnostic to host printf while preserving argument evaluation. The actual name hooks, warning condition, -EDEADLK signal and callback/release ordering execute unchanged.')
		'fixture_allocation_inspection':  fixture_allocations
		'actual_generated_body_proofs':   proofs
		'runs':                           results
		'compiler':                       tools
		'object_and_native_input_proofs': inputs
		'upstream_pin':                   pin
		'fixture_c_sha256':               hosttest.sha(os.join_path(work, 'fixture.c'))!
	})!
	println('LinuxKPI DMA reservation: actual V reservation/WW/fence/array/IRQ/task/time/allocator/RCU bodies, original records, strict GNU99/GNU11 and host ASan/UBSan passed')
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-directory'], 'Usage: dma_resv.v [--keep-directory DIRECTORY]', scope) or {
		eprintln(err)
		exit(2)
	}
	run_profile(options['--keep-directory']) or {
		eprintln(err)
		exit(1)
	}
}
