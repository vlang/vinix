// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos { fn C.thread_info(u32, i32, voidptr, voidptr) i32 }
type SuspendCall = fn (u32) i32
type SuspendWide = fn (u64) i32
fn suspend_call(client SuspendCall, name u32, expected i32) {
	wide := unsafe { SuspendWide(voidptr(client)) };darwin_set_errno(83)
	assert wide(0x1234567800000000|u64(name))==expected && unsafe { *C.ios_errno_address() }==83
}
fn suspend_refs(task u32, name u32, right i32) u32 { mut count := u32(0);assert darwin_mach_port_get_refs(task,name,right,unsafe { &count })==0;return count }
fn suspend_depth(name u32) u32 {
	$if macos { mut words := [10]u32{};mut count := u32(10);assert C.thread_info(name,3,unsafe { &words[0] },unsafe { &count })==0 && count==10;return words[8] }
	return 0
}
fn suspend_native_remote(client SuspendCall, resume SuspendCall, name u32) {
	$if macos {
		for _ in 0 .. 3 {
			assert suspend_depth(name)==0;suspend_call(client,name,0);assert suspend_depth(name)==1
			suspend_call(client,name,0);assert suspend_depth(name)==2
			suspend_call(resume,name,0);assert suspend_depth(name)==1
			suspend_call(resume,name,0);assert suspend_depth(name)==0;suspend_call(resume,name,5)
		}
		println('NATIVE-THREAD-SUSPEND: remote suspension counts 0-to-1-to-2 and balanced resumes, with errno preserved')
	}
}
struct SuspendSelf { target u32; resume SuspendCall }
fn suspend_resumer(context voidptr) voidptr {
	$if macos {
		state := unsafe { &SuspendSelf(context) }
		for _ in 0 .. 10000 {
			depth := suspend_depth(state.target)
			if depth!=0 { assert depth==1;suspend_call(state.resume,state.target,0);return unsafe { nil } }
			C.usleep(100)
		}
		panic('self suspension was not observed')
	}
	return unsafe { nil }
}
fn suspend_native_self(client SuspendCall, resume SuspendCall, name u32) {
	$if macos {
		assert suspend_depth(name)==0;state := SuspendSelf{name,resume};mut handle := u64(0)
		assert darwin_pthread_create(unsafe { &handle },unsafe { nil },unsafe { voidptr(suspend_resumer) },unsafe { voidptr(&state) })==0
		suspend_call(client,name,0);assert darwin_pthread_join(handle,unsafe { nil })==0 && suspend_depth(name)==0
		println('NATIVE-THREAD-SUSPEND: self suspension observed and resumed by another adapter thread, proving the namespace lock is released')
	}
}
struct SuspendWorker { client SuspendCall; resume SuspendCall; owner u32; ready i32; gate i32; finish i32 }
fn suspend_worker(context voidptr) voidptr {
	state := unsafe { &SuspendWorker(context) };name := darwin_pthread_mach_thread_np(u64(C.pthread_self()))
	mut byte := u8(1);assert C.write(state.ready,unsafe { &byte },1)==1 && C.read(state.gate,unsafe { &byte },1)==1
	$if linux { for _ in 0 .. 200 { suspend_call(state.client,name,46);suspend_call(state.client,state.owner,46);suspend_call(state.resume,name,5) } }
	assert C.write(state.ready,unsafe { &byte },1)==1 && C.read(state.finish,unsafe { &byte },1)==1
	return unsafe { nil }
}
fn suspend_ready(fd i32) { for _ in 0 .. 8 { mut byte := u8(0);assert C.read(fd,unsafe { &byte },1)==1 } }
fn suspend_release(fd i32) { bytes := [u8(1),1,1,1,1,1,1,1]!;assert C.write(fd,unsafe { &bytes[0] },8)==8 }
fn suspend_workers(client SuspendCall, resume SuspendCall, task u32, owner u32) {
	mut ready := [2]i32{};mut gate := [2]i32{};mut finish := [2]i32{};assert C.pipe(unsafe { &ready[0] })==0 && C.pipe(unsafe { &gate[0] })==0 && C.pipe(unsafe { &finish[0] })==0
	state := SuspendWorker{client,resume,owner,ready[1],gate[0],finish[0]};mut handles := [8]u64{};mut names := [8]u32{};mut refs := [8]u32{}
	for i in 0 .. 8 { assert darwin_pthread_create(unsafe { &handles[i] },unsafe { nil },unsafe { voidptr(suspend_worker) },unsafe { voidptr(&state) })==0;names[i]=darwin_pthread_mach_thread_np(handles[i]) }
	suspend_ready(ready[0]);for i,name in names { assert darwin_mach_port_mod_refs(task,name,0,1)==0;refs[i]=suspend_refs(task,name,0) }
	suspend_native_remote(client,resume,names[0])
	$if linux { for name in names { suspend_call(client,name,46);suspend_call(resume,name,5) } }
	suspend_release(gate[1]);suspend_ready(ready[0])
	for i,name in names { assert suspend_refs(task,name,0)==refs[i] }
	suspend_release(finish[1]);for handle in handles { assert darwin_pthread_join(handle,unsafe { nil })==0 }
	for name in names {
		mut kind := u32(0);for _ in 0 .. 10000 { assert darwin_mach_port_type(task,name,unsafe { &kind })==0;if kind==0x100000 { break };C.usleep(100) };assert kind==0x100000
		count := suspend_refs(task,name,4);suspend_call(client,name,0x10000003);assert suspend_refs(task,name,4)==count && darwin_mach_port_deallocate(task,name)==0;suspend_call(client,name,0x10000003)
	}
	for fd in [ready[0],ready[1],gate[0],gate[1],finish[0],finish[1]]! { assert C.close(fd)==0 }
}
fn test_thread_suspend() {
	client := unsafe { SuspendCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_thread_suspend')!)) };resume := unsafe { SuspendCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_thread_resume')!)) }
	suspend_call(client,0,0x10000003)
	for _ in 0 .. 2 {
		system_data_start()!;task := system_data.task_self;name := darwin_mach_thread_self();host := darwin_mach_host_self();before := suspend_refs(task,name,0)
		suspend_native_self(client,resume,name)
		$if linux { for _ in 0 .. 200 { suspend_call(client,name,46);suspend_call(resume,name,5) } }
		assert suspend_refs(task,name,0)==before
		for invalid in [u32(0),0xffffffff,0x65432103]! { suspend_call(client,invalid,0x10000003) }
		mut semaphore := u32(0);assert darwin_semaphore_create(task,unsafe { &semaphore },0,1)==0
		for wrong in [task,host,semaphore]! { suspend_call(client,wrong,4) }
		mut receive := u32(0);assert darwin_mach_port_allocate(task,1,unsafe { &receive })==0;suspend_call(client,receive,0x10000003)
		assert darwin_mach_port_insert_right(task,receive,receive,20)==0;suspend_call(client,receive,46);assert darwin_mach_port_destroy(task,receive)==0;suspend_call(client,receive,0x10000003)
		suspend_workers(client,resume,task,name)
		$if linux {
			assert darwin_mach_port_mod_refs(task,name,0,-i32(before))==0;suspend_call(client,name,0x10000003)
			mut address := u64(0);mut count := u32(0);assert darwin_task_threads(task,unsafe { &address },unsafe { &count })==0 && count==1 && read32(address)==name
			suspend_call(client,name,46);assert darwin_vm_deallocate(task,address,u64(count)*4)==0
			assert darwin_mach_thread_self()==name;suspend_call(client,name,46);assert darwin_mach_port_deallocate(task,name)==0
		}
		image_atfork_start()!;child := C.ios_fork();assert child>=0
		if child==0 { fresh := darwin_mach_thread_self();$if linux { suspend_call(client,name,0x10000003);suspend_call(client,fresh,46);suspend_call(resume,fresh,5) };$if macos { suspend_native_self(client,resume,fresh) };assert darwin_mach_port_deallocate(task,fresh)==0;C._exit(0) }
		mut status := i32(-1);assert C.ios_waitpid(child,unsafe { &status },0)==child && status==0;image_atfork_stop()
		assert darwin_semaphore_wait(semaphore)==0 && darwin_semaphore_destroy(task,semaphore)==0 && darwin_mach_port_deallocate(task,name)==0 && darwin_mach_port_deallocate(task,host)==0;system_data_stop()
	}
	mut rejected := false;runtime_symbol('/usr/lib/libobjc.A.dylib','_thread_suspend') or { rejected=true };assert rejected
	println('IOS-THREAD-SUSPEND: real native nested/self suspension and balanced resume; explicit unsupported result on Vinix, unchanged resume underflow/references, eight concurrent/retired workers, missing rights, wrong destinations, dirty upper arguments/errno, fork and two runtimes; no individual-thread suspension backend on Vinix')
}
