// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
struct FontTitleNativeResponse { metadata u64 state u64 }
struct FontTitleNativeName { data &char length usize }
type FontTitleNativeAccess = fn(u64)FontTitleNativeResponse
type FontTitleNativeGetter = fn()u64
type FontTitleNativeKeep = fn(u64)u64
type FontTitleNativeDrop = fn(u64)
type FontTitleNativeTypeName = fn(u64,bool)FontTitleNativeName
fn font_title_native_word(p u64)u64{return unsafe{*(&u64(p))}}
fn font_title_native_half(p u64)u32{return unsafe{*(&u32(p))}}
fn font_title_native_measure(){
 lib:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert lib!=unsafe{nil}&&core!=unsafe{nil}
 entry:=C.dlsym(lib,c'$s7SwiftUI4FontV5titleACvgZ');assert entry!=unsafe{nil}
 access:=unsafe{FontTitleNativeAccess(C.dlsym(lib,c'$s7SwiftUI4FontVMa'))};response:=access(0);assert response.metadata!=0&&response.state==0
 witnesses:=font_title_native_word(response.metadata-8)
 assert font_title_native_word(response.metadata)==0x200&&font_title_native_word(witnesses+64)==8&&font_title_native_word(witnesses+72)==8
 println('NATIVE-SWIFTUI-FONT-TITLE: Font kind='+font_title_native_word(response.metadata).hex()+' size='+font_title_native_word(witnesses+64).str()+' stride='+font_title_native_word(witnesses+72).str()+' flags='+font_title_native_half(witnesses+80).hex()+' extra='+font_title_native_half(witnesses+84).str())
 title:=unsafe{FontTitleNativeGetter(entry)};keep:=unsafe{FontTitleNativeKeep(C.dlsym(core,c'swift_retain'))};drop:=unsafe{FontTitleNativeDrop(C.dlsym(core,c'swift_release'))};name:=unsafe{FontTitleNativeTypeName(C.dlsym(core,c'swift_getTypeName'))}
 mut owners:=[8]u64{}
 mut first_refs:=u64(0)
 for i in 0..owners.len{owners[i]=title();assert owners[i]!=0;if i==0{first_refs=font_title_native_word(owners[0]+8)}else{assert owners[i]==owners[0]&&font_title_native_word(owners[0]+8)==first_refs+u64(i)*0x200000000}}
 for i,owner in owners{
  metadata:=font_title_native_word(owner);n:=name(metadata,true);assert n.length>0&&n.length<1024
  assert unsafe{tos(n.data,int(n.length))}=='SwiftUI.FontBox<SwiftUI.Font.TextStyleProvider>'&&font_title_native_half(metadata+48)==33
  before:=font_title_native_word(owner+8);assert keep(owner)==owner;after:=font_title_native_word(owner+8);drop(owner);assert font_title_native_word(owner+8)==before
  assert after==before+0x200000000
  println('NATIVE-SWIFTUI-FONT-TITLE-OWNER index='+i.str()+' same-as-first='+(owner==owners[0]).str()+' type='+unsafe{tos(n.data,int(n.length))}+' instance-size='+font_title_native_half(metadata+48).str()+' refs-before='+before.hex()+' refs-after-retain='+after.hex())
 }
 for i,owner in owners{before:=font_title_native_word(owner+8);drop(owner);if i+1<owners.len{assert font_title_native_word(owners[i+1]+8)==before-0x200000000}}
 println('NATIVE-SWIFTUI-FONT-TITLE: eight simultaneously owned results and balanced retain/release; no application code, FontBox virtual methods or rendering executed')
 assert C.dlclose(core)==0&&C.dlclose(lib)==0
}


type FontTitleProbe = fn (&u64,u64,&u64)
fn font_title_resolve() u64 {
	return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI4FontV5titleACvgZ') or { panic(err) }
}

fn font_title_reject(probe FontTitleProbe, entry u64, guard u64, result u64, self_value u64) {
	mut fds := [2]i32{}
	assert C.pipe(unsafe { &fds[0] }) == 0
	pid := C.ios_fork(); assert pid >= 0
	if pid == 0 {
		C.close(fds[0]); assert C.dup2(fds[1],2) == 2; C.close(fds[1])
		input := [guard,guard,guard,guard,result,self_value,guard]!
		mut output := [7]u64{}
		probe(unsafe { &input[0] },entry,unsafe { &output[0] })
		C._exit(0)
	}
	C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
	for {
		assert length < bytes.len
		count := C.read(fds[0],unsafe { &bytes[length] },usize(bytes.len-length))
		if count == 0 { break }
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		assert count > 0; length += int(count)
	}
	C.close(fds[0]); mut status := i32(0)
	assert C.ios_waitpid(pid,&status,0) == pid && status == 256
	output := unsafe { tos(&bytes[0],length) }
	assert output.contains('iOS: SwiftUI Font.title provider construction is not implemented')
	for bad in ['runtime error:','AddressSanitizer','Segmentation fault','SIGSEGV','SIGBUS']! { assert !output.contains(bad),output }
}

fn font_title_reader() u64 {
	entry := font_title_resolve()
	for _ in 0..1024 { assert font_title_resolve() == entry }
	return entry
}

__global font_title_callback_calls = 0
fn font_title_callback(object u64, selector &char) {
	assert ios_runtime.swift_concurrency_retired
	assert font_title_resolve() == u64(unsafe { voidptr(swiftui_font_title_unavailable) })
	font_title_callback_calls++
}

fn test_swiftui_font_title() {
	$if macos { font_title_native_measure() }
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil },page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	guard := u64(C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	shared_base := u64(C.mmap(unsafe { nil },page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1) && guard != u64(-1) && shared_base != u64(-1)
	shared := shared_base+u64(page)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xa9400620,0xa9410e22,0xf9401228,0xf9401634,0xf9401a35,0xd63f0200,0xa9000660,0xa9010e62,0xf9001268,0xa902d674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]! { write32(code+u64(i*4),op) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code+80))
	assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC) == 0
	probe := unsafe { FontTitleProbe(voidptr(code)) }; entry := font_title_resolve()
	for symbol in ['_$s7SwiftUI4FontV5titleACvgZExtra','_$s11SwiftUICore4FontV5titleACvgZ','_$s7SwiftUI4FontV4bodyACvgZ']! { if _ := swiftui_font_title_symbol(symbol) { assert false } }
	for _ in 0..2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0..8 { workers << spawn font_title_reader() }
		for worker in workers { assert worker.wait() == entry }; unsafe { workers.free() }
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']! { if _ := runtime_symbol(library,'_$s7SwiftUI4FontV5titleACvgZ') { assert false } }
		for self_value in [u64(0),guard,~u64(0)]! {
			font_title_reject(probe,entry,guard,guard,self_value)
			assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE) == 0
			C.memset(voidptr(shared),0xa5,page)
			for writable in [true,false]! {
				assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable { C.PROT_WRITE } else { 0 }) == 0
				for result in [shared,shared+u64(page)-128]! {
					font_title_reject(probe,entry,guard,result,self_value)
					for i in u64(0)..u64(page) { assert unsafe { *(&u8(shared+i)) } == 0xa5 }
				}
			}
		}
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'],c'VinixFontTitleCallback',0)
		assert cls != 0 && objc_add_method(cls,u64(c'dealloc'),u64(unsafe { voidptr(font_title_callback) }),c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls)); before := font_title_callback_calls
		ios_runtime.swift_concurrency_retired = true; objc_stop()
		assert font_title_callback_calls == before+1 && ios_runtime.live == 0 && font_title_resolve() == entry
		font_title_reject(probe,entry,guard,guard,guard)
	}
	assert C.munmap(voidptr(code),page) == 0 && C.munmap(voidptr(guard),page) == 0 && C.munmap(voidptr(shared_base),page*3) == 0
	println('IOS-SWIFTUI-FONT-TITLE: diagnostic binding only, eight readers and 16384 concurrent resolutions, 32 child calls exit 1 with the provider diagnostic, protected unused arguments/metadata/witness/self/x8, unchanged shared read-only/writable result pages at both protected boundaries, exact framework routing, callbacks and two drained runtime lifetimes; FontBox construction, font rendering and application rendering remain unsupported')
}
