// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
#include <sys/mman.h>
#include <unistd.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
struct TextFontNativeResponse { metadata u64 state u64 }
struct TextFontNativeString { first u64 second u64 }
type TextFontNativeAccess = fn(u64)TextFontNativeResponse
type TextFontNativeCString = fn(&char)TextFontNativeString
type TextFontNativeProbe = fn(&u64,u64,&u64)
type TextFontNativeDestroy = fn(u64,u64)
type TextFontNativeTag = fn(u64,u64)u32
type TextFontNativeTitle = fn()u64
type TextFontNativeDrop = fn(u64)
fn text_font_native_word(p u64)u64{return unsafe{*(&u64(p))}}
fn text_font_native_metadata(library voidptr,symbol &char)TextFontNativeResponse{entry:=C.dlsym(library,symbol);assert entry!=unsafe{nil};result:=unsafe{TextFontNativeAccess(entry)}(0);assert result.metadata!=0&&result.state==0;return result}
fn text_font_native_measure(){
 library:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert library!=unsafe{nil}&&core!=unsafe{nil}
 entry:=u64(C.dlsym(library,c'$s7SwiftUI4TextV4fontyAcA4FontVSgF'));initializer:=u64(C.dlsym(library,c'$s7SwiftUI4TextV8verbatimACSS_tcfC'));empty:=u64(C.dlsym(core,c'_swiftEmptyArrayStorage'));assert entry!=0&&initializer!=0&&empty!=0
 text:=text_font_native_metadata(library,c'$s7SwiftUI4TextVMa');modifier:=text_font_native_metadata(library,c'$s7SwiftUI4TextV8ModifierOMa');font:=text_font_native_metadata(library,c'$s7SwiftUI4FontVMa')
 witnesses:=text_font_native_word(text.metadata-8);mw:=text_font_native_word(modifier.metadata-8);fw:=text_font_native_word(font.metadata-8)
 assert text_font_native_word(text.metadata)==0x200&&text_font_native_word(witnesses+64)==32&&text_font_native_word(witnesses+72)==32&&text_font_native_word(mw+64)==9&&text_font_native_word(mw+72)==16&&text_font_native_word(fw+64)==8
 println('NATIVE-SWIFTUI-TEXT-FONT: Text size=32 stride=32 Modifier size=9 stride=16 Font size=8')
 destroy:=unsafe{TextFontNativeDestroy(voidptr(text_font_native_word(witnesses+8)))};tag:=unsafe{TextFontNativeTag(voidptr(text_font_native_word(mw+88)))}
 cstring_entry:=C.dlsym(core,c'$sSS7cStringSSSPys4Int8VG_tcfC');title_entry:=C.dlsym(library,c'$s7SwiftUI4FontV5titleACvgZ');drop_entry:=C.dlsym(core,c'swift_release');assert cstring_entry!=unsafe{nil}&&title_entry!=unsafe{nil}&&drop_entry!=unsafe{nil}
 cstring:=unsafe{TextFontNativeCString(cstring_entry)};title:=unsafe{TextFontNativeTitle(title_entry)};drop:=unsafe{TextFontNativeDrop(drop_entry)}
 provider:=title();assert provider!=0
 page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
 ops:=[u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xa9400620,0xa9410e22,0xf9401224,0xf9401628,0xf9401a34,0xf9401e35,0xd63f0200,0xa9000660,0xa9010e62,0xf9001268,0xa902d674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]!
 for i,op in ops{unsafe{*(&u32(code+u64(i*4)))=op}};C.__builtin___clear_cache(voidptr(code),voidptr(code+u64(ops.len*4)));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
 probe:=unsafe{TextFontNativeProbe(voidptr(code))}
 for value in ['Fortnite','a longer owned Fortnite Text with a heap string','a longer owned Text with é and 🎮']!{for argument in [u64(0),provider]!{
  words:=cstring(&char(value.str));heap:=words.second>>63==0;owner:=words.second&0x0fffffffffffffff;string_refs:=if heap{text_font_native_word(owner+8)}else{u64(0)}
  input:=[words.first,words.second,u64(0),u64(0),u64(0),u64(0),u64(0x5020),u64(0x5021)]!;mut source:=[7]u64{}
  probe(unsafe{&input[0]},initializer,unsafe{&source[0]});source[2]&=255
  assert source[0]==words.first&&source[1]==words.second&&source[2]==0&&source[3]==empty&&source[5]==0x5020&&source[6]==0x5021
  if heap{assert text_font_native_word(owner+8)==string_refs}
  before:=if heap{text_font_native_word(owner+8)}else{u64(0)};font_refs:=text_font_native_word(provider+8)
  first_input:=[argument,source[0],source[1],source[2],source[3],u64(0),u64(0x5020),u64(0x5021)]!;mut first:=[7]u64{};probe(unsafe{&first_input[0]},entry,unsafe{&first[0]});first[2]&=255
  assert first[0]==source[0]&&first[1]==source[1]&&first[2]==0&&first[3]!=empty&&first[3]!=0&&first[5]==0x5020&&first[6]==0x5021
  count:=text_font_native_word(first[3]+16);assert count==1;kind:=tag(first[3]+32,modifier.metadata)
  assert kind==1&&text_font_native_word(first[3]+32)==argument&&text_font_native_word(provider+8)==font_refs+if argument==0{u64(0)}else{u64(0x200000000)}
  println('NATIVE-SWIFTUI-TEXT-FONT-RESULT nil='+(argument==0).str()+' heap='+heap.str()+' storage-unchanged=true modifiers='+count.str()+' modifier-tag='+kind.str()+' payload-matches='+(text_font_native_word(first[3]+32)==argument).str()+' provider-ref-delta='+(text_font_native_word(provider+8)-font_refs).hex())
  if heap{assert text_font_native_word(owner+8)==before+0x200000000}
  second_input:=[argument,first[0],first[1],first[2],first[3],u64(0),u64(0x5020),u64(0x5021)]!;array_refs:=text_font_native_word(first[3]+8);mut second:=[7]u64{};probe(unsafe{&second_input[0]},entry,unsafe{&second[0]});second[2]&=255
  assert second[0]==source[0]&&second[1]==source[1]&&second[2]==0&&second[3]!=0&&second[5]==0x5020&&second[6]==0x5021
  assert second[3]!=first[3]&&text_font_native_word(second[3]+16)==2&&text_font_native_word(first[3]+16)==1&&text_font_native_word(first[3]+8)==array_refs
  for offset in [u64(32),u64(48)]!{assert tag(second[3]+offset,modifier.metadata)==1&&text_font_native_word(second[3]+offset)==argument}
  assert text_font_native_word(provider+8)==font_refs+if argument==0{u64(0)}else{u64(0x600000000)}
  println('NATIVE-SWIFTUI-TEXT-FONT-REPEAT modifiers='+text_font_native_word(second[3]+16).str()+' same-array='+(second[3]==first[3]).str()+' input-count='+text_font_native_word(first[3]+16).str()+' input-array-refs-unchanged='+(text_font_native_word(first[3]+8)==array_refs).str()+' provider-ref-delta='+(text_font_native_word(provider+8)-font_refs).hex())
  if heap{assert text_font_native_word(owner+8)==before+0x400000000}
  destroy(u64(unsafe{&second[0]}),text.metadata);if heap{assert text_font_native_word(owner+8)==before+0x200000000};assert text_font_native_word(provider+8)==font_refs+if argument==0{u64(0)}else{u64(0x200000000)}
  destroy(u64(unsafe{&first[0]}),text.metadata);if heap{assert text_font_native_word(owner+8)==before};assert text_font_native_word(provider+8)==font_refs
  destroy(u64(unsafe{&source[0]}),text.metadata)
 }}
 drop(provider);assert C.munmap(voidptr(code),page)==0&&C.dlclose(core)==0&&C.dlclose(library)==0
 println('NATIVE-SWIFTUI-TEXT-FONT: optional Font in x0, borrowed Text in x1-x4, four direct result registers, balanced native value-witness destruction and provider release; no application code or text rendering executed')
}

type TextFontProbe = fn (&u64,u64,&u64)
fn text_font_resolve() u64 {
	return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI4TextV4fontyAcA4FontVSgF') or { panic(err) }
}

fn text_font_reject(probe TextFontProbe, entry u64, guard u64, result u64, font_value u64) {
	mut fds := [2]i32{}
	assert C.pipe(unsafe { &fds[0] }) == 0
	pid := C.ios_fork(); assert pid >= 0
	if pid == 0 {
		C.close(fds[0]); assert C.dup2(fds[1],2) == 2; C.close(fds[1])
		input := [font_value,guard,guard,guard,guard,result,guard,guard]!
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
	assert output.contains('iOS: SwiftUI Text.font modifier construction is not implemented')
	for bad in ['runtime error:','AddressSanitizer','Segmentation fault','SIGSEGV','SIGBUS']! { assert !output.contains(bad),output }
}

fn text_font_reader() u64 {
	entry := text_font_resolve()
	for _ in 0..1024 { assert text_font_resolve() == entry }
	return entry
}

__global text_font_callback_calls = 0
fn text_font_callback(object u64, selector &char) {
	assert ios_runtime.swift_concurrency_retired
	assert text_font_resolve() == u64(unsafe { voidptr(swiftui_text_font_unavailable) })
	text_font_callback_calls++
}

fn test_swiftui_text_font() {
	$if macos { text_font_native_measure() }
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil },page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	guard := u64(C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	shared_base := u64(C.mmap(unsafe { nil },page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1) && guard != u64(-1) && shared_base != u64(-1)
	shared := shared_base+u64(page)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xa9400620,0xa9410e22,0xf9401224,0xf9401628,0xf9401a34,0xf9401e35,0xd63f0200,0xa9000660,0xa9010e62,0xf9001268,0xa902d674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]! { write32(code+u64(i*4),op) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code+84))
	assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC) == 0
	probe := unsafe { TextFontProbe(voidptr(code)) }; entry := text_font_resolve()
	for symbol in ['_$s7SwiftUI4TextV4fontyAcA4FontVSgFExtra','_$s11SwiftUICore4TextV4fontyAcA4FontVSgF','_$s7SwiftUI4TextV6italicACyF']! { if _ := swiftui_text_font_symbol(symbol) { assert false } }
	for _ in 0..2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0..8 { workers << spawn text_font_reader() }
		for worker in workers { assert worker.wait() == entry }; unsafe { workers.free() }
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']! { if _ := runtime_symbol(library,'_$s7SwiftUI4TextV4fontyAcA4FontVSgF') { assert false } }
		for font_value in [u64(0),guard,~u64(0)]! {
			text_font_reject(probe,entry,guard,guard,font_value)
			assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE) == 0
			C.memset(voidptr(shared),0xa5,page)
			for writable in [true,false]! {
				assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable { C.PROT_WRITE } else { 0 }) == 0
				for result in [shared,shared+u64(page)-128]! {
					text_font_reject(probe,entry,guard,result,font_value)
					for i in u64(0)..u64(page) { assert unsafe { *(&u8(shared+i)) } == 0xa5 }
				}
			}
		}
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'],c'VinixTextFontCallback',0)
		assert cls != 0 && objc_add_method(cls,u64(c'dealloc'),u64(unsafe { voidptr(text_font_callback) }),c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls)); before := text_font_callback_calls
		ios_runtime.swift_concurrency_retired = true; objc_stop()
		assert text_font_callback_calls == before+1 && ios_runtime.live == 0 && text_font_resolve() == entry
		text_font_reject(probe,entry,guard,guard,guard)
	}
	assert C.munmap(voidptr(code),page) == 0 && C.munmap(voidptr(guard),page) == 0 && C.munmap(voidptr(shared_base),page*3) == 0
	println('IOS-SWIFTUI-TEXT-FONT: diagnostic binding only, eight readers and 16384 concurrent resolutions, 32 child calls exit 1 with the modifier diagnostic, nil/protected/invalid Font and protected Text/self/x8, unchanged shared read-only/writable result pages at both protected boundaries, exact framework routing, callbacks and two drained runtime lifetimes; Text modifier construction, text rendering and application rendering remain unsupported')
}
