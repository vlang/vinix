// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	fn C.thread_set_exception_ports(u32, u32, u32, i32, i32) i32
	fn C.mach_port_allocate(u32, i32, &u32) i32
	fn C.mach_port_insert_right(u32, u32, u32, i32) i32
	fn C.mach_port_destroy(u32, u32) i32
	fn C.mach_port_get_refs(u32, u32, i32, &u32) i32
}
type TswapCall = fn (u32, u32, u32, i32, i32, voidptr, voidptr, voidptr, voidptr, voidptr) i32
type TswapWide = fn (u64, u64, u64, i64, i64, voidptr, voidptr, voidptr, voidptr, voidptr) i32
struct TswapSnapshot { mut: bytes [416]u8; result i32 }
fn tswap_snapshot(client TswapCall, name u32, mask u32, port u32, behavior i32, flavor i32, incoming u32, shift int) TswapSnapshot {
	mut value := TswapSnapshot{bytes: [416]u8{init: 0xa5}};base := u64(unsafe { &value.bytes[0] })+u64(shift);C.memcpy(voidptr(base+96),unsafe { &incoming },4)
	wide := unsafe { TswapWide(voidptr(client)) };darwin_set_errno(83)
	value.result=wide(0x1234567800000000|u64(name),0x1234567800000000|u64(mask),0x1234567800000000|u64(port),i64(0x1234567800000000|u64(u32(behavior))),i64(0x1234567800000000|u64(u32(flavor))),voidptr(base+16),voidptr(base+96),voidptr(base+176),voidptr(base+256),voidptr(base+336))
	assert unsafe { *C.ios_errno_address() }==83;return value
}
fn tswap_word(value &TswapSnapshot, offset int) u32 { mut word := u32(0);C.memcpy(unsafe { &word },unsafe { &value.bytes[offset] },4);return word }
fn tswap_expected(value &TswapSnapshot, mask u32, incoming u32, shift int, result i32) {
	mut expected := TswapSnapshot{bytes: [416]u8{init: 0xa5}};C.memcpy(unsafe { &expected.bytes[96+shift] },unsafe { &incoming },4)
	if result==0 { words := [mask,u32(mask!=0),0]!;if mask!=0 { C.memcpy(unsafe { &expected.bytes[16+shift] },unsafe { &words[0] },4);for offset in [176,256,336]! { C.memcpy(unsafe { &expected.bytes[offset+shift] },unsafe { &words[2] },4) } };C.memcpy(unsafe { &expected.bytes[96+shift] },unsafe { &words[1] },4) }
	assert value.result==result && C.memcmp(unsafe { &value.bytes[0] },unsafe { &expected.bytes[0] },416)==0
}
fn tswap_drop(value &TswapSnapshot, shift int) { $if macos { if value.result!=0 { return };count := tswap_word(value,96+shift);assert count<=14;for i in 0 .. count { port := tswap_word(value,176+shift+int(i)*4);if port!=0 && port!=0xffffffff { assert C.ios_native_port_deallocate(port)==0 } } } }
fn tswap_query(name u32, allocated bool) {
	for mask in [u32(0),2,6,0x3ffe]! {
		mut count := u32(0xffffffff);mut masks := [14]u32{init: 0xa5a5a5a5};mut ports := [14]u32{init: 0xa5a5a5a5};mut behaviors := [14]i32{init: -1};mut flavors := [14]i32{init: -1}
		assert darwin_thread_get_exception_ports(name,mask,unsafe { &masks[0] },unsafe { &count },unsafe { &ports[0] },unsafe { &behaviors[0] },unsafe { &flavors[0] })==0 && count==u32(allocated && mask!=0)
		if count!=0 { assert masks[0]==mask && ports[0]==0 && behaviors[0]==0 && flavors[0]==0 }
	}
}
fn tswap_errors(client TswapCall, name u32, result i32) {
	for mask in [u32(0),2,0xffffffff]! { for port in [u32(0),0x65432103]! {
		expected := if result==i32(0x10000003) { result } else if port!=0 { i32(0x1000000a) } else { result }
		value := tswap_snapshot(client,name,mask,port,1,999,0x98765432,1);tswap_expected(unsafe { &value },mask,0x98765432,1,expected)
		assert client(name,mask,port,1,999,voidptr(-1),voidptr(-1),voidptr(-1),voidptr(-1),voidptr(-1))==expected
	} }
}
fn tswap_linux(client TswapCall, name u32) {
	$if linux {
		for mask in [u32(0),2,6,0x800,0x3ffe,1,0x4000,0xffffffff]! { for incoming in [u32(0),1,14,0xffffffff]! { for shift in [0,1,3]! {
			value := tswap_snapshot(client,name,mask,0,0,0,incoming,shift);tswap_expected(unsafe { &value },mask,incoming,shift,if mask & ~u32(0x3ffe)==0 { i32(0) } else { i32(4) })
		} } }
		for behavior in [i32(0),1,3,4,i32(0x80000004),-1]! { for flavor in [i32(-1),0,6,8,25,27,28,999]! {
			value := tswap_snapshot(client,name,0,0,behavior,flavor,0xffffffff,1);tswap_expected(unsafe { &value },0,0xffffffff,1,if flavor in [i32(0),6,25,27]! && behavior!=4 { i32(0) } else { i32(4) })
		} }
		for tuple in [[i32(1),0]!,[0,6]!,[3,6]!]! { value := tswap_snapshot(client,name,2,0,tuple[0],tuple[1],0xffffffff,1);tswap_expected(unsafe { &value },2,0xffffffff,1,46) }
		tswap_query(name,true)
	}
}
fn tswap_native(client TswapCall, name u32) {
	$if macos {
		native := unsafe { TswapCall(voidptr(C.thread_swap_exception_ports)) };task := C.mach_task_self();mut old_masks := [14]u32{};mut old_ports := [14]u32{};mut old_behaviors := [14]i32{};mut old_flavors := [14]i32{};mut old_count := u32(0)
		assert C.thread_get_exception_ports(name,0x3ffe,unsafe { &old_masks[0] },unsafe { &old_count },unsafe { &old_ports[0] },unsafe { &old_behaviors[0] },unsafe { &old_flavors[0] })==0
		for mask in [u32(0),2,6,0x3ffe,1,0xffffffff]! { for incoming in [u32(0),1,14,0xffffffff]! { for shift in [0,1,3]! {
			assert C.thread_set_exception_ports(name,0x3ffe,0,0,0)==0
			baseline := tswap_snapshot(native,name,mask,0,0,0,incoming,shift);actual := tswap_snapshot(client,name,mask,0,0,0,incoming,shift)
			assert actual.result==baseline.result && C.memcmp(unsafe { &actual.bytes[0] },unsafe { &baseline.bytes[0] },416)==0;tswap_drop(unsafe { &actual },shift);tswap_drop(unsafe { &baseline },shift)
		} } }
		for flavor in i32(-2) .. 65 { baseline := tswap_snapshot(native,name,0,0,0,flavor,0,1);actual := tswap_snapshot(client,name,0,0,0,flavor,0,1);assert actual.result==baseline.result && C.memcmp(unsafe { &actual.bytes[0] },unsafe { &baseline.bytes[0] },416)==0 }
		mut port := u32(0);assert C.mach_port_allocate(task,1,unsafe { &port })==0 && C.mach_port_insert_right(task,port,port,20)==0
		assert C.thread_set_exception_ports(name,2,port,1,0)==0 && C.thread_set_exception_ports(name,4,port,3,6)==0;baseline := tswap_snapshot(native,name,6,0,0,0,0,1)
		assert C.thread_set_exception_ports(name,2,port,1,0)==0 && C.thread_set_exception_ports(name,4,port,3,6)==0;actual := tswap_snapshot(client,name,6,0,0,0,0,1)
		assert actual.result==0 && baseline.result==0 && tswap_word(unsafe { &actual },97)==2 && C.memcmp(unsafe { &actual.bytes[0] },unsafe { &baseline.bytes[0] },416)==0
		tswap_drop(unsafe { &actual },1);tswap_drop(unsafe { &baseline },1);mut refs := u32(0);assert C.mach_port_get_refs(task,port,0,unsafe { &refs })==0 && refs==1
		for i in 0 .. old_count { assert C.thread_set_exception_ports(name,old_masks[i],old_ports[i],old_behaviors[i],old_flavors[i])==0;if old_ports[i]!=0 && old_ports[i]!=0xffffffff { assert C.ios_native_port_deallocate(old_ports[i])==0 } }
		assert C.mach_port_destroy(task,port)==0
		println('NATIVE-THREAD-SWAP: native ten-argument records, masks/flavors, output-only counts, two old handler groups and balanced COPY_SEND rights')
	}
}
fn tswap_guard_alias(client TswapCall, name u32) {
	for first in 0 .. 5 { for second in first+1 .. 5 {
		mut bytes := [416]u8{init: 0xa5};mut expected := [416]u8{init: 0xa5};mut positions := [16,96,176,256,336]!;positions[second]=positions[first];values := [u32(2),1,0,0,0]!
		for i in 0 .. 5 { C.memcpy(unsafe { &expected[positions[i]] },unsafe { &values[i] },4) };base := u64(unsafe { &bytes[0] })
		assert client(name,2,0,0,0,voidptr(base+u64(positions[0])),voidptr(base+u64(positions[1])),voidptr(base+u64(positions[2])),voidptr(base+u64(positions[3])),voidptr(base+u64(positions[4])))==0 && C.memcmp(unsafe { &bytes[0] },unsafe { &expected[0] },416)==0
		$if linux { assert darwin_thread_get_exception_ports(name,2,voidptr(base+u64(positions[0])),voidptr(base+u64(positions[1])),voidptr(base+u64(positions[2])),voidptr(base+u64(positions[3])),voidptr(base+u64(positions[4])))==0 && C.memcmp(unsafe { &bytes[0] },unsafe { &expected[0] },416)==0 }
	} }
	page := usize(C.getpagesize());mapping := C.mmap(unsafe { nil },page*10,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert mapping!=voidptr(-1);defer { assert C.munmap(mapping,page*10)==0 }
	mut pointers := [5]voidptr{};for i in 0 .. 5 { pointers[i]=voidptr(u64(mapping)+u64(page)*u64(i*2+1)-4);assert C.mprotect(voidptr(u64(mapping)+u64(page)*u64(i*2+1)),page,C.PROT_NONE)==0 }
	assert client(name,2,0,0,0,pointers[0],pointers[1],pointers[2],pointers[3],pointers[4])==0;for i,value in [u32(2),1,0,0,0]! { assert read32(u64(pointers[i]))==value }
	assert client(name,0,0,1,0,voidptr(-1),pointers[1],voidptr(-1),voidptr(-1),voidptr(-1))==0 && read32(u64(pointers[1]))==0
	$if linux { assert darwin_thread_get_exception_ports(name,2,pointers[0],pointers[1],pointers[2],pointers[3],pointers[4])==0;for i,value in [u32(2),1,0,0,0]! { assert read32(u64(pointers[i]))==value } }
}
struct TswapWorker { client TswapCall; task u32; ready i32; gate i32 }
fn tswap_worker(context voidptr) voidptr {
	state := unsafe { &TswapWorker(context) };name := darwin_pthread_mach_thread_np(u64(C.pthread_self()));tswap_query(name,false)
	$if linux { rejected := tswap_snapshot(state.client,name,2,0,1,0,0,1);tswap_expected(unsafe { &rejected },2,0,1,46);tswap_query(name,false) }
	mut count := u32(0xffffffff);assert state.client(name,0,0,0,0,voidptr(-1),unsafe { &count },voidptr(-1),voidptr(-1),voidptr(-1))==0 && count==0;tswap_query(name,true)
	for _ in 0 .. 100 { value := tswap_snapshot(state.client,name,2,0,0,0,0,1);tswap_expected(unsafe { &value },2,0,1,0) }
	mut byte := u8(1);assert C.write(state.ready,unsafe { &byte },1)==1 && C.read(state.gate,unsafe { &byte },1)==1;return unsafe { nil }
}
fn tswap_workers(client TswapCall, task u32) {
	mut ready := [2]i32{};mut gate := [2]i32{};assert C.pipe(unsafe { &ready[0] })==0 && C.pipe(unsafe { &gate[0] })==0
	state := TswapWorker{client,task,ready[1],gate[0]};mut handles := [8]u64{};mut names := [8]u32{}
	for i in 0 .. 8 { assert darwin_pthread_create(unsafe { &handles[i] },unsafe { nil },unsafe { voidptr(tswap_worker) },unsafe { voidptr(&state) })==0;names[i]=darwin_pthread_mach_thread_np(handles[i]) }
	for _ in 0 .. 8 { mut byte := u8(0);assert C.read(ready[0],unsafe { &byte },1)==1 }
	for name in names { tswap_query(name,true);assert darwin_mach_port_mod_refs(task,name,0,1)==0 }
	tswap_native(client,names[0]);bytes := [u8(1),1,1,1,1,1,1,1]!;assert C.write(gate[1],unsafe { &bytes[0] },8)==8;for handle in handles { assert darwin_pthread_join(handle,unsafe { nil })==0 }
	for name in names { mut kind := u32(0);for _ in 0 .. 10000 { assert darwin_mach_port_type(task,name,unsafe { &kind })==0;if kind==0x100000 { break };C.usleep(100) };assert kind==0x100000;tswap_errors(client,name,0x10000003);assert darwin_mach_port_deallocate(task,name)==0 }
	for fd in [ready[0],ready[1],gate[0],gate[1]]! { assert C.close(fd)==0 }
}
fn test_thread_swap_exception_ports() {
	client := unsafe { TswapCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_thread_swap_exception_ports')!)) };tswap_errors(client,0,0x10000003)
	for _ in 0 .. 2 {
		system_data_start()!;task := system_data.task_self;name := darwin_mach_thread_self();host := darwin_mach_host_self()
		$if linux { tswap_query(name,false);bad := tswap_snapshot(client,name,1,0,0,0,0,1);tswap_expected(unsafe { &bad },1,0,1,4);tswap_query(name,false) }
		zero := tswap_snapshot(client,name,0,0,0,0,0xffffffff,1);tswap_expected(unsafe { &zero },0,0xffffffff,1,0);tswap_query(name,true);tswap_linux(client,name);tswap_native(client,name);tswap_guard_alias(client,name)
		for invalid in [u32(0),0xffffffff,0x65432103]! { tswap_errors(client,invalid,0x10000003) }
		mut semaphore := u32(0);assert darwin_semaphore_create(task,unsafe { &semaphore },0,1)==0;for wrong in [task,host,semaphore]! { tswap_errors(client,wrong,4) }
		mut receive := u32(0);assert darwin_mach_port_allocate(task,1,unsafe { &receive })==0
		missing := tswap_snapshot(client,name,0,receive,1,0,0,1);tswap_expected(unsafe { &missing },0,0,1,0x1000000a)
		assert darwin_mach_port_insert_right(task,receive,receive,20)==0;tswap_errors(client,receive,46)
		for handler in [task,name,host,semaphore]! { value := tswap_snapshot(client,name,0,handler,1,999,0,1);tswap_expected(unsafe { &value },0,0,1,17) }
		compatible := tswap_snapshot(client,name,0,receive,1,0,0xffffffff,3);tswap_expected(unsafe { &compatible },0,0xffffffff,3,0);tswap_query(name,true)
		unsupported := tswap_snapshot(client,name,2,receive,1,0,0xffffffff,3);tswap_expected(unsafe { &unsupported },2,0xffffffff,3,46);tswap_query(name,true)
		mut refs := u32(0);assert darwin_mach_port_get_refs(task,receive,0,unsafe { &refs })==0 && refs==1
		tswap_workers(client,task)
		$if linux { assert darwin_mach_port_get_refs(task,name,0,unsafe { &refs })==0 && darwin_mach_port_mod_refs(task,name,0,-i32(refs))==0;tswap_errors(client,name,0x10000003);mut address := u64(0);mut count := u32(0);assert darwin_task_threads(task,unsafe { &address },unsafe { &count })==0 && count==1 && read32(address)==name;tswap_query(name,true);assert darwin_vm_deallocate(task,address,u64(count)*4)==0 }
		image_atfork_start()!;child := C.ios_fork();assert child>=0
		if child==0 { fresh := darwin_mach_thread_self();tswap_query(fresh,false);tswap_linux(client,fresh);tswap_native(client,fresh);assert darwin_mach_port_deallocate(task,fresh)==0;C._exit(0) }
		mut status := i32(-1);assert C.ios_waitpid(child,unsafe { &status },0)==child && status==0;image_atfork_stop()
		assert darwin_mach_port_destroy(task,receive)==0 && darwin_semaphore_wait(semaphore)==0 && darwin_semaphore_destroy(task,semaphore)==0 && darwin_mach_port_deallocate(task,name)==0 && darwin_mach_port_deallocate(task,host)==0;system_data_stop()
	}
	mut rejected := false;runtime_symbol('/usr/lib/libobjc.A.dylib','_thread_swap_exception_ports') or { rejected=true };assert rejected
	println('IOS-THREAD-SWAP-EXCEPTION-PORTS: native swaps and COPY_SEND groups; Vinix zero-mask table creation and exact unset clears, matching queries, ten-argument ABI, guarded/unaligned/aliased outputs, descriptor precedence, eight live/retired workers, right reacquisition, fork and two runtimes; handler/policy installation and kernel delivery remain unsupported')
}
