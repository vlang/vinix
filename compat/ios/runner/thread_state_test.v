// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	fn C.thread_suspend(u32) i32
	fn C.thread_resume(u32) i32
}
type StateCall = fn (u32, i32, voidptr, voidptr) i32
type StateWide = fn (u64, i64, voidptr, voidptr) i32
struct StateSnapshot {
mut:
	bytes [640]u8
	result i32
}
fn state_word(snapshot &StateSnapshot, offset int) u32 { mut value := u32(0);C.memcpy(unsafe { &value },unsafe { &snapshot.bytes[offset] },4);return value }
fn state_snapshot(client StateCall, name u32, flavor i32, incoming u32, shift int) StateSnapshot {
	mut value := StateSnapshot{bytes: [640]u8{init: 0xa5}};base := u64(unsafe { &value.bytes[0] })+u64(shift)
	C.memcpy(voidptr(base+592),unsafe { &incoming },4);wide := unsafe { StateWide(voidptr(client)) };darwin_set_errno(83)
	value.result=wide(0x1234567800000000|u64(name),i64(0x1234567800000000|u64(u32(flavor))),voidptr(base+16),voidptr(base+592))
	assert unsafe { *C.ios_errno_address() }==83
	return value
}
fn state_extent(snapshot &StateSnapshot, incoming u32, shift int, result i32, count u32) {
	mut expected := StateSnapshot{bytes: [640]u8{init: 0xa5}}
	C.memcpy(unsafe { &expected.bytes[592+shift] },unsafe { &incoming },4)
	assert snapshot.result==result
	if result==0 {
		assert count<=132 && state_word(snapshot,592+shift)==count
		C.memcpy(unsafe { &expected.bytes[16+shift] },unsafe { &snapshot.bytes[16+shift] },usize(count)*4)
		C.memcpy(unsafe { &expected.bytes[592+shift] },unsafe { &count },4)
	}
	assert C.memcmp(unsafe { &snapshot.bytes[0] },unsafe { &expected.bytes[0] },640)==0
}
fn state_errors(client StateCall, name u32, result i32) {
	for flavor in [i32(1),6,17,999]! { for incoming in [u32(0),70,132,0xffffffff]! {
		actual := state_snapshot(client,name,flavor,incoming,1);state_extent(unsafe { &actual },incoming,1,result,0)
		mut count := incoming;assert client(name,flavor,voidptr(-1),unsafe { &count })==result && count==incoming
	} }
}
fn state_linux(client StateCall, name u32, own bool) {
	$if linux {
		for flavor in [i32(-1),0,1,2,3,5,6,7,10,15,17,27,28,128,129,130,131,999]! {
			for incoming in [u32(0),1,3,4,5,6,64,65,67,68,69,70,129,130,131,132,133,1296,1297,0xffffffff]! { for shift in [0,1,3]! {
				length := thread_state_words(flavor)
				mut result := if length==0 || incoming<length { i32(4) } else { i32(46) }
				$if arm64 { if own && flavor==17 && incoming>=132 { result=0 } }
				actual := state_snapshot(client,name,flavor,incoming,shift);state_extent(unsafe { &actual },incoming,shift,result,if result==0 { u32(132) } else { u32(0) })
				if result==0 { assert state_word(unsafe { &actual },16+shift+520)==0 && state_word(unsafe { &actual },16+shift+524)==0 }
			} }
		}
	}
}
fn state_native(client StateCall, name u32, suspended bool) {
	$if macos {
		native := unsafe { StateCall(voidptr(C.thread_get_state)) }
		for flavor in [i32(-1),0,1,2,3,5,6,7,10,15,17,27,28,128,129,130,131,999]! { for incoming in [u32(0),1,4,6,65,68,69,70,130,131,132,133,1296,0xffffffff]! { for shift in [0,1,3]! {
			baseline := state_snapshot(native,name,flavor,incoming,shift);actual := state_snapshot(client,name,flavor,incoming,shift)
			assert actual.result==baseline.result && state_word(unsafe { &actual },592+shift)==state_word(unsafe { &baseline },592+shift)
			count := if actual.result==0 { state_word(unsafe { &actual },592+shift) } else { u32(0) }
			state_extent(unsafe { &actual },incoming,shift,baseline.result,count)
			if suspended && flavor in [i32(0),6,17,128,131]! { assert C.memcmp(unsafe { &actual.bytes[0] },unsafe { &baseline.bytes[0] },640)==0 }
		} } }
		println('NATIVE-THREAD-STATE: native flavors/counts/extents and destination handling; suspended GPR/NEON/flavor lists match exact native records')
	}
}
// Directly seed two vector registers immediately before the capture helper.
// Caller-saved v0/v31 may be changed by native calls inside the public query.
fn state_hardware() {
	$if arm64 {
		output := C.__builtin_alloca(528)
		asm arm64 raw {
			"movi v0.16b, #0x5a\n\tmovi v31.16b, #0xc3"
			;
			;
			; v0
			  v31
			  memory
		}
		thread_state_neon_snapshot(output)
		assert read64(u64(output))==0x5a5a5a5a5a5a5a5a && read64(u64(output)+8)==0x5a5a5a5a5a5a5a5a
		assert read64(u64(output)+496)==0xc3c3c3c3c3c3c3c3 && read64(u64(output)+504)==0xc3c3c3c3c3c3c3c3
		assert read64(u64(output)+520)==0
	}
}
fn state_guard_alias(client StateCall, name u32) {
	page := usize(C.getpagesize());mapping := C.mmap(unsafe { nil },page*4,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert mapping!=voidptr(-1)
	defer { assert C.munmap(mapping,page*4)==0 }
	assert C.mprotect(voidptr(u64(mapping)+u64(page)),page,C.PROT_NONE)==0 && C.mprotect(voidptr(u64(mapping)+u64(page)*3),page,C.PROT_NONE)==0
	output := voidptr(u64(mapping)+u64(page)-528);count := voidptr(u64(mapping)+u64(page)*3-4)
	write32(u64(count),132);assert client(name,17,output,count)==0 && read32(u64(count))==132
	for shift in [0,1,3,524]! {
		mut bytes := [640]u8{init: 0xa5};base := u64(unsafe { &bytes[0] });incoming := u32(132);C.memcpy(voidptr(base+16+u64(shift)),unsafe { &incoming },4)
		assert client(name,17,voidptr(base+16),voidptr(base+16+u64(shift)))==0
		mut length := u32(0);C.memcpy(unsafe { &length },voidptr(base+16+u64(shift)),4);assert length==132
		for i in 0 .. 16 { assert bytes[i]==0xa5 };for i in 544 .. 640 { assert bytes[i]==0xa5 }
	}
}
struct StateWorker { client StateCall; task u32; ready i32; gate i32 }
fn state_worker(context voidptr) voidptr {
	state := unsafe { &StateWorker(context) };name := darwin_pthread_mach_thread_np(u64(C.pthread_self()))
	state_hardware();state_linux(state.client,name,true)
	for _ in 0 .. 100 { snapshot := state_snapshot(state.client,name,17,132,1);state_extent(unsafe { &snapshot },132,1,0,132) }
	mut byte := u8(1);assert C.write(state.ready,unsafe { &byte },1)==1 && C.read(state.gate,unsafe { &byte },1)==1
	return unsafe { nil }
}
fn state_workers(client StateCall, task u32) {
	mut ready := [2]i32{};mut gate := [2]i32{};assert C.pipe(unsafe { &ready[0] })==0 && C.pipe(unsafe { &gate[0] })==0
	state := StateWorker{client,task,ready[1],gate[0]};mut handles := [8]u64{};mut names := [8]u32{}
	for i in 0 .. 8 { assert darwin_pthread_create(unsafe { &handles[i] },unsafe { nil },unsafe { voidptr(state_worker) },unsafe { voidptr(&state) })==0;names[i]=darwin_pthread_mach_thread_np(handles[i]) }
	for _ in 0 .. 8 { mut byte := u8(0);assert C.read(ready[0],unsafe { &byte },1)==1 }
	for i,name in names {
		assert darwin_mach_port_mod_refs(task,name,0,1)==0
		$if macos { if i==0 { assert C.thread_suspend(name)==0;state_native(client,name,true);assert C.thread_resume(name)==0 } }
		state_linux(client,name,false)
	}
	bytes := [u8(1),1,1,1,1,1,1,1]!;assert C.write(gate[1],unsafe { &bytes[0] },8)==8
	for handle in handles { assert darwin_pthread_join(handle,unsafe { nil })==0 }
	for name in names { mut kind := u32(0);for _ in 0 .. 10000 { assert darwin_mach_port_type(task,name,unsafe { &kind })==0;if kind==0x100000 { break };C.usleep(100) };assert kind==0x100000;state_errors(client,name,0x10000003);assert darwin_mach_port_deallocate(task,name)==0 }
	for fd in [ready[0],ready[1],gate[0],gate[1]]! { assert C.close(fd)==0 }
}
fn test_thread_state() {
	client := unsafe { StateCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_thread_get_state')!)) };state_errors(client,0,0x10000003)
	for _ in 0 .. 2 {
		system_data_start()!;task := system_data.task_self;name := darwin_mach_thread_self()
		state_hardware();state_native(client,name,false);state_linux(client,name,true);state_guard_alias(client,name)
		for invalid in [u32(0),0xffffffff,0x65432103]! { state_errors(client,invalid,0x10000003) }
		host := darwin_mach_host_self();mut semaphore := u32(0);assert darwin_semaphore_create(task,unsafe { &semaphore },0,1)==0
		for other in [task,host,semaphore]! { state_errors(client,other,4) }
		mut receive := u32(0);assert darwin_mach_port_allocate(task,1,unsafe { &receive })==0;state_errors(client,receive,0x10000003)
		assert darwin_mach_port_insert_right(task,receive,receive,20)==0;state_errors(client,receive,46)
		state_workers(client,task)
		image_atfork_start()!;child := C.ios_fork();assert child>=0
		if child==0 { fresh := darwin_mach_thread_self();state_hardware();state_native(client,fresh,false);state_linux(client,fresh,true);$if linux { state_errors(client,name,0x10000003) };assert darwin_mach_port_deallocate(task,fresh)==0;C._exit(0) }
		mut status := i32(-1);assert C.ios_waitpid(child,unsafe { &status },0)==child && status==0;image_atfork_stop()
		assert darwin_mach_port_destroy(task,receive)==0 && darwin_semaphore_wait(semaphore)==0 && darwin_semaphore_destroy(task,semaphore)==0
		assert darwin_mach_port_deallocate(task,name)==0 && darwin_mach_port_deallocate(task,host)==0;system_data_stop()
	}
	mut rejected := false;runtime_symbol('/usr/lib/libobjc.A.dylib','_thread_get_state') or { rejected=true };assert rejected
	println('IOS-THREAD-STATE: live native state queries and exact suspended native records; real current-thread ARM64 NEON capture in V, 132-word count, guarded/unaligned/aliased outputs, flavor/count/destination errors, eight live/retired workers, fork and two runtimes; general/debug/exception/remote snapshots remain unsupported on Vinix')
}
