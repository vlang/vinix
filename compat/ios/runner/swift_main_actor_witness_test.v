// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#include <CoreFoundation/CFRunLoop.h>
}
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.CFRunLoopRunInMode(voidptr,f64,bool) i32

type MainWitnessAccess = fn (u64) SwiftAssociatedMetadata
type MainWitnessProbe = fn (u64,u64,u64,u64,u64,&u64)
type MainWitnessLookup = fn (u64,u64,u64) u64
type MainWitnessSign = fn (u64,u64) u64
type MainWitnessGet = fn () SwiftExecutorPair
type MainWitnessIsMain = fn (u64,u64) bool
type MainWitnessRetain = fn (u64) u64
type MainWitnessRelease = fn (u64)
type MainWitnessCreate = fn (u64,u64,u64,u64,u64) SwiftTaskPair
type MainWitnessRun = fn (u64,u64,u64)
type MainWitnessCurrent = fn () u64
type MainWitnessEnqueue = fn (u64)
type MainWitnessSerial = fn (u64,u64,u64,u64,u64)
struct MainWitnessApi {
	native bool
	metadata u64
	actor u64
	descriptor u64
	protocol u64
	dispatcher u64
	@[required] lookup MainWitnessLookup
	@[required] get MainWitnessGet
	@[required] is_main MainWitnessIsMain
	@[required] retain MainWitnessRetain
	@[required] release MainWitnessRelease
	@[required] create MainWitnessCreate
	@[required] run MainWitnessRun
	@[required] current MainWitnessCurrent
	@[required] enqueue MainWitnessEnqueue
	switch_entry u64
}
struct MainWitnessScene {
	pair SwiftExecutorPair
	api MainWitnessApi
	thread u64
	continuation u64
mut:
	owner u64
	context u64
	calls u64
}

fn main_witness_initial(context u64,self u64) u64 {
	mut scene := unsafe { &MainWitnessScene(self) }
	assert scene.api.current() == scene.owner && context == scene.context
	assert u64(C.pthread_self()) == scene.thread && scene.calls == 0
	assert scene.api.is_main(scene.pair.identity,scene.pair.implementation)
	if !scene.api.native {
		assert unsafe { (&SwiftTaskState(scene.owner + 80)).flags } & swift_task_on_main != 0
		if _ := swift_task_switch_checked(context,scene.continuation,0,0) { assert false }
	}
	scene.calls = 1
	return scene.continuation
}
fn main_witness_resume(context u64) u64 {
	owner := main_witness_current_api()
	// Both implementations retain their original job resume/context fields
	// across a same-executor tail switch. Self is recovered from that context.
	mut scene := unsafe { &MainWitnessScene(read64(read64(owner + 64) - 16)) }
	assert scene.api.current() == owner && owner == scene.owner && context == scene.context
	assert u64(C.pthread_self()) == scene.thread && scene.calls == 1
	C.ios_store_pointer(unsafe { &scene.calls },2)
	return 0
}
__global main_witness_current_api = MainWitnessCurrent(unsafe { nil })

fn main_witness_emit(code u64,api MainWitnessApi) {
	// Ordinary arguments -> Swift metadata/table/self, with guarded registers.
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0203f4,
		0xaa0303f5,0xaa0403f0,0xd63f0200,0xa9000660,0xa9015674,
		0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! { write32(code + u64(i * 4),op) }
	write32(code + 64,0xdac10820); write32(code + 68,0xd65f03c0) // Native descriptor PACDA.
	for i,op in [u32(0xa9bf7bf4),0xaa0303f4,0xaa0403f0,0xd63f0200,0xa8c17bf4,0xd65f03c0]! {
		write32(code + 96 + u64(i * 4),op)
	}
	// Task body tail-switches on its actual main executor; no C frame remains.
	for i,op in [u32(0xa9bf7bfd),0xaa1603e0,0xaa1403e1,0x580001b0,0xd63f0200,
		0xa8c17bfd,if api.native {u32(0xdac123e0)} else {u32(0xd503201f)},
		0xa9400a81,0x58000150,0xd61f0200]! { write32(code + 512 + u64(i * 4),op) }
	unsafe { *(&u64(code + 576)) = u64(voidptr(main_witness_initial)); *(&u64(code + 584)) = api.switch_entry }
	for i,op in [u32(0xa9bf7bfd),0xaa1603e0,0x580001d0,0xd63f0200,0xa8c17bfd,
		0xaa0003f4,0xd2800015,0xf94006d0,if api.native {u32(0xdac143f0)} else {u32(0xd503201f)},0xd61f0200]! {
		write32(code + 640 + u64(i * 4),op)
	}
	unsafe { *(&u64(code + 704)) = u64(voidptr(main_witness_resume)) }
}
fn main_witness_api(native bool,probe MainWitnessProbe,sign MainWitnessSign) MainWitnessApi {
	mut lib := unsafe { voidptr(nil) }; mut core := unsafe { voidptr(nil) }
	$if macos { if native {
		lib = C.dlopen(c'/usr/lib/swift/libswift_Concurrency.dylib',2)
		core = C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2)
		assert lib != unsafe { nil } && core != unsafe { nil }
	} }
	mut entries := [14]u64{}
	for i,name in ['_$sScMMa','_$sScM6sharedScMvgZ','_$sScMScAsMc','_$sScAMp',
		'_$sScA15unownedExecutorScevgTj','_swift_getWitnessTable','_swift_task_getMainExecutor',
		'_swift_task_isMainExecutor','_swift_retain','_swift_release','_swift_task_create',
		'_swift_job_run','_swift_task_getCurrent','_swift_task_enqueueMainExecutor']! {
		is_core := i in [5,8,9]!
		entries[i] = if native { u64(C.dlsym(if is_core {core} else {lib},name[1..].str)) }
			else { runtime_symbol('/usr/lib/swift/' + if is_core {'libswiftCore.dylib'} else {'libswift_Concurrency.dylib'},name) or { panic(err) } }
		assert entries[i] != 0,name
	}
	metadata := unsafe { MainWitnessAccess(voidptr(entries[0]))(0) }.metadata
	mut output := [4]u64{}
	probe(0,0,metadata,0x5021,entries[1],unsafe { &output[0] })
	assert output[0] != 0 && output[2] == metadata && output[3] == 0x5021
	descriptor := if native { sign(entries[2],0xc6eb) } else { entries[2] }
	switch_entry := if native {u64(C.dlsym(lib,c'swift_task_switch'))} else {runtime_symbol('/usr/lib/swift/libswift_Concurrency.dylib','_swift_task_switch') or {panic(err)}}
	return MainWitnessApi{native: native, metadata: metadata, actor: output[0], descriptor: descriptor,
		protocol: entries[3],dispatcher: entries[4],lookup: unsafe {MainWitnessLookup(voidptr(entries[5]))},
		get: unsafe {MainWitnessGet(voidptr(entries[6]))},is_main: unsafe {MainWitnessIsMain(voidptr(entries[7]))},
		retain: unsafe {MainWitnessRetain(voidptr(entries[8]))},release: unsafe {MainWitnessRelease(voidptr(entries[9]))},
		create: unsafe {MainWitnessCreate(voidptr(entries[10]))},run: unsafe {MainWitnessRun(voidptr(entries[11]))},
		current: unsafe {MainWitnessCurrent(voidptr(entries[12]))},enqueue: unsafe {MainWitnessEnqueue(voidptr(entries[13]))},switch_entry: switch_entry}
}

fn main_witness_values(api MainWitnessApi,probe MainWitnessProbe,sample_refs bool) SwiftExecutorPair {
	assert read32(api.protocol) & 31 == 3 && read32(api.protocol + 12) == 1 && read32(api.protocol + 16) == 1
	table := api.lookup(api.descriptor,api.metadata,0) & 0x0000ffffffffffff
	assert table != 0 && read64(table) & 0x0000ffffffffffff == api.descriptor & 0x0000ffffffffffff
	expected := api.get()
	assert expected.identity != 0 && expected.implementation != 0 && api.is_main(expected.identity,expected.implementation)
	before := read64(api.actor + 8); executor_before := read64(expected.identity + 8)
	for entry in [api.dispatcher,read64(table + 8) & 0x0000ffffffffffff]! {
		mut out := [u64(0xfeedface),0,0,0,0,0xfeedface]!
		probe(api.metadata,table,api.actor,0x5021,entry,unsafe { &out[1] })
		assert out[0] == 0xfeedface && out[5] == 0xfeedface
		assert out[1] == expected.identity && out[2] == expected.implementation
		assert out[3] == api.actor && out[4] == 0x5021
	}
	assert read64(api.actor + 8) == before
	if sample_refs || !api.native { assert read64(expected.identity + 8) == executor_before }
	meta := read64(expected.identity) & 0x0000ffffffffffff
	assert read32(meta + 48) == 17 && unsafe { *(&u8(expected.identity + 16)) } == 0
	serial := expected.implementation & 0x0000fffffffffff8
	base := read64(serial + 8) & 0x0000ffffffffffff
	assert read32((read64(serial) & 0x0000ffffffffffff) + 12) == 0
	assert read32((read64(base) & 0x0000ffffffffffff) + 12) == 0
	mut output := [4]u64{}
	probe(meta,serial,expected.identity,0x5021,read64(serial + 40) & 0x0000ffffffffffff,unsafe { &output[0] })
	assert output[0] == expected.identity && output[1] == expected.implementation && output[2] == expected.identity && output[3] == 0x5021
	probe(meta,serial,expected.identity,0x5021,read64(serial + 64) & 0x0000ffffffffffff,unsafe { &output[0] })
	assert output[0] == 2 && output[2] == expected.identity && output[3] == 0x5021
	page := usize(C.getpagesize()); protected := u64(C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)); assert protected != u64(-1)
	assert api.lookup(api.descriptor,protected,protected) & 0x0000ffffffffffff == table
	probe(protected,protected,protected,0x5021,read64(table + 8) & 0x0000ffffffffffff,unsafe { &output[0] })
	assert output[0] == expected.identity && output[1] == expected.implementation && output[2] == protected
	if !api.native {
		assert !api.is_main(protected,protected) && !api.is_main(expected.identity,0) && !api.is_main(1,0)
		if _ := swift_main_executor_enqueue_checked(protected,protected,protected,protected) { assert false }
		if _ := swift_task_enqueue_main_checked(protected) { assert false }
		assert swift_object_type(expected.identity) == meta
		assert api.retain(expected.identity) == expected.identity; api.release(expected.identity)
	}
	assert C.munmap(voidptr(protected),page) == 0
	return expected
}

fn main_witness_job(api MainWitnessApi,code u64,pair SwiftExecutorPair,mode int) {
	page := usize(C.getpagesize())
	data := u64(C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)); assert data != u64(-1)
	descriptor := data + u64(page) - 8
	write32(descriptor,u32(i32(i64(code + 512) - i64(descriptor)))); write32(descriptor + 4,32)
	assert C.mprotect(voidptr(data),page,C.PROT_READ) == 0
	mut scene := unsafe { &MainWitnessScene(C.__builtin_alloca(sizeof(MainWitnessScene))) }
	unsafe { *scene = MainWitnessScene{pair: pair,api: api,thread: u64(C.pthread_self()),continuation: code + 640} }
	sign := unsafe { MainWitnessSign(voidptr(code + 64)) }
	task := api.create(0xc015,0,0,if api.native {sign(descriptor,3848)} else {descriptor},u64(scene))
	scene.owner = task.task; scene.context = task.context
	api.retain(task.task)
	if mode == 0 { api.run(task.task,pair.identity,pair.implementation) }
	else {
		if mode == 1 { api.enqueue(task.task) }
		else {
			serial := pair.implementation & 0x0000fffffffffff8
			table := if mode == 2 {serial} else {read64(serial + 8) & 0x0000ffffffffffff}
			slot := if mode == 2 {u64(2)} else {u64(1)}
			invoke := unsafe {MainWitnessSerial(voidptr(code + 96))}
			invoke(task.task,read64(pair.identity) & 0x0000ffffffffffff,table,pair.identity,read64(table + slot * 8) & 0x0000ffffffffffff)
		}
		assert scene.calls == 0
		if !api.native {
			assert read64(task.task + 8) == 0x200000003
			if _ := swift_task_enqueue_main_checked(task.task) { assert false }
			if _ := swift_task_run_checked(task.task,0,0) { assert false }
			if mode == 1 { swift_tasks_join() } else { assert dispatch_main_drain() }
		}
		$if macos { if api.native {
			for _ in 0 .. 1000 { if C.ios_load_pointer(unsafe { &scene.calls }) == 2 { break };C.CFRunLoopRunInMode(C.kCFRunLoopDefaultMode,0.01,true) }
		} }
	}
	assert C.ios_load_pointer(unsafe { &scene.calls }) == 2 && api.current() == 0
	assert read64(task.task + 8) == 3
	api.release(task.task)
	if !api.native { swift_tasks_drain_checked() or { panic(err) }; assert ios_runtime.swift_task_main_jobs == 0 }
	assert C.munmap(voidptr(data),page) == 0
}
fn main_witness_worker(api MainWitnessApi,probe MainWitnessProbe) {
	for _ in 0 .. 64 { main_witness_values(api,probe,false) }
}
fn test_swift_main_actor_witness() {
	$if !arm64 { return }
	page := usize(C.getpagesize())
	for native in [true,false,false]! {
		$if !macos { if native { continue } }
		if !native { objc_start(); system_data_start() or { panic(err) } }
		code := u64(C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)); assert code != u64(-1)
		// Bootstrap adapters precede any native static getter call.
		for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0203f4,0xaa0303f5,0xaa0403f0,0xd63f0200,0xa9000660,0xa9015674,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! {write32(code + u64(i * 4),op)}
		write32(code + 64,0xdac10820); write32(code + 68,0xd65f03c0)
		C.__builtin___clear_cache(voidptr(code),voidptr(code + 72)); assert C.mprotect(voidptr(code),page,C.PROT_READ | C.PROT_EXEC) == 0
		probe := unsafe {MainWitnessProbe(voidptr(code))}; sign := unsafe {MainWitnessSign(voidptr(code + 64))}
		api := main_witness_api(native,probe,sign)
		main_witness_current_api = api.current
		assert C.mprotect(voidptr(code),page,C.PROT_READ | C.PROT_WRITE) == 0
		main_witness_emit(code,api); C.__builtin___clear_cache(voidptr(code),voidptr(code + 712)); assert C.mprotect(voidptr(code),page,C.PROT_READ | C.PROT_EXEC) == 0
		pair := main_witness_values(api,probe,true)
		for mode in 0 .. 4 { main_witness_job(api,code,pair,mode) }
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn main_witness_worker(api,probe) }; workers.wait()
		if native { println('IOS-MAIN-ACTOR-WITNESS-NATIVE: real Actor descriptor/static witness lookup, borrowed executor getter and preserved context/error registers, nonzero main executor object and inherited Executor/SerialExecutor tables, protected unused metadata, asUnowned and nil isolation result, actual manual/main-queue jobs and same-executor tail continuation') }
		else {
			arena := ios_runtime.swift_main_actor_arena
			assert ios_runtime.swift_task_count == 0 && ios_runtime.swift_task_jobs == 0 && ios_runtime.swift_task_main_jobs == 0
			objc_stop(); system_data_stop()
			assert C.mprotect(voidptr(arena),page,C.PROT_READ) != 0
			assert C.mprotect(voidptr(arena + u64(page)),page,C.PROT_READ) != 0
			assert !api.is_main(pair.identity,pair.implementation)
		}
		assert C.munmap(voidptr(code),page) == 0
	}
	println('IOS-MAIN-ACTOR-WITNESS: private Actor conformance and complete main serial executor table, canonical immutable reference and borrowed lookup/getter, main-thread manual/deferred jobs, atomic enqueue ownership and join drain, real same-main tail switch, rejected invalid/unregistered jobs and cross-executor suspension, eight borrowed workers and two drained/unmapped lifetimes')
}
