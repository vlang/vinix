// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
const personality_symbol='___objc_personality_v0'
type PersonalityProbe=fn(&u64,u64,&u64)
fn personality_resolve()u64{return runtime_symbol('/usr/lib/libobjc.A.dylib',personality_symbol) or {panic(err)}}
fn personality_reject(probe PersonalityProbe,entry u64,version u64,actions u64,exception_class u64,exception_object u64,context u64,guard u64,result u64){
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
	if pid==0{
		C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);input:=[version,actions,exception_class,exception_object,context,guard,guard,guard,guard,guard,result,guard,guard]!;mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});C._exit(0)
	}
	C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0
	for{assert length<bytes.len;count:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if count==0{break};if count<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert count>0;length+=int(count)}
	C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
	output:=unsafe{tos(&bytes[0],length)};assert output.contains('iOS: Objective-C exception unwinding through Mach-O frames is not implemented')&&!output.contains('iOS: C++ exception unwinding')
	for bad in ['runtime error:','AddressSanitizer','SIGSEGV','SIGBUS','Segmentation fault']!{assert !output.contains(bad),output}
}
fn personality_reader()u64{entry:=personality_resolve();for _ in 0..1024{assert personality_resolve()==entry};return entry}
__global personality_callback_calls=0
fn personality_callback(object u64,selector &char){assert ios_runtime.swift_concurrency_retired&&personality_resolve()==u64(unsafe{voidptr(objc_personality_unavailable)});personality_callback_calls++}
fn test_objc_personality(){
	$if macos{library:=C.dlopen(c'/usr/lib/libobjc.A.dylib',2);assert library!=unsafe{nil}&&C.dlsym(library,c'__objc_personality_v0')!=unsafe{nil};assert C.dlclose(library)==0;println('NATIVE-OBJC-PERSONALITY: libobjc export present; native personality, exception throwing and unwinding not invoked')}
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)&&base!=u64(-1);shared:=base+u64(page)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+100));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{PersonalityProbe(voidptr(code))};entry:=personality_resolve();assert entry==u64(unsafe{voidptr(objc_personality_unavailable)})
	for symbol in [personality_symbol+'Extra','__objc_personality_v0','___objc_personality_v1','___objc_personality_sj0','___gxx_personality_v0']!{if _:=objc_runtime_symbol(symbol){assert false}}
	for _ in 0..2{
		objc_start();mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn personality_reader()};for worker in workers{assert worker.wait()==entry};unsafe{workers.free()}
		for library in ['/usr/lib/libSystem.B.dylib','/usr/lib/libc++.1.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/usr/lib/swift/libswiftCore.dylib']!{if _:=runtime_symbol(library,personality_symbol){assert false}}
		for version in [u64(1),0,0xffffffff,0x7fffffff]!{for actions in [u64(1),2,6,8,0,0xffffffff]!{for exception_class in [u64(0),0x434c4e47432b2b00,~u64(0)]!{personality_reject(probe,entry,version,actions,exception_class,guard,guard,guard,guard)}}}
		for exception_object in [u64(0),1,~u64(0)]!{for context in [u64(0),1,~u64(0)]!{personality_reject(probe,entry,1,1,0,exception_object,context,guard,guard)}}
		assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(shared),0xa5,page)
		for writable in [true,false]!{assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable{C.PROT_WRITE}else{0})==0;for address in [shared,shared+u64(page)-32]!{personality_reject(probe,entry,1,2,~u64(0),address,guard,guard,address);personality_reject(probe,entry,1,8,0,guard,address,guard,address);for i in u64(0)..u64(page){assert unsafe{*(&u8(shared+i))}==0xa5}}}
		assert ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0&&ios_runtime.swiftui_opacity_arena==0&&ios_runtime.ns_exception_type_arena==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixPersonalityTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(personality_callback)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls));before:=personality_callback_calls
		ios_runtime.swift_concurrency_retired=true;objc_stop();assert personality_callback_calls==before+1&&ios_runtime.live==0&&ios_runtime.objects.len==0&&personality_resolve()==entry;personality_reject(probe,entry,1,1,0,guard,guard,guard,guard)
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0&&C.munmap(voidptr(base),page*3)==0
	println('IOS-OBJC-PERSONALITY: exact libobjc diagnostic binding, eight readers and 16384 concurrent resolutions, 180 child calls exit 1 across version/action/class and null/invalid/protected exception/context arguments, protected unused registers/stack/Self/x8, unchanged writable/read-only state at both guard boundaries, no exception/context reads or writes, no unwind result or additional metadata/owners, callback access and stable entry before startup/after two drained runtimes; Objective-C throwing, catching and Mach-O unwinding remain unsupported')
}
