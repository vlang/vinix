// SPDX-License-Identifier: GPL-2.0-or-later
module main

type ThreadsCall = fn (u32, voidptr, voidptr) i32
type ThreadsWide = fn (u64, voidptr, voidptr) i32
struct ThreadsSnapshot { address u64; count u32 }
fn threads_take(client ThreadsCall, task u32, shift int, incoming u32) ThreadsSnapshot {
	mut bytes := [48]u8{init: 0xa5};mut expected := [48]u8{init: 0xa5}
	base := u64(unsafe { &bytes[0] });C.memcpy(voidptr(base+24+u64(shift)),unsafe { &incoming },4)
	darwin_set_errno(83);wide := unsafe { ThreadsWide(voidptr(client)) }
	assert wide(0x1234567800000000|u64(task),voidptr(base+8+u64(shift)),voidptr(base+24+u64(shift))) == 0
	assert unsafe { *C.ios_errno_address() } == 83
	mut address := u64(0);mut count := u32(0);C.memcpy(unsafe { &address },voidptr(base+8+u64(shift)),8);C.memcpy(unsafe { &count },voidptr(base+24+u64(shift)),4)
	assert address!=0 && address & (mach_page_size()-1)==0 && count>0 && count<1024
	C.memcpy(unsafe { &expected[8+shift] },unsafe { &address },8);C.memcpy(unsafe { &expected[24+shift] },unsafe { &count },4)
	assert C.memcmp(unsafe { &bytes[0] },unsafe { &expected[0] },48)==0
	return ThreadsSnapshot{address,count}
}
fn threads_has(snapshot ThreadsSnapshot, name u32) bool {
	mut found := false
	for i in 0 .. snapshot.count {
		value := read32(snapshot.address+u64(i)*4)
		// Native copyout can lose a racing thread before its send right enters
		// this process. Null/dead literals do not identify a live thread.
		if value==0 || value==0xffffffff { continue }
		for j in 0 .. i { assert read32(snapshot.address+u64(j)*4)!=value }
		if value==name { found=true }
	}
	return found
}
fn threads_drop(task u32, snapshot ThreadsSnapshot) {
	for i in 0 .. snapshot.count { assert darwin_mach_port_deallocate(task,read32(snapshot.address+u64(i)*4))==0 }
	assert darwin_vm_deallocate(task,snapshot.address,u64(snapshot.count)*4)==0
}
fn threads_refs(task u32, name u32, right i32) u32 { mut value := u32(0);assert darwin_mach_port_get_refs(task,name,right,unsafe { &value })==0;return value }
fn threads_errors(client ThreadsCall, task u32, result i32) {
	for incoming in [u32(0),1,0xffffffff]! {
		mut bytes := [48]u8{init: 0xa5};base := u64(unsafe { &bytes[0] });C.memcpy(voidptr(base+25),unsafe { &incoming },4);before := bytes
		darwin_set_errno(83);assert client(task,voidptr(base+9),voidptr(base+25))==result && unsafe { *C.ios_errno_address() }==83
		assert C.memcmp(unsafe { &bytes[0] },unsafe { &before[0] },48)==0
		assert client(task,voidptr(-1),voidptr(-1))==result
	}
}
fn threads_dead(task u32, name u32) {
	mut kind := u32(0)
	for _ in 0 .. 10000 { assert darwin_mach_port_type(task,name,unsafe { &kind })==0;if kind==0x100000 { break };C.usleep(100) }
	assert kind==0x100000 && darwin_pthread_from_mach_thread_np(name)==0
}
struct ThreadsWorker { client ThreadsCall; task u32; gate i32 }
fn threads_worker(context voidptr) voidptr {
	state := unsafe { &ThreadsWorker(context) };mut byte := u8(0);assert C.read(state.gate,unsafe { &byte },1)==1
	self := darwin_pthread_mach_thread_np(u64(C.pthread_self()))
	for _ in 0 .. 50 { snapshot := threads_take(state.client,state.task,1,0xffffffff);assert threads_has(snapshot,self);threads_drop(state.task,snapshot) }
	return unsafe { nil }
}
fn threads_workers(client ThreadsCall, task u32, own u32) {
	mut gate := [2]i32{};assert C.pipe(unsafe { &gate[0] })==0
	state := ThreadsWorker{client,task,gate[0]};mut handles := [8]u64{};mut names := [8]u32{}
	for i in 0 .. 8 { assert darwin_pthread_create(unsafe { &handles[i] },unsafe { nil },unsafe { voidptr(threads_worker) },unsafe { voidptr(&state) })==0;names[i]=darwin_pthread_mach_thread_np(handles[i]);assert names[i]!=0 }
	held := threads_take(client,task,3,0)
	assert threads_has(held,own);for name in names { assert threads_has(held,name) }
	$if linux { assert held.count==9 }
	bytes := [u8(1),1,1,1,1,1,1,1]!;assert C.write(gate[1],unsafe { &bytes[0] },8)==8
	for handle in handles { assert darwin_pthread_join(handle,unsafe { nil })==0 }
	for name in names { threads_dead(task,name);assert threads_refs(task,name,4)==1 }
	current := threads_take(client,task,0,1);for name in names { assert !threads_has(current,name) };threads_drop(task,current)
	threads_drop(task,held);mut kind := u32(0);for name in names { assert darwin_mach_port_type(task,name,unsafe { &kind })==15 }
	assert C.close(gate[0])==0 && C.close(gate[1])==0
}
struct ThreadsDestructor { ready i32; gate i32; key u64 }
fn threads_destructor(context voidptr) {
	state := unsafe { &ThreadsDestructor(context) };mut byte := u8(1);assert C.write(state.ready,unsafe { &byte },1)==1;assert C.read(state.gate,unsafe { &byte },1)==1
}
fn threads_destructor_worker(context voidptr) voidptr {
	state := unsafe { &ThreadsDestructor(context) };assert C.pthread_setspecific(state.key,context)==0;return unsafe { nil }
}
fn threads_tsd(client ThreadsCall, task u32) {
	mut ready := [2]i32{};mut gate := [2]i32{};assert C.pipe(unsafe { &ready[0] })==0 && C.pipe(unsafe { &gate[0] })==0
	mut key := u64(0);assert darwin_key_create(unsafe { &key },unsafe { voidptr(threads_destructor) })==0
	state := ThreadsDestructor{ready[1],gate[0],key};mut handle := u64(0);assert darwin_pthread_create(unsafe { &handle },unsafe { nil },unsafe { voidptr(threads_destructor_worker) },unsafe { voidptr(&state) })==0
	mut byte := u8(0);assert C.read(ready[0],unsafe { &byte },1)==1
	name := darwin_pthread_mach_thread_np(handle);snapshot := threads_take(client,task,1,0);assert threads_has(snapshot,name)
	assert C.write(gate[1],unsafe { &byte },1)==1 && darwin_pthread_join(handle,unsafe { nil })==0;threads_dead(task,name);threads_drop(task,snapshot)
	assert C.pthread_key_delete(key)==0;for fd in [ready[0],ready[1],gate[0],gate[1]]! { assert C.close(fd)==0 }
}
fn threads_guard_alias(client ThreadsCall, task u32) {
	page := usize(C.getpagesize());mapping := C.mmap(unsafe { nil },page*4,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert mapping!=voidptr(-1)
	assert C.mprotect(voidptr(u64(mapping)+u64(page)),page,C.PROT_NONE)==0 && C.mprotect(voidptr(u64(mapping)+u64(page)*3),page,C.PROT_NONE)==0
	output := voidptr(u64(mapping)+u64(page)-8);count := voidptr(u64(mapping)+u64(page)*3-4);assert client(task,output,count)==0
	threads_drop(task,ThreadsSnapshot{read64(u64(output)),read32(u64(count))});assert C.munmap(mapping,page*4)==0
	for shift in -3 .. 9 {
		mut bytes := [48]u8{init: 0xa5};mut expected := [48]u8{init: 0xa5};base := u64(unsafe { &bytes[0] })
		assert client(task,voidptr(base+16),voidptr(base+u64(16+shift)))==0
		// Recover the owned array from the VM registry when aliasing destroys
		// its caller pointer. Its stored count is the last native output write.
		address := system_data.vm_mappings.last().address;mut length := u32(0);C.memcpy(unsafe { &length },voidptr(base+u64(16+shift)),4)
		C.memcpy(unsafe { &expected[16] },unsafe { &address },8);C.memcpy(unsafe { &expected[16+shift] },unsafe { &length },4)
		assert C.memcmp(unsafe { &bytes[0] },unsafe { &expected[0] },48)==0;threads_drop(task,ThreadsSnapshot{address,length})
	}
}
fn threads_dispatch(client ThreadsCall, task u32) {
	queue := darwin_dispatch_get_global_queue(0,0)
	semaphore := darwin_dispatch_semaphore_create(0)
	darwin_dispatch_async_f(queue,voidptr(semaphore),threads_dispatch_signal)
	assert darwin_dispatch_semaphore_wait(semaphore,u64(-1))==0
	snapshot := threads_take(client,task,1,0)
	assert dispatch_runtime.worker_count>0
	for i in 0 .. dispatch_runtime.worker_count { assert threads_has(snapshot,darwin_pthread_mach_thread_np(u64(dispatch_runtime.workers[i]))) }
	threads_drop(task,snapshot);darwin_dispatch_release(semaphore)
}
fn threads_dispatch_signal(context voidptr) { darwin_dispatch_semaphore_signal(u64(context)) }
fn test_task_threads() {
	client := unsafe { ThreadsCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_task_threads')!)) };threads_errors(client,0,0x10000003)
	for _ in 0 .. 2 {
		println('Task threads fixture: start')
		objc_start();system_data_start()!;task := system_data.task_self;own := darwin_pthread_mach_thread_np(u64(C.pthread_self()));baseline := threads_refs(task,own,0)
		for incoming in [u32(0),1,0xffffffff]! { for shift in [0,1,3]! { snapshot := threads_take(client,task,shift,incoming);assert threads_has(snapshot,own) && threads_refs(task,own,0)==baseline+1;threads_drop(task,snapshot);assert threads_refs(task,own,0)==baseline } }
		first := threads_take(client,task,1,0);second := threads_take(client,task,3,0xffffffff);assert threads_refs(task,own,0)==baseline+2
		// VM storage and the array's owned send rights have independent lives.
		for i in 0 .. first.count { assert darwin_mach_port_deallocate(task,read32(first.address+u64(i)*4))==0 }
		assert threads_has(first,own);assert darwin_vm_deallocate(task,first.address,u64(first.count)*4)==0;threads_drop(task,second);assert threads_refs(task,own,0)==baseline
		for name in [u32(0),0xffffffff,0x45678903]! { threads_errors(client,name,0x10000003) }
		host := darwin_mach_host_self();mut semaphore := u32(0);assert darwin_semaphore_create(task,unsafe { &semaphore },0,1)==0
		for name in [own,host,semaphore]! { threads_errors(client,name,4) }
		mut receive := u32(0);assert darwin_mach_port_allocate(task,1,unsafe { &receive })==0;threads_errors(client,receive,0x10000003)
		assert darwin_mach_port_insert_right(task,receive,receive,20)==0;threads_errors(client,receive,46)
		println('Task threads fixture: guards/alias');threads_guard_alias(client,task)
		println('Task threads fixture: workers');threads_workers(client,task,own)
		println('Task threads fixture: TSD');threads_tsd(client,task)
		$if linux {
			// A live thread whose last send right was dropped is still listed.
			assert darwin_mach_port_mod_refs(task,own,0,-i32(baseline))==0
			snapshot := threads_take(client,task,0,0);assert threads_has(snapshot,own) && threads_refs(task,own,0)==1;threads_drop(task,snapshot)
			C.ios_mach_threads_lock();mut port := system_data.thread_ports;assert port.name==own && port.refs==0;port.refs=65535;C.ios_mach_threads_unlock()
			pinned := threads_take(client,task,0,0);assert threads_refs(task,own,0)==65535;threads_drop(task,pinned);assert threads_refs(task,own,0)==65535
			C.ios_mach_threads_lock();port.refs=1;C.ios_mach_threads_unlock()
		}
		println('Task threads fixture: fork');image_atfork_start()!;child := C.ios_fork();assert child>=0
	if child==0 { snapshot := threads_take(client,task,1,0xffffffff);assert threads_has(snapshot,darwin_pthread_mach_thread_np(u64(C.pthread_self())));$if linux { assert snapshot.count==1 && !threads_has(snapshot,own) };threads_drop(task,snapshot);C._exit(0) }
		mut status := i32(-1);assert C.ios_waitpid(child,unsafe { &status },0)==child && status==0;image_atfork_stop()
		println('Task threads fixture: dispatch');threads_dispatch(client,task)
		assert system_data.vm_mappings.len==0
		assert darwin_mach_port_destroy(task,receive)==0 && darwin_semaphore_wait(semaphore)==0 && darwin_semaphore_destroy(task,semaphore)==0 && darwin_mach_port_deallocate(task,host)==0
		objc_stop();system_data_stop();threads_errors(client,task,0x10000003)
	}
	mut rejected := false;runtime_symbol('/usr/lib/libobjc.A.dylib','_task_threads') or { rejected=true };assert rejected
	println('IOS-TASK-THREADS: pointer8/count4 ABI, output-only counts, guarded/unaligned/aliased writes, independent VM/send rights, eight concurrent workers, retired/dead names, TSD lifetime, zero/saturated urefs, dispatch workers, fork and two runtime lifetimes')
}
