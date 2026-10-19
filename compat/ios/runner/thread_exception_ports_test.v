// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	fn C.thread_set_exception_ports(u32, u32, u32, i32, i32) i32
	fn C.mach_port_allocate(u32, i32, &u32) i32
	fn C.mach_port_insert_right(u32, u32, u32, i32) i32
	fn C.mach_port_get_refs(u32, u32, i32, &u32) i32
	fn C.mach_port_destroy(u32, u32) i32
}
type ThreadPortsCall = fn (u32, u32, voidptr, voidptr, voidptr, voidptr, voidptr) i32
type ThreadPortsWide = fn (u64, u64, voidptr, voidptr, voidptr, voidptr, voidptr) i32
struct ThreadPortsSnapshot {
mut:
	bytes [416]u8
	result i32
}
fn thread_ports_snapshot(client ThreadPortsCall, name u32, mask u32, incoming u32, shift int) ThreadPortsSnapshot {
	mut snapshot := ThreadPortsSnapshot{bytes: [416]u8{init: 0xa5}}
	base := u64(unsafe { &snapshot.bytes[0] })+u64(shift);C.memcpy(voidptr(base+96),unsafe { &incoming },4)
	wide := unsafe { ThreadPortsWide(voidptr(client)) };darwin_set_errno(83)
	snapshot.result = wide(0x1234567800000000|u64(name),0x1234567800000000|u64(mask),voidptr(base+16),voidptr(base+96),voidptr(base+176),voidptr(base+256),voidptr(base+336))
	assert unsafe { *C.ios_errno_address() }==83
	return snapshot
}
fn thread_ports_word(snapshot &ThreadPortsSnapshot, offset int) u32 { mut word := u32(0);C.memcpy(unsafe { &word },unsafe { &snapshot.bytes[offset] },4);return word }
fn thread_ports_drop(snapshot &ThreadPortsSnapshot, shift int) {
	$if macos {
		if snapshot.result!=0 { return };count := thread_ports_word(snapshot,96+shift);assert count<=14
		for i in 0 .. count { name := thread_ports_word(snapshot,176+shift+int(i)*4);if name!=0 && name!=0xffffffff { assert C.ios_native_port_deallocate(name)==0 } }
	}
}
fn thread_ports_expected(snapshot &ThreadPortsSnapshot, incoming u32, shift int, result i32) {
	mut expected := ThreadPortsSnapshot{bytes: [416]u8{init: 0xa5}};value := if result==0 { u32(0) } else { incoming }
	C.memcpy(unsafe { &expected.bytes[96+shift] },unsafe { &value },4)
	assert snapshot.result==result
	assert C.memcmp(unsafe { &snapshot.bytes[0] },unsafe { &expected.bytes[0] },416)==0
}
fn thread_ports_empty(client ThreadPortsCall, name u32) {
	for mask in [u32(0),2,4,0x400,0x800,0x2000,0x1bfe,0x3ffe,1,0x4000,0xffffffff]! { for incoming in [u32(0),1,14,0xffffffff]! { for shift in [0,1,3]! {
		actual := thread_ports_snapshot(client,name,mask,incoming,shift);thread_ports_expected(unsafe { &actual },incoming,shift,if mask & ~u32(0x3ffe)==0 { i32(0) } else { i32(4) })
	} } }
}
fn thread_ports_error(client ThreadPortsCall, name u32, result i32) {
	for mask in [u32(0),2,0xffffffff]! {
		actual := thread_ports_snapshot(client,name,mask,0x98765432,1);thread_ports_expected(unsafe { &actual },0x98765432,1,result)
		assert client(name,mask,voidptr(-1),voidptr(-1),voidptr(-1),voidptr(-1),voidptr(-1))==result
	}
}
fn thread_ports_native(client ThreadPortsCall, name u32) {
	$if macos {
		native := unsafe { ThreadPortsCall(voidptr(C.thread_get_exception_ports)) }
		for mask in [u32(0),2,4,0x2000,0x3ffe,1,0xffffffff]! { for incoming in [u32(0),1,14,0xffffffff]! { for shift in [0,1,3]! {
			baseline := thread_ports_snapshot(native,name,mask,incoming,shift);actual := thread_ports_snapshot(client,name,mask,incoming,shift)
			assert actual.result==baseline.result && C.memcmp(unsafe { &actual.bytes[0] },unsafe { &baseline.bytes[0] },416)==0
			thread_ports_drop(unsafe { &actual },shift);thread_ports_drop(unsafe { &baseline },shift)
		} } }
		mut masks := [14]u32{};mut ports := [14]u32{};mut behaviors := [14]i32{};mut flavors := [14]i32{};mut count := u32(0)
		assert C.thread_get_exception_ports(name,0x3ffe,unsafe { &masks[0] },unsafe { &count },unsafe { &ports[0] },unsafe { &behaviors[0] },unsafe { &flavors[0] })==0
		mut port := u32(0);task := C.mach_task_self();assert C.mach_port_allocate(task,1,unsafe { &port })==0 && C.mach_port_insert_right(task,port,port,20)==0
		assert C.thread_set_exception_ports(name,0x3ffe,0,0,0)==0
		assert C.thread_set_exception_ports(name,2,port,1,0)==0 && C.thread_set_exception_ports(name,4,port,3,6)==0
		for incoming in [u32(0),1,14,0xffffffff]! { for shift in [0,1,3]! {
			baseline := thread_ports_snapshot(native,name,6,incoming,shift);actual := thread_ports_snapshot(client,name,6,incoming,shift)
			assert actual.result==0 && baseline.result==0 && thread_ports_word(unsafe { &actual },96+shift)==2
			assert C.memcmp(unsafe { &actual.bytes[0] },unsafe { &baseline.bytes[0] },416)==0
			thread_ports_drop(unsafe { &actual },shift);thread_ports_drop(unsafe { &baseline },shift)
			mut refs := u32(0);assert C.mach_port_get_refs(task,port,0,unsafe { &refs })==0 && refs==1
		} }
		// Explicitly allocated native tables include null-action groups, unlike
		// a newly created thread's absent table. Measure overlapping output order.
		assert C.thread_set_exception_ports(name,0x3ffe,0,0,0)==0
		for first in 0 .. 5 { for second in first+1 .. 5 {
			mut bytes := [416]u8{init: 0xa5};mut expected := [416]u8{init: 0xa5};mut positions := [16,96,176,256,336]!;positions[second]=positions[first]
			base := u64(unsafe { &bytes[0] });values := [u32(2),1,0,0,0]!;for i in 0 .. 5 { C.memcpy(unsafe { &expected[positions[i]] },unsafe { &values[i] },4) }
			assert client(name,2,voidptr(base+u64(positions[0])),voidptr(base+u64(positions[1])),voidptr(base+u64(positions[2])),voidptr(base+u64(positions[3])),voidptr(base+u64(positions[4])))==0
			assert C.memcmp(unsafe { &bytes[0] },unsafe { &expected[0] },416)==0
		} }
		for i in 0 .. count { assert C.thread_set_exception_ports(name,masks[i],ports[i],behaviors[i],flavors[i])==0;if ports[i]!=0 && ports[i]!=0xffffffff { assert C.ios_native_port_deallocate(ports[i])==0 } }
		assert C.mach_port_destroy(task,port)==0
		println('NATIVE-THREAD-PORTS: live native records, absent/allocated action tables, two handler groups, output-only counts, overlapping copy order and balanced COPY_SEND rights')
	}
}
fn thread_ports_guard(client ThreadPortsCall, name u32) {
	page := usize(C.getpagesize());mapping := C.mmap(unsafe { nil },page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert mapping!=voidptr(-1)
	defer { assert C.munmap(mapping,page*2)==0 }
	assert C.mprotect(voidptr(u64(mapping)+u64(page)),page,C.PROT_NONE)==0
	count := voidptr(u64(mapping)+u64(page)-4)
	for mask in [u32(0),2,0x3ffe]! {
		$if macos { if mask!=0 { continue } }
		write32(u64(count),0xffffffff);assert client(name,mask,voidptr(-1),count,voidptr(-1),voidptr(-1),voidptr(-1))==0 && read32(u64(count))==0
		// Only count is written when an absent table returns zero groups.
		mut bytes := [32]u8{init: 0xa5};mut expected := [32]u8{init: 0xa5};zero := u32(0)
		C.memcpy(unsafe { &expected[9] },unsafe { &zero },4);base := u64(unsafe { &bytes[0] })
		assert client(name,mask,voidptr(base+9),voidptr(base+9),voidptr(base+9),voidptr(base+9),voidptr(base+9))==0 && C.memcmp(unsafe { &bytes[0] },unsafe { &expected[0] },32)==0
	}
}
struct ThreadPortsWorker { client ThreadPortsCall; task u32; ready i32; gate i32 }
fn thread_ports_worker(context voidptr) voidptr {
	state := unsafe { &ThreadPortsWorker(context) };name := darwin_pthread_mach_thread_np(u64(C.pthread_self()))
	thread_ports_empty(state.client,name);mut refs := u32(0)
	assert darwin_mach_port_get_refs(state.task,name,0,unsafe { &refs })==0;initial := refs
	for _ in 0 .. 500 { mut count := u32(0xffffffff);darwin_set_errno(83);assert state.client(name,0x3ffe,voidptr(-1),unsafe { &count },voidptr(-1),voidptr(-1),voidptr(-1))==0 && count==0 && unsafe { *C.ios_errno_address() }==83 }
	assert darwin_mach_port_get_refs(state.task,name,0,unsafe { &refs })==0 && refs==initial
	mut byte := u8(1);assert C.write(state.ready,unsafe { &byte },1)==1 && C.read(state.gate,unsafe { &byte },1)==1
	return unsafe { nil }
}
fn thread_ports_workers(client ThreadPortsCall, task u32) {
	mut ready := [2]i32{};mut gate := [2]i32{};assert C.pipe(unsafe { &ready[0] })==0 && C.pipe(unsafe { &gate[0] })==0
	state := ThreadPortsWorker{client,task,ready[1],gate[0]};mut handles := [8]u64{};mut names := [8]u32{}
	for i in 0 .. 8 { assert darwin_pthread_create(unsafe { &handles[i] },unsafe { nil },unsafe { voidptr(thread_ports_worker) },unsafe { voidptr(&state) })==0;names[i]=darwin_pthread_mach_thread_np(handles[i]);assert names[i]!=0 }
	for _ in 0 .. 8 { mut byte := u8(0);assert C.read(ready[0],unsafe { &byte },1)==1 }
	for name in names { thread_ports_empty(client,name);assert darwin_mach_port_mod_refs(task,name,0,1)==0 }
	bytes := [u8(1),1,1,1,1,1,1,1]!;assert C.write(gate[1],unsafe { &bytes[0] },8)==8
	for handle in handles { assert darwin_pthread_join(handle,unsafe { nil })==0 }
	for name in names {
		mut kind := u32(0);for _ in 0 .. 10000 { assert darwin_mach_port_type(task,name,unsafe { &kind })==0;if kind==0x100000 { break };C.usleep(100) };assert kind==0x100000
		thread_ports_error(client,name,0x10000003);assert darwin_mach_port_deallocate(task,name)==0
	}
	for fd in [ready[0],ready[1],gate[0],gate[1]]! { assert C.close(fd)==0 }
}
fn test_thread_exception_ports() {
	client := unsafe { ThreadPortsCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_thread_get_exception_ports')!)) };thread_ports_error(client,0,0x10000003)
	for _ in 0 .. 2 {
		system_data_start()!;task := system_data.task_self;name := darwin_mach_thread_self()
		$if linux { thread_ports_empty(client,name) }
		thread_ports_native(client,name);thread_ports_guard(client,name)
		for invalid in [u32(0),0xffffffff,0x65432103]! { thread_ports_error(client,invalid,0x10000003) }
		host := darwin_mach_host_self();mut semaphore := u32(0);assert darwin_semaphore_create(task,unsafe { &semaphore },0,1)==0
		for other in [task,host,semaphore]! { thread_ports_error(client,other,4) }
		mut receive := u32(0);assert darwin_mach_port_allocate(task,1,unsafe { &receive })==0;thread_ports_error(client,receive,0x10000003)
		assert darwin_mach_port_insert_right(task,receive,receive,20)==0;thread_ports_error(client,receive,46)
		thread_ports_workers(client,task)
		$if linux {
			mut refs := u32(0);assert darwin_mach_port_get_refs(task,name,0,unsafe { &refs })==0
			assert darwin_mach_port_mod_refs(task,name,0,-i32(refs))==0;thread_ports_error(client,name,0x10000003)
			mut array := u64(0);mut count := u32(0);assert darwin_task_threads(task,unsafe { &array },unsafe { &count })==0 && count==1 && read32(array)==name
			assert darwin_vm_deallocate(task,array,u64(count)*4)==0;thread_ports_empty(client,name)
		}
		image_atfork_start()!;child := C.ios_fork();assert child>=0
		if child==0 { fresh := darwin_mach_thread_self();thread_ports_native(client,fresh);$if linux { thread_ports_empty(client,fresh);thread_ports_error(client,name,0x10000003) };assert darwin_mach_port_deallocate(task,fresh)==0;C._exit(0) }
		mut status := i32(-1);assert C.ios_waitpid(child,unsafe { &status },0)==child && status==0;image_atfork_stop()
		assert darwin_mach_port_destroy(task,receive)==0 && darwin_semaphore_wait(semaphore)==0 && darwin_semaphore_destroy(task,semaphore)==0
		assert darwin_mach_port_deallocate(task,name)==0 && darwin_mach_port_deallocate(task,host)==0
		system_data_stop();$if linux { thread_ports_error(client,name,0x10000003) }
	}
	mut rejected := false;runtime_symbol('/usr/lib/libobjc.A.dylib','_thread_get_exception_ports') or { rejected=true };assert rejected
	println('IOS-THREAD-EXCEPTION-PORTS: absent-table zero groups, native installed records/COPY_SEND rights, output-only 32-bit counts, untouched/guarded/unaligned/aliased outputs, destination/mask precedence, eight live/retired threads, unchanged send references, fork and two runtimes; thread handler installation and kernel delivery remain unsupported on Vinix')
}
