// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftExecutorPair { identity u64 implementation u64 }
const swift_task_on_main = u64(1) << 63

// All descriptors are private, unconditional, nongeneric Swift records. The
// measured Actor table has one getter; SerialExecutor inherits Executor and
// has three enqueue entries, asUnowned, equality and two isolation entries.
// No PAC signatures are needed for Vinix's ordinary ARM64 function pointers.
fn swift_main_executor_emit(code u64,data u64,module_descriptor u64) {
	actor := data + 256
	metadata := data + 664
	nominal := data + 768
	owner := data + 896
	executor := data + 960
	serial := data + 1040
	for descriptor in [actor,executor,serial]! {
		write32(descriptor,0x20043)
		swift_protocol_relative(descriptor + 4,module_descriptor)
		write32(descriptor + 12,1)
		swift_protocol_relative(descriptor + 28,data + 384) // Self.
	}
	C.memcpy(voidptr(data + 352),c'Actor',6)
	C.memcpy(voidptr(data + 384),c'x',2)
	C.memcpy(voidptr(data + 1376),c'Executor',9)
	C.memcpy(voidptr(data + 1392),c'SerialExecutor',15)
	swift_protocol_relative(actor + 8,data + 352)
	write32(actor + 16,1); write32(actor + 24,0x1f) // Self: AnyObject.
	write32(actor + 36,0x69760013) // Instance getter, native discriminator.
	swift_protocol_relative(executor + 8,data + 1376)
	write32(executor + 16,3); write32(executor + 24,0x1f)
	for i,flags in [u32(0x78480011),0xaa8e0011,0x56ba0011]! { write32(executor + 36 + u64(i * 8),flags) }
	swift_protocol_relative(serial + 8,data + 1392)
	write32(serial + 16,8); write32(serial + 24,0x80) // Self: Executor.
	swift_protocol_relative(serial + 32,executor)
	for i,flags in [u32(0),0x5e960011,0xf99f0011,0x8c540011,0x08e30011,0xffbd0011,0xfd3c0011,0x79c80011]! {
		write32(serial + 36 + u64(i * 8),flags)
	}
	// Unlike the native library's evolving default witnesses, these complete
	// private tables supply every requirement explicitly.
	for descriptor in [data + 400,data + 1152,data + 1168]! {
		swift_protocol_relative(descriptor + 4,if descriptor == data + 400 { data + 128 } else { nominal })
	}
	swift_protocol_relative(data + 400,actor)
	swift_protocol_relative(data + 408,data + 432)
	swift_protocol_relative(data + 1152,executor)
	swift_protocol_relative(data + 1160,data + 1280)
	swift_protocol_relative(data + 1168,serial)
	swift_protocol_relative(data + 1176,data + 1200)
	unsafe {
		*(&u64(data + 432)) = data + 400
		*(&u64(data + 440)) = code + 128
		*(&u64(data + 1200)) = data + 1168
		*(&u64(data + 1208)) = data + 1280
		*(&u64(data + 1240)) = code + 288
		*(&u64(data + 1248)) = code + 192
		*(&u64(data + 1256)) = code + 224
		*(&u64(data + 1264)) = code + 256
		*(&u64(data + 1280)) = data + 1152
	}
	for i in 0 .. 3 {
		unsafe { *(&u64(data + 1216 + u64(i * 8))) = code + 160
			*(&u64(data + 1288 + u64(i * 8))) = code + 160 }
	}
	// A known final executor object, with native ARC and the measured threaded
	// boolean at offset 16 (false for the main-thread dispatch executor). Its
	// private metadata is separate from MainActor's type.
	unsafe {
		*(&u64(metadata - 16)) = code + 96
		*(&u64(metadata - 8)) = read64(data + 16)
		*(&u64(metadata + 32)) = 2; *(&u64(metadata + 40)) = 2
		*(&u64(metadata + 48)) = 0x700000011
		*(&u64(metadata + 56)) = 0x1800000070
		*(&u64(metadata + 64)) = nominal
		*(&u64(metadata + 80)) = 16
		*(&u64(owner)) = metadata
		*(&u64(owner + 8)) = swift_main_actor_immortal
		*(&u8(owner + 16)) = 0
	}
	write32(nominal,0x50)
	swift_protocol_relative(nominal + 4,module_descriptor)
	swift_protocol_relative(nominal + 8,data + 832)
	write32(nominal + 24,3); write32(nominal + 28,11)
	write32(nominal + 32,1); write32(nominal + 36,1); write32(nominal + 40,10)
	C.memcpy(voidptr(data + 832),c'VinixMainExecutor',18)
	for i,instruction in [u32(0xaa1403e0),0xd2800221,0xd28000e2,0x58000070,0xd61f0200]! {
		write32(code + 96 + u64(i * 4),instruction)
	}
	unsafe { *(&u64(code + 120)) = u64(voidptr(swift_heap_deallocate)) }
	write32(code + 128,0x58000080); write32(code + 132,0x580000a1); write32(code + 136,0xd65f03c0)
	unsafe { *(&u64(code + 144)) = owner; *(&u64(code + 152)) = data + 1200 }
	write32(code + 160,0xaa1403e3); write32(code + 164,0x58000070); write32(code + 168,0xd61f0200)
	unsafe { *(&u64(code + 176)) = u64(voidptr(swift_main_executor_enqueue)) }
	write32(code + 192,0xeb14001f); write32(code + 196,0x1a9f17e0); write32(code + 200,0xd65f03c0)
	write32(code + 224,0x58000090); write32(code + 228,0xd61f0200)
	unsafe { *(&u64(code + 240)) = u64(voidptr(swift_main_executor_check_isolated)) }
	write32(code + 256,0x52800040); write32(code + 260,0xd65f03c0) // Optional<Bool>.none.
	write32(code + 288,0xaa1403e0); write32(code + 292,0x58000061); write32(code + 296,0xd65f03c0)
	unsafe { *(&u64(code + 304)) = data + 1200 } // Borrow Self, unlike MainActor's getter.
}

fn swift_main_executor_is_singleton_locked(owner u64) bool {
	base := ios_runtime.swift_main_actor_arena
	return base != 0 && !ios_runtime.swift_main_actor_retired
		&& owner == base + u64(C.getpagesize()) + 896
}
fn swift_main_executor_matches_locked(identity u64,implementation u64) bool {
	return swift_main_executor_is_singleton_locked(identity)
		&& implementation == ios_runtime.swift_main_actor_arena + u64(C.getpagesize()) + 1200
}
fn swift_main_executor_is_main(identity u64,implementation u64) bool {
	if ios_runtime == unsafe { nil } { return false }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	return swift_main_executor_matches_locked(identity,implementation)
}
fn swift_main_executor_check_isolated_checked() ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_main_actor_retired
		|| u64(C.pthread_self()) != ios_runtime.main_thread {
		return error('iOS: main executor isolation requires the main thread')
	}
}
fn swift_main_executor_check_isolated() { swift_main_executor_check_isolated_checked() or { panic(err) } }

fn swift_task_main_job_count(delta i64) {
	mutex := voidptr(ios_runtime.swift_task_sync)
	C.pthread_mutex_lock(mutex)
	if delta > 0 { ios_runtime.swift_task_jobs++; ios_runtime.swift_task_main_jobs++ }
	else {
		if ios_runtime.swift_task_jobs == 0 || ios_runtime.swift_task_main_jobs == 0 { panic('iOS: main Swift task callback count underflow') }
		ios_runtime.swift_task_jobs--; ios_runtime.swift_task_main_jobs--
		C.pthread_cond_broadcast(swift_task_sync_condition())
	}
	C.pthread_mutex_unlock(mutex)
}
fn swift_task_enqueue_main_checked(owner u64) ! {
	if ios_runtime == unsafe { nil } || dispatch_runtime == unsafe { nil } {
		return error('iOS: main Swift task enqueue outside scheduler lifetime')
	}
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_concurrency_retired || swift_task_find_locked(owner) == 0 {
		return error('iOS: main Swift executor requires a registered task job')
	}
	mut state := unsafe { &SwiftTaskState(owner + 80) }
	if state.phase != 0 { return error('iOS: main Swift task already enqueued or started') }
	swift_main_actor_arena()!
	C.pthread_mutex_lock(dispatch_runtime.mutex); defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if dispatch_runtime.stopping { return error('iOS: main Swift task enqueue during scheduler shutdown') }
	queue := dispatch_queue_locked(darwin_dispatch_get_main_queue())
	state.phase = 1; state.flags |= swift_task_on_main
	swift_task_main_job_count(1)
	// This consumes the job's existing execution reference, without touching
	// caller ownership. Publication is atomic with the scheduler's stop gate.
	dispatch_add_locked(queue,0,0,voidptr(owner),swift_task_main_dispatch,false)
}
fn swift_task_enqueue_main(owner u64) { swift_task_enqueue_main_checked(owner) or { panic(err) } }
fn swift_task_main_dispatch(argument voidptr) {
	base := ios_runtime.swift_main_actor_arena + u64(C.getpagesize())
	swift_task_run(u64(argument),base + 896,base + 1200)
}
fn swift_main_executor_enqueue_checked(job u64,metadata u64,table u64,owner u64) ! {
	if ios_runtime == unsafe { nil } { return error('iOS: main executor outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	data := ios_runtime.swift_main_actor_arena + u64(C.getpagesize())
	valid := swift_main_executor_is_singleton_locked(owner) && metadata == data + 664
		&& table in [data + 1200,data + 1280]!
	C.ios_objc_initialize_unlock()
	if !valid { return error('iOS: invalid main serial executor witness context') }
	swift_task_enqueue_main_checked(job)!
}
fn swift_main_executor_enqueue(job u64,metadata u64,table u64,owner u64) {
	swift_main_executor_enqueue_checked(job,metadata,table,owner) or { panic(err) }
}
