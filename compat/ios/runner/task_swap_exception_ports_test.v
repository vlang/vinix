// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	fn C.task_set_exception_ports(u32, u32, u32, i32, i32) i32
	fn C.mach_port_allocate(u32, i32, &u32) i32
	fn C.mach_port_insert_right(u32, u32, u32, i32) i32
	fn C.mach_port_destroy(u32, u32) i32
	fn C.mach_port_get_refs(u32, u32, i32, &u32) i32
}
type SwapCall = fn (u32, u32, u32, i32, i32, voidptr, voidptr, voidptr, voidptr, voidptr) i32
type SwapWide = fn (u64, u64, u64, i64, i64, voidptr, voidptr, voidptr, voidptr, voidptr) i32
struct SwapSnapshot {
mut:
	bytes [416]u8
	result i32
}
fn swap_snapshot(client SwapCall, task u32, mask u32, port u32, behavior i32, flavor i32, incoming u32, shift int) SwapSnapshot {
	mut snapshot := SwapSnapshot{bytes: [416]u8{init: 0xa5}}
	base := u64(unsafe { &snapshot.bytes[0] }) + u64(shift); C.memcpy(voidptr(base+96),unsafe { &incoming },4)
	dirty := unsafe { SwapWide(voidptr(client)) }; darwin_set_errno(83)
	snapshot.result = dirty(0x1234567800000000|u64(task),0x1234567800000000|u64(mask),0x1234567800000000|u64(port),i64(0x1234567800000000|u64(u32(behavior))),i64(0x1234567800000000|u64(u32(flavor))),voidptr(base+16),voidptr(base+96),voidptr(base+176),voidptr(base+256),voidptr(base+336))
	assert unsafe { *C.ios_errno_address() } == 83
	return snapshot
}
fn swap_word(snapshot &SwapSnapshot, offset int) u32 { mut value := u32(0); C.memcpy(unsafe { &value },unsafe { &snapshot.bytes[offset] },4); return value }
fn swap_drop(snapshot &SwapSnapshot, shift int) {
	$if macos {
		if snapshot.result != 0 { return }; count := swap_word(snapshot,96+shift); assert count <= 14
		for i in 0 .. count { port := swap_word(snapshot,176+shift+int(i)*4); if port != 0 && port != 0xffffffff { assert C.ios_native_port_deallocate(port) == 0 } }
	}
}
fn swap_expected(actual &SwapSnapshot, mask u32, incoming u32, shift int, result i32) {
	mut expected := SwapSnapshot{bytes: [416]u8{init: 0xa5}}
	base := u64(unsafe { &expected.bytes[0] })+u64(shift); C.memcpy(voidptr(base+96),unsafe { &incoming },4)
	if result == 0 { words := [mask,u32(mask!=0),0]!;if mask!=0 { C.memcpy(voidptr(base+16),unsafe { &words[0] },4); for offset in [176,256,336]! { C.memcpy(voidptr(base+u64(offset)),unsafe { &words[2] },4) } };C.memcpy(voidptr(base+96),unsafe { &words[1] },4) }
	if actual.result != result { eprintln('SWAP-MISMATCH mask='+mask.hex()+' expected='+result.str()+' actual='+actual.result.str()) }
	assert actual.result == result
	assert C.memcmp(unsafe { &actual.bytes[0] },unsafe { &expected.bytes[0] },416) == 0
}
fn swap_linux(client SwapCall, task u32) {
	$if linux {
		for mask in [u32(0),2,4,0x800,0x2000,0x1bfe,0x3ffe,1,0x4000,0xffffffff]! { for incoming in [u32(0),1,14,0xffffffff]! { for shift in [0,1,3]! {
			actual := swap_snapshot(client,task,mask,0,0,0,incoming,shift);swap_expected(unsafe { &actual },mask,incoming,shift,if mask & ~u32(0x3ffe)==0 { i32(0) } else { i32(4) })
		} } }
		for behavior in [i32(0),1,2,3,4,5,i32(0x80000004),-1]! { for flavor in [i32(-1),0,6,8,25,27,28,999]! {
			valid := flavor in [i32(0),6,25,27]! && behavior != 4
			actual := swap_snapshot(client,task,0,0,behavior,flavor,0xffffffff,1);swap_expected(unsafe { &actual },0,0xffffffff,1,if valid { i32(0) } else { i32(4) })
		} }
		for tuple in [[i32(1),0]!,[0,6]!,[3,6]!]! { actual := swap_snapshot(client,task,2,0,tuple[0],tuple[1],0x98765432,3);swap_expected(unsafe { &actual },2,0x98765432,3,46) }
		mut masks := [14]u32{}; mut ports := [14]u32{}; mut behaviors := [14]i32{}; mut flavors := [14]i32{}; mut count := u32(0)
		assert darwin_task_get_exception_ports(task,0x3ffe,unsafe { &masks[0] },unsafe { &count },unsafe { &ports[0] },unsafe { &behaviors[0] },unsafe { &flavors[0] }) == 0 && count == 1 && masks[0] == 0x3ffe && ports[0] == 0 && behaviors[0] == 0 && flavors[0] == 0
	}
}
fn swap_native(client SwapCall, task u32) {
	$if macos {
		native := unsafe { SwapCall(voidptr(C.task_swap_exception_ports)) }; self := C.mach_task_self()
		mut masks := [14]u32{};mut handlers := [14]u32{};mut behaviors := [14]i32{};mut flavors := [14]i32{};mut count := u32(0)
		assert C.task_get_exception_ports(self,0x3ffe,unsafe { &masks[0] },unsafe { &count },unsafe { &handlers[0] },unsafe { &behaviors[0] },unsafe { &flavors[0] }) == 0
		mut port := u32(0);assert C.mach_port_allocate(self,1,unsafe { &port }) == 0 && C.mach_port_insert_right(self,port,port,20) == 0
		for mask in [u32(0),2,0x1bfe,0x3ffe,1,0xffffffff]! { for incoming in [u32(0),1,14,0xffffffff]! { for shift in [0,1,3]! {
			assert C.task_set_exception_ports(self,0x3ffe,0,0,0) == 0
			baseline := swap_snapshot(native,self,mask,0,0,0,incoming,shift)
			actual := swap_snapshot(client,task,mask,0,0,0,incoming,shift)
			assert actual.result == baseline.result && C.memcmp(unsafe { &actual.bytes[0] },unsafe { &baseline.bytes[0] },416) == 0
			swap_drop(unsafe { &actual },shift);swap_drop(unsafe { &baseline },shift)
		} } }
		for flavor in i32(-2) .. 65 { baseline := swap_snapshot(native,self,0,0,0,flavor,0,1);actual := swap_snapshot(client,task,0,0,0,flavor,0,1);assert actual.result == baseline.result && C.memcmp(unsafe { &actual.bytes[0] },unsafe { &baseline.bytes[0] },416) == 0 }
		// Two distinct old action groups use the same live send right. Keep
		// all COPY_SEND references until both records have been compared.
		for mask in [u32(2),6]! {
			assert C.task_set_exception_ports(self,2,port,1,0) == 0
			if mask==6 { assert C.task_set_exception_ports(self,4,port,3,6) == 0 }
			baseline := swap_snapshot(native,self,mask,0,0,0,0,1)
			assert C.task_set_exception_ports(self,2,port,1,0) == 0
			if mask==6 { assert C.task_set_exception_ports(self,4,port,3,6) == 0 }
			actual := swap_snapshot(client,task,mask,0,0,0,0,1)
			assert actual.result == 0 && baseline.result == 0 && swap_word(unsafe { &actual },97) == if mask==6 { u32(2) } else { u32(1) }
			assert C.memcmp(unsafe { &actual.bytes[0] },unsafe { &baseline.bytes[0] },416) == 0
			swap_drop(unsafe { &actual },1);swap_drop(unsafe { &baseline },1)
			mut refs := u32(0);assert C.mach_port_get_refs(self,port,0,unsafe { &refs }) == 0 && refs == 1
		}
		assert C.task_set_exception_ports(self,0x3ffe,0,0,0) == 0
		for i in 0 .. count { assert C.task_set_exception_ports(self,masks[i],handlers[i],behaviors[i],flavors[i]) == 0;if handlers[i]!=0 && handlers[i]!=0xffffffff { assert C.ios_native_port_deallocate(handlers[i]) == 0 } }
		assert C.mach_port_destroy(self,port) == 0
		println('NATIVE-TASK-SWAP: exact ten-argument records, output-only counts, masks, ARM flavors, two old action groups and balanced COPY_SEND references match native Mach')
	}
}
fn swap_errors(client SwapCall, task u32, result i32) {
	for mask in [u32(0),2,0xffffffff]! { for port in [u32(0),0x65432103]! {
		expected := if result==i32(0x10000003) { result } else if port!=0 { i32(0x1000000a) } else { result }
		actual := swap_snapshot(client,task,mask,port,1,999,0x98765432,1);swap_expected(unsafe { &actual },mask,0x98765432,1,expected)
		assert client(task,mask,port,1,999,voidptr(-1),voidptr(-1),voidptr(-1),voidptr(-1),voidptr(-1)) == expected
	} }
}
fn swap_guard_alias(client SwapCall, task u32) {
	// Type 1 starts with no inherited handler on the host; clearing it is
	// idempotent. The last two pointers travel on the caller's ARM64 stack.
	for first in 0 .. 5 { for second in first+1 .. 5 {
		mut bytes := [416]u8{init: 0xa5};mut expected := [416]u8{init: 0xa5};mut positions := [16,96,176,256,336]!;positions[second] = positions[first]
		values := [u32(2),1,0,0,0]!;for i in 0 .. 5 { C.memcpy(unsafe { &expected[positions[i]] },unsafe { &values[i] },4) }
		base := u64(unsafe { &bytes[0] });assert client(task,2,0,0,0,voidptr(base+u64(positions[0])),voidptr(base+u64(positions[1])),voidptr(base+u64(positions[2])),voidptr(base+u64(positions[3])),voidptr(base+u64(positions[4]))) == 0
		assert C.memcmp(unsafe { &bytes[0] },unsafe { &expected[0] },416) == 0
	} }
	page := usize(C.getpagesize());mapping := C.mmap(unsafe { nil },page*10,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert mapping!=voidptr(-1);defer { assert C.munmap(mapping,page*10)==0 }
	mut pointers := [5]voidptr{};for i in 0 .. 5 { pointers[i] = voidptr(u64(mapping)+u64(page)*u64(i*2+1)-4);assert C.mprotect(voidptr(u64(mapping)+u64(page)*u64(i*2+1)),page,C.PROT_NONE) == 0 }
	assert client(task,2,0,0,0,pointers[0],pointers[1],pointers[2],pointers[3],pointers[4]) == 0
	for i,value in [u32(2),1,0,0,0]! { assert read32(u64(pointers[i])) == value }
	assert client(task,0,0,1,0,voidptr(-1),pointers[1],voidptr(-1),voidptr(-1),voidptr(-1)) == 0 && read32(u64(pointers[1])) == 0
	assert client(task,1,0,0,0,voidptr(-1),voidptr(-1),voidptr(-1),voidptr(-1),voidptr(-1)) == 4
}
struct SwapWorker { client SwapCall; task u32 }
fn swap_worker(context voidptr) voidptr {
	state := unsafe { &SwapWorker(context) }
	for _ in 0 .. 500 { mut count := u32(0xffffffff);darwin_set_errno(83);assert state.client(state.task,0,0,1,0,voidptr(-1),unsafe { &count },voidptr(-1),voidptr(-1),voidptr(-1)) == 0 && count == 0 && unsafe { *C.ios_errno_address() } == 83 }
	return unsafe { nil }
}
fn test_task_swap_exception_ports() {
	client := unsafe { SwapCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_task_swap_exception_ports')!)) };swap_errors(client,0,0x10000003)
	for _ in 0 .. 2 {
		system_data_start()!;task := system_data.task_self;swap_linux(client,task);swap_native(client,task);swap_guard_alias(client,task)
		for name in [u32(0),0xffffffff,0x45678903]! { swap_errors(client,name,0x10000003) }
		worker := darwin_mach_thread_self();host := darwin_mach_host_self();mut semaphore := u32(0);assert darwin_semaphore_create(task,unsafe { &semaphore },0,1) == 0
		for name in [worker,host,semaphore]! { swap_errors(client,name,4) }
		mut receive := u32(0);assert darwin_mach_port_allocate(task,1,unsafe { &receive }) == 0
		unprepared := swap_snapshot(client,task,0,receive,1,0,0xffffffff,1);swap_expected(unsafe { &unprepared },0,0xffffffff,1,0x1000000a)
		assert darwin_mach_port_insert_right(task,receive,receive,20) == 0;swap_errors(client,receive,46)
		for name in [task,receive,worker,host,semaphore]! { actual := swap_snapshot(client,task,0,name,1,0,0xffffffff,3);swap_expected(unsafe { &actual },0,0xffffffff,3,if name == receive { i32(0) } else { i32(17) }) }
		for name in [task,worker,host,semaphore]! { for mask in [u32(0),1,2]! { for behavior in [i32(0),1]! {
			actual := swap_snapshot(client,task,mask,name,behavior,999,0x98765432,1);swap_expected(unsafe { &actual },mask,0x98765432,1,if mask==1 || behavior==0 { i32(4) } else { i32(17) })
		} } }
		$if linux { for _ in 0 .. 200 { actual := swap_snapshot(client,task,2,receive,1,0,0x98765432,3);swap_expected(unsafe { &actual },2,0x98765432,3,46) } }
		mut refs := u32(0);assert darwin_mach_port_get_refs(task,receive,0,unsafe { &refs }) == 0 && refs == 1
		mut handles := [8]u64{};state := SwapWorker{client,task};for i in 0 .. 8 { assert C.pthread_create(unsafe { voidptr(&handles[i]) },unsafe { nil },swap_worker,unsafe { voidptr(&state) }) == 0 };for handle in handles { assert C.pthread_join(voidptr(handle),unsafe { nil }) == 0 }
		image_atfork_start()!;child := C.ios_fork();assert child>=0;if child==0 { swap_linux(client,task);swap_native(client,task);C._exit(0) };mut status := i32(-1);assert C.ios_waitpid(child,unsafe { &status },0) == child && status == 0;image_atfork_stop()
		assert darwin_mach_port_destroy(task,receive) == 0 && darwin_semaphore_wait(semaphore) == 0 && darwin_semaphore_destroy(task,semaphore) == 0
		assert darwin_mach_port_deallocate(task,worker) == 0 && darwin_mach_port_deallocate(task,host) == 0
		system_data_stop();swap_errors(client,task,0x10000003)
	}
	mut rejected := false;runtime_symbol('/usr/lib/libobjc.A.dylib','_task_swap_exception_ports') or { rejected = true };assert rejected
	println('IOS-TASK-SWAP-EXCEPTION-PORTS: native Mach swap/rights and Vinix empty-mask/unset clears, ten-argument ABI, output-only counts, exact guarded/unaligned/aliased writes, descriptor precedence, eight workers, fork and two lifetimes; handler/policy installation and kernel fault delivery remain unsupported on Vinix')
}
