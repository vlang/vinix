// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftTaskPair { task u64 context u64 }
// Private storage is owned by Vinix. The measured public job header occupies
// 80 bytes; the complete task header is 176 bytes. No per-task V box or map.
struct SwiftTaskState {
mut:
	previous u64
	next u64
	alloc_top u64
	alloc_count u64
	total u64
	flags u64 // Creation flags, with effective priority in the upper word.
	phase u64 // 0 created, 1 queued, 2 running, 3 complete, 4 completing.
	metadata u64
	size u64
	mask u64
	name u64
	name_size u64
}
struct SwiftTaskLayout { total u64 context u64 result u64 fragment u64 size u64 mask u64 name u64 name_size u64 named bool }
type SwiftTaskInvoke = fn (u64, u64)
type SwiftTaskValueDestroy = fn (u64, u64)

fn swift_task_find_locked(owner u64) u64 {
	mut node := ios_runtime.swift_tasks
	for node != 0 {
		if node == owner { return node }
		node = unsafe { (&SwiftTaskState(node + 80)).next }
	}
	return 0
}
fn swift_task_registered(owner u64) bool {
	if ios_runtime == unsafe { nil } { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return swift_task_find_locked(owner) != 0
}
fn swift_task_current() u64 {
	if ios_runtime == unsafe { nil } || !ios_runtime.swift_task_key_live { return 0 }
	return u64(C.pthread_getspecific(ios_runtime.swift_task_key))
}
fn swift_task_sync_condition() voidptr {
	return unsafe { voidptr(ios_runtime.swift_task_sync + u64(C.ios_sizeof_mutex())) }
}
fn swift_task_job_count(delta i64) {
	mutex := unsafe { voidptr(ios_runtime.swift_task_sync) }
	C.pthread_mutex_lock(mutex)
	if delta > 0 { ios_runtime.swift_task_jobs++ }
	else {
		if ios_runtime.swift_task_jobs == 0 { panic('iOS: Swift task callback count underflow') }
		ios_runtime.swift_task_jobs--
		C.pthread_cond_broadcast(swift_task_sync_condition())
	}
	C.pthread_mutex_unlock(mutex)
}
fn swift_tasks_join() {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_task_sync == 0 { return }
	mutex := unsafe { voidptr(ios_runtime.swift_task_sync) }
	C.pthread_mutex_lock(mutex)
	for ios_runtime.swift_task_jobs != 0 {
		// Only Swift main jobs require a main-thread turn. Do not run unrelated
		// main blocks merely because generic Swift workers are being joined.
		if ios_runtime.swift_task_main_jobs != 0 && u64(C.pthread_self()) == ios_runtime.main_thread {
			C.pthread_mutex_unlock(mutex)
			ran := dispatch_main_drain()
			C.pthread_mutex_lock(mutex)
			if ios_runtime.swift_task_jobs == 0 { break }
			if ran { continue }
		}
		if C.pthread_cond_wait(swift_task_sync_condition(), mutex) != 0 { panic('iOS: cannot join Swift tasks') }
	}
	C.pthread_mutex_unlock(mutex)
}

fn swift_task_emit(code u64, metadata u64) {
	// Swift async adapters borrow context in x22, closure in x20, error in x21.
	for i, instruction in [u32(0xd2800000), 0xf85f02d4, 0xf85e82d0, 0xd61f0200]! { write32(code + u64(i * 4), instruction) }
	// Future: x0 is the indirect result, both variants load entry at context-24.
	for i, instruction in [u32(0xf85e02c0), 0xf85f02d4, 0xf85e82d0, 0xd61f0200]! { write32(code + 32 + u64(i * 4), instruction) }
	// Completion's second Swift-context parameter is x20, rather than x21.
	for i, instruction in [u32(0xaa1603e0), 0xaa1403e1, 0x58000050, 0xd61f0200]! { write32(code + 64 + u64(i * 4), instruction) }
	unsafe { *(&u64(code + 80)) = u64(voidptr(swift_task_complete)) }
	// Ordinary C (entry, context) -> Swift async; restore all borrowed registers.
	for i, instruction in [u32(0xa9bd7bf4), 0xa9015bf5, 0xf90013fe, 0xaa0003f0,
		0xaa0103f6, 0xd2800014, 0xd2800015, 0xd63f0200, 0xf94013fe,
		0xa9415bf5, 0xa8c37bf4, 0xd65f03c0]! { write32(code + 96 + u64(i * 4), instruction) }
	// A meaningful heap destroyer; swift_release normally takes our registry path.
	write32(code + 160, 0xaa1403e0); write32(code + 164, 0x58000070); write32(code + 168, 0xd61f0200)
	unsafe { *(&u64(code + 176)) = u64(voidptr(swift_task_destroy)) }
	// Async switch (context x22, continuation x0, executor x1/x2) -> ordinary
	// validation -> tail continuation. Pop the frame before resuming; completion
	// may free the task and nested switches must not grow the C stack.
	for i, instruction in [u32(0xa9bf7bfd), 0xaa0203e3, 0xaa0103e2, 0xaa0003e1,
		0xaa1603e0, 0x580000b0, 0xd63f0200, 0xa8c17bfd, 0xd61f0000]! {
		write32(code + 192 + u64(i * 4), instruction)
	}
	unsafe { *(&u64(code + 232)) = u64(voidptr(swift_task_switch_prepare)) }
	unsafe {
		*(&u64(metadata - 24)) = 0
		*(&u64(metadata - 16)) = code + 160
		*(&u64(metadata - 8)) = 0
		*(&u64(metadata)) = 0x502
		*(&u64(metadata + 8)) = 1
		*(&u64(metadata + 16)) = u64(voidptr(swift_task_dispatch))
	}
}

fn swift_task_arena() !u64 {
	if ios_runtime.swift_task_arena != 0 { return ios_runtime.swift_task_arena }
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if code == unsafe { voidptr(-1) } { return error('iOS: cannot allocate Swift task entries') }
	base := u64(code)
	swift_task_emit(base, base + u64(page) + 32)
	C.__builtin___clear_cache(code, unsafe { voidptr(base + 240) })
	if C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(unsafe { voidptr(base + u64(page)) }, page, C.PROT_READ) != 0 {
		C.munmap(code, page * 2)
		return error('iOS: cannot seal Swift task entries')
	}
	sync := C.calloc(1, usize(C.ios_sizeof_mutex() + C.ios_sizeof_cond()))
	if sync == unsafe { nil } { C.munmap(code, page * 2); return error('iOS: cannot allocate Swift task synchronization') }
	if C.ios_mutex_create(sync, 0) != 0 { C.free(sync); C.munmap(code, page * 2); return error('iOS: cannot initialize Swift task mutex') }
	condition := unsafe { voidptr(u64(sync) + u64(C.ios_sizeof_mutex())) }
	if C.pthread_cond_init(condition, unsafe { nil }) != 0 {
		C.pthread_mutex_destroy(sync); C.free(sync); C.munmap(code, page * 2)
		return error('iOS: cannot initialize Swift task condition')
	}
	if C.ios_key_create(unsafe { &ios_runtime.swift_task_key }, unsafe { nil }) != 0 {
		C.pthread_cond_destroy(condition); C.pthread_mutex_destroy(sync); C.free(sync); C.munmap(code, page * 2)
		return error('iOS: cannot initialize Swift current task TLS')
	}
	ios_runtime.swift_task_sync = u64(sync)
	ios_runtime.swift_task_key_live = true
	ios_runtime.swift_task_arena = base
	return base
}

fn swift_task_layout(flags u64, options u64, metadata u64, descriptor u64) !SwiftTaskLayout {
	if flags & ~u64(0xdcff) != 0 { return error('iOS: structured, inline and immediate Swift tasks are not implemented') }
	if descriptor < 8 || descriptor & 3 != 0 || descriptor > 0x0000fffffffffff7 {
		return error('iOS: invalid Swift async descriptor')
	}
	size := u64(read32(descriptor + 4))
	if size < 16 || size & 15 != 0 { return error('iOS: invalid Swift initial context size') }
	mut named := false
	mut name := u64(0)
	mut option := options
	mut seen := [64]u64{}
	mut count := 0
	for option != 0 {
		if option < 8 || option & 7 != 0 || count == 64 { return error('iOS: invalid Swift task option chain') }
		for i in 0 .. count { if seen[i] == option { return error('iOS: cyclic Swift task option chain') } }
		seen[count] = option; count++
		kind := read32(option)
		if kind == 7 { named = true; name = read64(option + 16) }
		else if kind == 0 {
			if read64(option + 16) != 0 || read64(option + 24) != 0 { return error('iOS: custom Swift executors are not implemented') }
		} else { return error('iOS: Swift task option is not implemented') }
		option = read64(option + 8)
	}
	name_size := if name != 0 { u64(darwin_strlen(unsafe { &char(name) })) } else { u64(0) }
	fragment := u64(176) + if named { u64(16) } else { u64(0) }
	mut result := u64(0)
	mut result_size := u64(0)
	mut mask := u64(0)
	mut end := fragment
	if metadata != 0 {
		if metadata < 8 || metadata & 7 != 0 { return error('iOS: invalid Swift future metadata') }
		witness := read64(metadata - 8)
		if witness == 0 { return error('iOS: Swift future needs value witnesses') }
		result_size = read64(witness + 64)
		mask = u64(read32(witness + 80) & 255)
		if mask > 15 || (mask + 1) & mask != 0 || read32(witness + 80) & 0x400000 != 0 || read64(witness + 8) == 0 {
			return error('iOS: invalid Swift future value layout')
		}
		result = (fragment + 24 + mask) & ~mask
		if result_size > 0x7fffffffffffffff - result - 48 - size { return error('iOS: Swift future allocation size overflow') }
		end = result + result_size
	}
	prefix := if metadata == 0 { u64(24) } else { u64(32) }
	context := (end + prefix + 15) & ~u64(15)
	return SwiftTaskLayout{ total: context + size, context: context, result: result,
		fragment: fragment, size: result_size, mask: mask, name: name, name_size: name_size, named: named }
}

fn swift_task_create_checked(flags u64, options u64, metadata u64, descriptor u64, closure u64) !SwiftTaskPair {
	$if !arm64 { return error('iOS: Swift task creation requires ARM64') }
	if ios_runtime == unsafe { nil } { return error('iOS: Swift task creation outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_concurrency_retired { return error('iOS: Swift task creation outside runtime lifetime') }
	if flags & 0x1000 != 0 {
		if dispatch_runtime == unsafe { nil } { return error('iOS: Swift task enqueue without dispatch runtime') }
		C.pthread_mutex_lock(dispatch_runtime.mutex)
		stopping := dispatch_runtime.stopping
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		if stopping { return error('iOS: Swift task enqueue during dispatch shutdown') }
	}
	layout := swift_task_layout(flags, options, metadata, descriptor)!
	if closure != 0 && flags & 0x8000 == 0 { swift_buffer_refs(closure, 0)! }
	delta := i64(i32(read32(descriptor)))
	entry := if delta < 0 { descriptor - u64(-delta) } else { descriptor + u64(delta) }
	if entry < 8 || entry & 3 != 0 || entry > 0x0000ffffffffffff { return error('iOS: invalid Swift async entry') }
	current := swift_task_current()
	if current != 0 && swift_task_find_locked(current) == 0 { return error('iOS: unregistered current Swift task') }
	mut priority := flags & 255
	if priority == 0 {
		if current != 0 && flags & 0xc00 != 0 { priority = unsafe { ((&SwiftTaskState(current + 80)).flags >> 32) & 255 } }
		if priority == 0 { priority = 21 }
		if priority == 33 && flags & 0xc00 != 0 { priority = 25 }
	}
	code := swift_task_arena()!
	if ios_runtime.swift_task_count == u64(-1) { return error('iOS: Swift task count overflow') }
	pointer := unsafe { &u64(C.__builtin_alloca(8)) }
	unsafe { *pointer = 0 }
	if C.posix_memalign(unsafe { voidptr(pointer) }, 16, usize(layout.total)) != 0 { return error('iOS: cannot allocate Swift task') }
	owner := unsafe { *pointer }
	context := owner + layout.context
	queued := flags & 0x1000 != 0
	job_flags := (if metadata != 0 { u64(1) << 25 } else { u64(0) })
		| (if layout.named { u64(1) << 30 } else { u64(0) }) | if queued { priority << 8 } else { u64(0) }
	ios_runtime.swift_task_sequence++
	if ios_runtime.swift_task_sequence == 0 { ios_runtime.swift_task_sequence++ }
	unsafe {
		*(&u64(owner)) = code + u64(C.getpagesize()) + 32
		*(&u64(owner + 8)) = if queued { u64(0x200000003) } else { u64(3) }
		*(&u64(owner + 16)) = 0; *(&u64(owner + 24)) = 0
		*(&u64(owner + 32)) = job_flags | u64(ios_runtime.swift_task_sequence) << 32
		*(&u64(owner + 40)) = 0; *(&u64(owner + 48)) = 0
		*(&u64(owner + 56)) = code + if metadata != 0 && flags & 0x4000 == 0 { u64(32) } else { u64(0) }
		*(&u64(owner + 64)) = context; *(&u64(owner + 72)) = 0
		*(&SwiftTaskState(owner + 80)) = SwiftTaskState{ next: ios_runtime.swift_tasks, total: layout.total,
			flags: flags | priority << 32, phase: if queued { u64(1) } else { u64(0) }, metadata: metadata,
			size: layout.size, mask: layout.mask, name_size: layout.name_size }
		*(&u64(context - 24)) = entry; *(&u64(context - 16)) = closure; *(&u64(context - 8)) = 0
		*(&u64(context)) = 0; *(&u64(context + 8)) = code + 64
		if metadata != 0 {
			*(&u64(owner + layout.fragment)) = 0
			*(&u64(owner + layout.fragment + 8)) = metadata
			*(&u64(owner + layout.fragment + 16)) = 0
			*(&u64(context - 32)) = owner + layout.result
		}
	}
	mut state := unsafe { &SwiftTaskState(owner + 80) }
	if layout.named {
		if layout.name != 0 {
			name := swift_task_allocate_in_locked(state, layout.name_size + 1) or { C.free(unsafe { voidptr(owner) }); return err }
			C.memcpy(unsafe { voidptr(name) }, unsafe { voidptr(layout.name) }, usize(layout.name_size + 1))
			state.name = name
		}
		unsafe { *(&u64(owner + 176)) = state.name; *(&u64(owner + 184)) = layout.name_size }
	}
	if ios_runtime.swift_tasks != 0 { unsafe { (&SwiftTaskState(ios_runtime.swift_tasks + 80)).previous = owner } }
	ios_runtime.swift_tasks = owner
	ios_runtime.swift_task_count++
	if queued {
		swift_task_job_count(1)
		// No runtime lock across dispatch submission or application execution.
		C.ios_objc_initialize_unlock()
		queue := darwin_dispatch_get_global_queue(i64(priority), 0)
		dispatch_submit(if queue == 0 { darwin_dispatch_get_global_queue(21, 0) } else { queue }, 0, 0,
			unsafe { voidptr(owner) }, swift_task_dispatch)
		C.ios_objc_initialize_lock()
	}
	return SwiftTaskPair{ task: owner, context: context }
}
fn swift_task_create(flags u64, options u64, metadata u64, descriptor u64, closure u64) SwiftTaskPair {
	return swift_task_create_checked(flags, options, metadata, descriptor, closure) or { panic(err) }
}

fn swift_task_run_checked(owner u64, identity u64, implementation u64) ! {
	if ios_runtime == unsafe { nil } { return error('iOS: Swift task execution outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	on_main := swift_main_executor_matches_locked(identity,implementation)
	if (!on_main && (identity != 0 || implementation != 0))
		|| (on_main && u64(C.pthread_self()) != ios_runtime.main_thread) {
		C.ios_objc_initialize_unlock(); return error('iOS: invalid Swift executor or main job outside main thread')
	}
	if ios_runtime.swift_concurrency_retired || swift_task_find_locked(owner) == 0 {
		C.ios_objc_initialize_unlock(); return error('iOS: unregistered Swift task execution')
	}
	mut state := unsafe { &SwiftTaskState(owner + 80) }
	if state.phase > 1 { C.ios_objc_initialize_unlock(); return error('iOS: Swift task already started') }
	queued_main := state.phase == 1 && state.flags & swift_task_on_main != 0
	if state.phase == 1 && queued_main != on_main {
		C.ios_objc_initialize_unlock(); return error('iOS: Swift queued job executor mismatch')
	}
	if state.phase == 0 { swift_task_job_count(1) }
	if on_main { state.flags |= swift_task_on_main }
	state.phase = 2
	context := read64(owner + 64)
	entry := read64(owner + 56)
	previous := swift_task_current()
	if C.pthread_setspecific(ios_runtime.swift_task_key, unsafe { voidptr(owner) }) != 0 { panic('iOS: cannot install current Swift task') }
	call := unsafe { SwiftTaskInvoke(voidptr(ios_runtime.swift_task_arena + 96)) }
	C.ios_objc_initialize_unlock()
	call(entry, context)
	// Completion may have released the last reference and freed owner/context.
	unfinished := swift_task_current() != 0
	if C.pthread_setspecific(ios_runtime.swift_task_key, unsafe { voidptr(previous) }) != 0 { panic('iOS: cannot restore current Swift task') }
	if queued_main { swift_task_main_job_count(-1) } else { swift_task_job_count(-1) }
	if unfinished { return error('iOS: Swift task returned without completion; suspension is not implemented') }
}
fn swift_task_run(owner u64, identity u64, implementation u64) { swift_task_run_checked(owner, identity, implementation) or { panic(err) } }
fn swift_task_dispatch(argument voidptr) { swift_task_run(u64(argument), 0, 0) }

fn swift_task_complete_checked(context u64, error_value u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return error('iOS: Swift task completion outside runtime lifetime') }
	owner := swift_task_current()
	C.ios_objc_initialize_lock()
	if owner == 0 || swift_task_find_locked(owner) == 0 { C.ios_objc_initialize_unlock(); return error('iOS: Swift completion without current task') }
	mut state := unsafe { &SwiftTaskState(owner + 80) }
	if state.phase != 2 || context != read64(owner + 64) { C.ios_objc_initialize_unlock(); return error('iOS: invalid Swift task completion context') }
	if error_value != 0 {
		header := ios_runtime.objects[error_value] or { C.ios_objc_initialize_unlock(); return error('iOS: Swift task error requires a live CFError') }
		if state.metadata == 0 || header.cls != cf_error_type_id() || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
			C.ios_objc_initialize_unlock(); return error('iOS: Swift task error supports owned CFError; native boxes are not implemented')
		}
	}
	state.phase = 4
	closure := if state.flags & 0x8000 == 0 { read64(context - 16) } else { u64(0) }
	C.ios_objc_initialize_unlock()
	if closure != 0 { swift_release(closure) }
	C.ios_objc_initialize_lock()
	if state.metadata != 0 {
		fragment := owner + 176 + if read32(owner + 32) & (u32(1) << 30) != 0 { u64(16) } else { u64(0) }
		unsafe { *(&u64(fragment + 16)) = error_value; *(&u64(fragment)) = if error_value == 0 { u64(1) } else { u64(2) } }
	}
	unsafe { *(&u64(context - 8)) = error_value }
	state.phase = 3
	if C.pthread_setspecific(ios_runtime.swift_task_key, unsafe { nil }) != 0 { panic('iOS: cannot clear current Swift task') }
	C.ios_objc_initialize_unlock()
	swift_task_refs(owner, -1)!
}
fn swift_task_complete(context u64, error_value u64) { swift_task_complete_checked(context, error_value) or { panic(err) } }

fn swift_task_refs(owner u64, delta i64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return error('iOS: Swift task ARC outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	if swift_task_find_locked(owner) == 0 { C.ios_objc_initialize_unlock(); return error('iOS: unregistered Swift task ARC') }
	bits := read64(owner + 8)
	if bits & 0x80000001ffffffff != 3 { C.ios_objc_initialize_unlock(); return error('iOS: invalid Swift task reference state') }
	refs := (bits >> 33) + 1
	if (delta > 0 && u64(delta) > swift_strong_limit - refs) || (delta < 0 && u64(-(delta + 1)) + 1 > refs) {
		C.ios_objc_initialize_unlock(); return error('iOS: Swift task reference overflow or underflow')
	}
	updated := u64(i64(refs) + delta)
	if updated == 0 && unsafe { (&SwiftTaskState(owner + 80)).phase } != 3 {
		C.ios_objc_initialize_unlock(); return error('iOS: Swift task cannot be destroyed before completion')
	}
	unsafe { *(&u64(owner + 8)) = if updated == 0 { u64(0x100000003) } else { u64(3) | (updated - 1) << 33 } }
	C.ios_objc_initialize_unlock()
	if updated == 0 { swift_task_destroy(owner) }
	return updated
}
fn swift_task_destroy(owner u64) {
	C.ios_objc_initialize_lock()
	if swift_task_find_locked(owner) == 0 || read64(owner + 8) != 0x100000003 { panic('iOS: invalid Swift task destruction') }
	state := unsafe { *(&SwiftTaskState(owner + 80)) }
	if state.phase != 3 { panic('iOS: Swift task destruction before completion') }
	if state.previous != 0 { unsafe { (&SwiftTaskState(state.previous + 80)).next = state.next } }
	else { ios_runtime.swift_tasks = state.next }
	if state.next != 0 { unsafe { (&SwiftTaskState(state.next + 80)).previous = state.previous } }
	ios_runtime.swift_task_count--
	ios_runtime.swift_task_disposing++
	context := read64(owner + 64)
	error_value := read64(context - 8)
	C.ios_objc_initialize_unlock()
	if state.metadata != 0 {
		if error_value != 0 { objc_release(error_value) }
		else {
			witness := read64(state.metadata - 8)
			destroy := unsafe { SwiftTaskValueDestroy(voidptr(read64(witness + 8))) }
			destroy(read64(context - 32), state.metadata)
		}
	}
	// Task-private allocations (including its name) die with the task, even
	// when the body left temporary allocations for allocator destruction.
	mut node := state.alloc_top
	for node != 0 { previous := read64(node); C.free(unsafe { voidptr(node) }); node = previous }
	C.free(unsafe { voidptr(owner) })
	C.ios_objc_initialize_lock()
	ios_runtime.swift_task_disposing--
	C.ios_objc_initialize_unlock()
}
fn swift_tasks_drain_checked() ! {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut jobs := u64(0)
	mut main_jobs := u64(0)
	if ios_runtime.swift_task_sync != 0 {
		mutex := unsafe { voidptr(ios_runtime.swift_task_sync) }
		C.pthread_mutex_lock(mutex); jobs = ios_runtime.swift_task_jobs; main_jobs = ios_runtime.swift_task_main_jobs; C.pthread_mutex_unlock(mutex)
	}
	if ios_runtime.swift_tasks != 0 || ios_runtime.swift_task_count != 0 || ios_runtime.swift_task_disposing != 0
		|| swift_task_current() != 0 || jobs != 0 || main_jobs != 0 { return error('iOS: Swift tasks have not drained') }
}
fn swift_tasks_stop() {
	swift_tasks_drain_checked() or { panic(err) }
	if ios_runtime.swift_task_arena == 0 { return }
	if C.pthread_key_delete(ios_runtime.swift_task_key) != 0 { panic('iOS: cannot retire Swift task TLS') }
	ios_runtime.swift_task_key_live = false
	if C.pthread_cond_destroy(swift_task_sync_condition()) != 0 { panic('iOS: cannot retire Swift task condition') }
	if C.pthread_mutex_destroy(unsafe { voidptr(ios_runtime.swift_task_sync) }) != 0 { panic('iOS: cannot retire Swift task mutex') }
	C.free(unsafe { voidptr(ios_runtime.swift_task_sync) })
	ios_runtime.swift_task_sync = 0
	if C.munmap(unsafe { voidptr(ios_runtime.swift_task_arena) }, usize(C.getpagesize()) * 2) != 0 { panic('iOS: cannot retire Swift task entries') }
	ios_runtime.swift_task_arena = 0
}
fn swift_task_create_symbol(symbol string) !u64 {
	$if !arm64 { return error('iOS: Swift task creation requires ARM64') }
	if ios_runtime == unsafe { nil } { return error('iOS: Swift task creation outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_concurrency_retired { return error('iOS: Swift task creation outside runtime lifetime') }
	return match symbol {
		'_swift_task_create' { u64(voidptr(swift_task_create)) }
		'_swift_task_getCurrent' { u64(voidptr(swift_task_current)) }
		'_swift_job_run' { u64(voidptr(swift_task_run)) }
		'_swift_task_switch' { swift_task_arena()! + 192 }
		else { return error('iOS: Swift task creation symbol is not implemented') }
	}
}
