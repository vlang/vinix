// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
type SaBegin = fn(u64,u64,u64,u64)
type SaEnd = fn(u64)
struct SaApi { native bool begin SaBegin @[required] end SaEnd @[required] }
fn sa_api(native bool) SaApi {
	if native {
		h:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert h!=unsafe{nil}
		return SaApi{true,unsafe{SaBegin(C.dlsym(h,c'swift_beginAccess'))},unsafe{SaEnd(C.dlsym(h,c'swift_endAccess'))}}
	}
	return SaApi{false,unsafe{SaBegin(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_beginAccess') or {panic(err)}))},
		unsafe{SaEnd(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_endAccess') or {panic(err)}))}}
}
fn sa_fill(p u64) { unsafe{*(&u64(p))=0xabcd;*(&u64(p+8))=0x1234;*(&u64(p+16))=0x5678} }
fn sa_layout(api SaApi,guard u64) {
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe{nil},usize(page*3),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
	defer{assert C.munmap(voidptr(base),usize(page*3))==0}
	for at_end in [false,true]!{for flags in [u64(0),1,32,33]!{for pc in [u64(0),0x12345678]!{
		assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
		p:=base+page+if at_end{page-24}else{u64(0)};sa_fill(p)
		api.begin(guard+3,p,flags,pc)
		if flags&32==0{assert read64(p)==0&&read64(p+8)==0x1234&&read64(p+16)==0x5678}else{
			assert read64(p)==guard+3&&read64(p+8)!=0&&read64(p+16)==flags&1
			if pc!=0{assert read64(p+8)==pc}
		}
		before:=[read64(p),read64(p+8),read64(p+16)]!
		assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ)==0
		api.end(p);assert before==[read64(p),read64(p+8),read64(p+16)]!
	}}}
	// Instantaneous accesses touch only Pointer, including end's no-op read.
	assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ|C.PROT_WRITE)==0
	last:=base+page*2-8;unsafe{*(&u64(last))=123};api.begin(guard,last,0,0)
	assert read64(last)==0;assert C.mprotect(voidptr(base+page),usize(page),C.PROT_READ)==0;api.end(last)
}
fn sa_nested(api SaApi,guard u64) {
	p:=u64(C.calloc(65,24));assert p!=0;defer{C.free(voidptr(p))}
	for i in u64(0)..64{api.begin(guard,p+i*24,32,0x12345678);assert read64(p+i*24+16)==if i==0{u64(0)}else{p+(i-1)*24}}
	api.begin(guard,p+64*24,0,0);assert read64(p+64*24)==0;api.end(p+64*24)
	api.end(p+31*24);assert read64(p+32*24+16)==p+30*24
	for i in 0..64{index:=u64(63-i);if index!=31{api.end(p+index*24)}}
	for i in u64(0)..64{api.begin(guard+i,p+i*24,33,0)}
	for i in u64(0)..64{api.end(p+i*24)}
	api.begin(guard,p,33,0);api.end(p)
}
fn sa_worker(api SaApi,guard u64,ready chan u64,gate chan int) {
	p:=u64(C.calloc(1,24));assert p!=0
	api.begin(guard,p,33,0);ready<-p
	_:=<-gate;api.end(p);C.free(voidptr(p))
}
fn sa_threads(api SaApi,guard u64) {
	ready:=chan u64{cap:8};gate:=chan int{cap:8};mut workers:=[]thread{}
	for _ in 0..8{workers<<spawn sa_worker(api,guard,ready,gate)}
	for _ in 0..8{p:=<-ready;if !api.native{if _:=swift_access_end_checked(p){assert false}}}
	if !api.native{assert ios_runtime.swift_access_count==8}
	for _ in 0..8{gate<-1};workers.wait();unsafe{workers.free()};ready.close();gate.close()
}
fn sa_invalid(guard u64) {
	p:=u64(C.calloc(2,24));assert p!=0;defer{C.free(voidptr(p))};sa_fill(p);sa_fill(p+24)
	for flags in [u64(2),16,64,~u64(0)]!{if _:=swift_access_begin_checked(guard,p,flags,1){assert false}}
	assert read64(p)==0xabcd&&read64(p+8)==0x1234&&read64(p+16)==0x5678
	for invalid in [u64(0),1,~u64(7)]!{if _:=swift_access_begin_checked(guard,invalid,32,1){assert false};if _:=swift_access_end_checked(invalid){assert false}}
	if _:=swift_access_begin_checked(0,p,32,1){assert false};if _:=swift_access_begin_checked(p,p,32,1){assert false}
	swift_access_begin_checked(guard,p,32,1) or {panic(err)}
	for buffer in [p,p+8,p+16]!{if _:=swift_access_begin_checked(guard+1,buffer,32,1){assert false}}
	for flags in [u64(1),33]!{if _:=swift_access_begin_checked(guard,p+24,flags,1){assert false};assert read64(p+24)==0xabcd&&read64(p+32)==0x1234&&read64(p+40)==0x5678}
	assert read64(p)==guard&&read64(p+16)==0&&ios_runtime.swift_access_count==1
	if _:=swift_access_stop_checked(){assert false}
	swift_access_end_checked(p) or {panic(err)}
	if _:=swift_access_end_checked(p){assert false}
	for flags in [u64(0),1,32,33]!{
		swift_access_begin_checked(guard,p,33,1) or {panic(err)}
		if _:=swift_access_begin_checked(guard,p+24,flags,1){assert false}
		assert read64(p+24)==0xabcd&&read64(p+32)==0x1234&&read64(p+40)==0x5678
		swift_access_end_checked(p) or {panic(err)}
	}
	// Current-task state must not be mistaken for a synchronous TLS access set.
	swift_task_arena() or {panic(err)};assert C.pthread_setspecific(ios_runtime.swift_task_key,voidptr(1))==0
	if _:=swift_access_begin_checked(guard,guard,32,0){assert false};if _:=swift_access_end_checked(guard){assert false}
	assert C.pthread_setspecific(ios_runtime.swift_task_key,unsafe{nil})==0
	ios_runtime.swift_concurrency_retired=true
	if _:=swift_access_begin_checked(guard,guard,0,0){assert false};if _:=swift_access_end_checked(guard){assert false}
	ios_runtime.swift_concurrency_retired=false
}
fn sa_limit(guard u64) {
	p:=u64(C.calloc(4097,24));assert p!=0;defer{C.free(voidptr(p))}
	for i in u64(0)..4096{swift_access_begin_checked(guard,p+i*24,32,1) or {panic(err)}}
	sa_fill(p+4096*24);if _:=swift_access_begin_checked(guard,p+4096*24,32,1){assert false};assert read64(p+4096*24)==0xabcd
	for i in 0..4096{swift_access_end_checked(p+u64(4095-i)*24) or {panic(err)}}
}
fn sa_conflict_child(mode string) {
	parts:=mode.split(':');native:=parts[0]=='native';if !native{objc_start()};api:=sa_api(native)
	mut storage:=[6]u64{};p:=u64(unsafe{&storage[0]})
	api.begin(0x123456,p,parts[1].u64(),0);api.begin(0x123456,p+24,parts[2].u64(),0)
	panic('Swift access conflict failed to trap')
}
fn sa_conflicts(native bool) {
	for pair in [[u64(32),1]!,[u64(32),33]!,[u64(33),0]!,[u64(33),32]!,[u64(33),1]!,[u64(33),33]!]!{
		mut child:=os.new_process(os.executable());mut env:=os.environ();env['VINIX_SWIFT_ACCESS_CHILD']=if native{'native'}else{'compat'}+':'+pair[0].str()+':'+pair[1].str()
		child.set_environment(env);child.set_redirect_stdio_merged();child.run();log:=child.stdout_slurp();child.wait();status:=child.code;child.close()
		assert status!=0&&log.contains(if native{'Fatal access conflict detected.'}else{'unsupported Swift access scope or exclusive access conflict'}),log
	}
}
fn test_swift_access() {
	if mode:=os.getenv_opt('VINIX_SWIFT_ACCESS_CHILD'){sa_conflict_child(mode);return}
	page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=~u64(0)
	defer{assert C.munmap(voidptr(guard),page)==0}
	$if macos{api:=sa_api(true);sa_layout(api,guard);sa_nested(api,guard);sa_threads(api,guard);sa_conflicts(true);println('NATIVE-SWIFT-ACCESS: ordinary C void begin/end ABI, instantaneous checks and three-word tracked records, read/read nesting, fatal read/write conflicts, non-LIFO unlink, diagnostic PC, guarded identity and scratch, unchanged ended buffers and eight isolated threads')}
	for _ in 0..2{
		objc_start();api:=sa_api(false);sa_layout(api,guard);sa_nested(api,guard);sa_threads(api,guard);sa_invalid(guard);sa_limit(guard)
		$if macos{sa_conflicts(false)}
		assert ios_runtime.swift_access_count==0&&C.pthread_getspecific(ios_runtime.swift_access_key)==unsafe{nil}
		objc_stop();assert !ios_runtime.swift_access_key_live&&ios_runtime.swift_access_count==0&&ios_runtime.live==0
		if _:=swift_access_begin_checked(guard,guard,32,0){assert false};if _:=swift_access_end_checked(guard){assert false}
	}
	println('IOS-SWIFT-ACCESS: bounded synchronous begin/end scopes, exact guarded scratch writes and opaque borrowed identity, nested reads and independent modifies, exclusive conflicts rejected before writes, non-LIFO unlink and scratch reuse, 4096-scope bound, foreign/double end and task contexts rejected, eight isolated threads and two drained lifetimes')
}
