// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	fn C.thread_suspend(u32) i32
	fn C.thread_info(u32, i32, voidptr, voidptr) i32
}
type ResumeCall = fn (u32) i32
type ResumeWide = fn (u64) i32

fn resume_call(client ResumeCall, name u32, expected i32) {
	wide := unsafe { ResumeWide(voidptr(client)) };darwin_set_errno(83)
	assert wide(0x1234567800000000|u64(name))==expected
	assert unsafe { *C.ios_errno_address() }==83
}
fn resume_refs(task u32, name u32, right i32) u32 {
	mut count := u32(0);assert darwin_mach_port_get_refs(task,name,right,unsafe { &count })==0;return count
}
fn resume_depth(name u32) u32 {
	$if macos {
		mut words := [10]u32{};mut count := u32(10)
		assert C.thread_info(name,3,unsafe { &words[0] },unsafe { &count })==0 && count==10
		return words[8]
	}
	return 0
}
fn resume_native(client ResumeCall, name u32, remote bool) {
	$if macos {
		assert resume_depth(name)==0
		for _ in 0 .. 3 { resume_call(client,name,C.thread_resume(name));assert resume_depth(name)==0 }
		if remote {
			for _ in 0 .. 3 {
				assert C.thread_suspend(name)==0 && resume_depth(name)==1
				assert C.thread_suspend(name)==0 && resume_depth(name)==2
				resume_call(client,name,0);assert resume_depth(name)==1
				resume_call(client,name,0);assert resume_depth(name)==0
				resume_call(client,name,5);assert resume_depth(name)==0
			}
		}
		println('NATIVE-THREAD-RESUME: native zero-count underflow and, for a remote worker, real nested 2-to-1-to-0 suspension transitions')
	}
}

struct ResumeWorker { client ResumeCall; owner u32; ready i32; gate i32; finish i32 }
fn resume_worker(context voidptr) voidptr {
	state := unsafe { &ResumeWorker(context) };name := darwin_pthread_mach_thread_np(u64(C.pthread_self()))
	mut byte := u8(1);assert C.write(state.ready,unsafe { &byte },1)==1 && C.read(state.gate,unsafe { &byte },1)==1
	for _ in 0 .. 200 { resume_call(state.client,name,5);resume_call(state.client,state.owner,5) }
	assert C.write(state.ready,unsafe { &byte },1)==1 && C.read(state.finish,unsafe { &byte },1)==1
	return unsafe { nil }
}
fn resume_ready(fd i32) { for _ in 0 .. 8 { mut byte := u8(0);assert C.read(fd,unsafe { &byte },1)==1 } }
fn resume_release(fd i32) { bytes := [u8(1),1,1,1,1,1,1,1]!;assert C.write(fd,unsafe { &bytes[0] },8)==8 }
fn resume_workers(client ResumeCall, task u32, owner u32) {
	mut ready := [2]i32{};mut gate := [2]i32{};mut finish := [2]i32{};assert C.pipe(unsafe { &ready[0] })==0 && C.pipe(unsafe { &gate[0] })==0 && C.pipe(unsafe { &finish[0] })==0
	state := ResumeWorker{client,owner,ready[1],gate[0],finish[0]};mut handles := [8]u64{};mut names := [8]u32{};mut refs := [8]u32{}
	for i in 0 .. 8 { assert darwin_pthread_create(unsafe { &handles[i] },unsafe { nil },unsafe { voidptr(resume_worker) },unsafe { voidptr(&state) })==0;names[i]=darwin_pthread_mach_thread_np(handles[i]) }
	resume_ready(ready[0])
	for i,name in names { assert darwin_mach_port_mod_refs(task,name,0,1)==0;refs[i]=resume_refs(task,name,0);resume_call(client,name,5) }
	resume_native(client,names[0],true)
	resume_release(gate[1]);resume_ready(ready[0])
	for i,name in names { resume_call(client,name,5);assert resume_refs(task,name,0)==refs[i] }
	resume_release(finish[1]);for handle in handles { assert darwin_pthread_join(handle,unsafe { nil })==0 }
	for name in names {
		mut kind := u32(0);for _ in 0 .. 10000 { assert darwin_mach_port_type(task,name,unsafe { &kind })==0;if kind==0x100000 { break };C.usleep(100) };assert kind==0x100000
		count := resume_refs(task,name,4);resume_call(client,name,0x10000003);assert resume_refs(task,name,4)==count && darwin_mach_port_deallocate(task,name)==0
		resume_call(client,name,0x10000003)
	}
	for fd in [ready[0],ready[1],gate[0],gate[1],finish[0],finish[1]]! { assert C.close(fd)==0 }
}

fn test_thread_resume() {
	client := unsafe { ResumeCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib','_thread_resume')!)) }
	resume_call(client,0,0x10000003)
	for _ in 0 .. 2 {
		system_data_start()!;task := system_data.task_self;name := darwin_mach_thread_self();host := darwin_mach_host_self()
		before := resume_refs(task,name,0);resume_native(client,name,false)
		for _ in 0 .. 200 { resume_call(client,name,5) };assert resume_refs(task,name,0)==before
		for invalid in [u32(0),0xffffffff,0x65432103]! { resume_call(client,invalid,0x10000003) }
		mut semaphore := u32(0);assert darwin_semaphore_create(task,unsafe { &semaphore },0,1)==0
		for wrong in [task,host,semaphore]! { resume_call(client,wrong,4) }
		mut receive := u32(0);assert darwin_mach_port_allocate(task,1,unsafe { &receive })==0;resume_call(client,receive,0x10000003)
		assert darwin_mach_port_insert_right(task,receive,receive,20)==0;resume_call(client,receive,46)
		assert darwin_mach_port_destroy(task,receive)==0;resume_call(client,receive,0x10000003)
		resume_workers(client,task,name)
		$if linux {
			// No remaining send right must not be mistaken for a resumable thread.
			assert darwin_mach_port_mod_refs(task,name,0,-i32(before))==0;resume_call(client,name,0x10000003)
			mut address := u64(0);mut count := u32(0);assert darwin_task_threads(task,unsafe { &address },unsafe { &count })==0 && count==1
			assert read32(address)==name;resume_call(client,name,5);assert darwin_vm_deallocate(task,address,u64(count)*4)==0
			name2 := darwin_mach_thread_self();assert name2==name;resume_call(client,name2,5);assert darwin_mach_port_deallocate(task,name)==0
		}
		image_atfork_start()!;child := C.ios_fork();assert child>=0
		if child==0 {
			fresh := darwin_mach_thread_self();resume_native(client,fresh,false);resume_call(client,fresh,5)
			$if linux { resume_call(client,name,0x10000003) }
			assert darwin_mach_port_deallocate(task,fresh)==0;C._exit(0)
		}
		mut status := i32(-1);assert C.ios_waitpid(child,unsafe { &status },0)==child && status==0;image_atfork_stop()
		assert darwin_semaphore_wait(semaphore)==0 && darwin_semaphore_destroy(task,semaphore)==0
		assert darwin_mach_port_deallocate(task,name)==0 && darwin_mach_port_deallocate(task,host)==0;system_data_stop()
	}
	mut rejected := false;runtime_symbol('/usr/lib/libobjc.A.dylib','_thread_resume') or { rejected=true };assert rejected
	println('IOS-THREAD-RESUME: native nested suspension counts and zero-count underflow; Vinix live threads reject underflow with KERN_FAILURE, dirty upper arguments/errno, eight concurrent workers, unchanged send/dead references, missing rights, wrong destinations, retirement, fork and two runtimes; per-thread suspension remains unsupported on Vinix')
}
