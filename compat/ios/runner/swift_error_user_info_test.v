// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFDictionary.h>
}
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.CFStringCreateWithBytes(voidptr,&u8,i64,u32,bool) voidptr
fn C.CFErrorCreate(voidptr,voidptr,i64,voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
fn C.CFDictionaryCreateMutable(voidptr,i64,voidptr,voidptr) voidptr
fn C.CFDictionarySetValue(voidptr,voidptr,voidptr)
fn C.CFDictionaryGetCount(voidptr) i64
fn C.CFDictionaryGetValue(voidptr,voidptr) voidptr
type EiProbe = fn (u64,u64,u64,u64,&u64,u64)
type EiGet = fn (u64,&u64,&SwiftErrorValue)
const ei_symbol = '_$ss5ErrorPsE9_userInfoyXlSgvg'

fn ei_control() u64 { return 0xfeed1234 }
fn ei_emit(code u64) {
	// Self, metadata, table, entry, output, x8. Capture x0 and the three
	// callee-saved Swift contexts; a nonzero control checks the adapter too.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3,
		0xaa0303f0, 0xaa0003f4, 0xaa0103e0, 0xaa0203e1,
		u32(0xd2800000 | (0x5121 << 5) | 21), u32(0xd2800000 | (0x5222 << 5) | 22),
		0xaa0503e8, 0xd63f0200, 0xf9000260, 0xa900d674, 0xf9000e76,
		0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
}
fn ei_capture(probe EiProbe,entry u64,source u64,metadata u64,table u64,guard u64) u64 {
 mut output := [u64(0x12345678),~u64(0),~u64(0),~u64(0),~u64(0),0x87654321]!
 probe(source,metadata,table,entry,unsafe{&output[1]},guard)
 assert output[0]==0x12345678&&output[5]==0x87654321
 assert output[2]==source&&output[3]==0x5121&&output[4]==0x5222
 return output[1]
}
fn ei_expect(probe EiProbe,entry u64,source u64,metadata u64,table u64,guard u64,expected u64){
 assert ei_capture(probe,entry,source,metadata,table,guard)==expected
}

fn C.CFGetTypeID(voidptr) u64
fn C.CFDictionaryGetTypeID() u64
fn C.mincore(voidptr,usize,&u8)i32
fn ei_native_empty(result u64){
 $if macos {assert result!=0&&C.CFGetTypeID(voidptr(result))==C.CFDictionaryGetTypeID()&&C.CFDictionaryGetCount(voidptr(result))==0}
}
fn ei_native(probe EiProbe,guard u64){
 $if macos {
  lib:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',C.RTLD_NOW);assert lib!=unsafe{nil}
  entry:=u64(C.dlsym(lib,unsafe{&char(ei_symbol.str+1)}));get_entry:=C.dlsym(lib,c'swift_getErrorValue');assert entry!=0&&get_entry!=unsafe{nil}
  text:='Error userInfo default ownership fixture'
  domain:=C.CFStringCreateWithBytes(unsafe{nil},text.str,i64(text.len),0x08000100,false)
  info:=C.CFDictionaryCreateMutable(unsafe{nil},0,unsafe{&C.kCFTypeDictionaryKeyCallBacks},unsafe{&C.kCFTypeDictionaryValueCallBacks})
  assert info!=unsafe{nil};C.CFDictionarySetValue(info,domain,domain)
  owner:=C.CFErrorCreate(unsafe{nil},domain,-17,info);assert owner!=unsafe{nil};C.CFRelease(info)
  before:=C.CFGetRetainCount(owner);get:=unsafe{EiGet(get_entry)}
  mut scratch:=u64(0);mut value:=SwiftErrorValue{};get(u64(owner),unsafe{&scratch},unsafe{&value})
  assert scratch==u64(owner)&&value.value==u64(unsafe{&scratch})
  page:=usize(C.getpagesize());source:=guard-8;unsafe{*(&u64(source))=u64(owner)}
  assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ)==0
  for _ in 0..32{result:=ei_capture(probe,entry,source,value.metadata,value.witness,guard);ei_native_empty(result);C.CFRelease(voidptr(result))}
  assert read64(source)==u64(owner)&&C.CFGetRetainCount(owner)==before
  // Concrete userInfo is nonempty. The default returns an owned empty
  // dictionary independently, rather than dispatching that concrete witness.
  first:=ei_capture(probe,entry,source,value.metadata,value.witness,guard)
  second:=ei_capture(probe,entry,source,value.metadata,value.witness,guard)
  concrete:=ei_capture(probe,read64(value.witness+24)&0x0000ffffffffffff,source,value.metadata,value.witness,guard)
  assert concrete!=0&&C.CFGetRetainCount(owner)==before;C.CFRelease(owner)
  ei_native_empty(first);C.CFRelease(voidptr(first));ei_native_empty(second);C.CFRelease(voidptr(second))
  assert C.CFDictionaryGetCount(voidptr(concrete))==1&&C.CFDictionaryGetValue(voidptr(concrete),domain)==domain
  C.CFRelease(voidptr(concrete));C.CFRelease(domain)
  assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ|C.PROT_WRITE)==0
  merge:=u64(C.dlsym(lib,c'$ss11_MergeErrorON'));table:=u64(C.dlsym(lib,c'$ss11_MergeErrorOs0B0sWP'));assert merge!=0&&table!=0
  for receiver in [u64(0),guard,~u64(0)]!{result:=ei_capture(probe,entry,receiver,merge,table,guard);ei_native_empty(result);C.CFRelease(voidptr(result))}
  println('NATIVE-ERROR-USER-INFO: owned empty dictionary default, exact readonly CFError reference word, zero-sized MergeError Self, protected x8, preserved x20/x21/x22, borrowed ownership and distinct concrete nonempty userInfo; both results survive Error destruction')
 }
}
fn ei_resolver()u64{return runtime_symbol('/usr/lib/swift/libswiftCore.dylib',ei_symbol)or{panic(err)}}
fn ei_empty(result u64){assert result!=0&&objc_is_kind(result,ios_runtime.names['NSDictionary'])&&obj_header(result).keys.len==0&&obj_header(result).refs==1}
fn ei_worker(probe EiProbe,entry u64,metadata u64,table u64,guard u64){
 for _ in 0..128{assert ei_resolver()==entry;result:=ei_capture(probe,entry,guard,metadata,table,guard);ei_empty(result);objc_release(result)}
}
fn ei_reject(source u64,metadata u64,table u64){if _:=swift_error_user_info_checked(source,metadata,table){assert false}}
fn test_swift_error_user_info(){
 $if !arm64{return}
 page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page*3,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
 defer{assert C.munmap(voidptr(code),page*3)==0}
 guard:=code+u64(page*2);source:=guard-8;ei_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+76))
 assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0&&C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
 probe:=unsafe{EiProbe(voidptr(code))};ei_expect(probe,u64(unsafe{voidptr(ei_control)}),guard,guard,guard,guard,0xfeed1234)
 ei_native(probe,guard)
 for _ in 0..2{
  objc_start();mut publishers:=[]thread u64{};for _ in 0..8{publishers<<spawn ei_resolver()};entries:=publishers.wait()
  for entry in entries{assert entry==entries[0]&&entry!=0};entry:=entries[0];arena:=ios_runtime.swift_error_arena;assert entry==arena+224
  domain:=owned_string('Error userInfo default ownership fixture')
  info:=cf_dictionary_mutable(0,0,cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks'),cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks'))
  cf_dictionary_set(info,domain,domain);objc_set_class(info,ios_runtime.names['NSDictionary'])
  owner:=objc_allocate(cf_error_type_id());mut header:=obj_header(owner);header.number=-17;header.fields[0]=domain;header.fields[1]=info // Transfer both owned fields.
  before:=header.refs;mut scratch:=u64(0);mut value:=SwiftErrorValue{};swift_error_value(owner,unsafe{&scratch},unsafe{&value})
  unsafe{*(&u64(source))=owner};assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ)==0
  for _ in 0..32{result:=ei_capture(probe,entry,source,value.metadata,value.witness,guard);ei_empty(result);objc_release(result)}
  assert read64(source)==owner&&obj_header(owner).refs==before&&obj_header(info).refs==1
  for bad in [u64(0),1,~u64(0),guard,value.metadata+8]!{ei_reject(guard,bad,value.witness);ei_reject(guard,value.metadata,bad)}
  for bad in [u64(0),1,~u64(0)]!{ei_reject(bad,value.metadata,value.witness)}
  assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ|C.PROT_WRITE)==0
  for bad in [u64(0),1,~u64(0)]!{unsafe{*(&u64(source))=bad};ei_reject(source,value.metadata,value.witness)}
  unsafe{*(&u64(source))=owner};assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ)==0
  first:=ei_capture(probe,entry,source,value.metadata,value.witness,guard)
  second:=ei_capture(probe,entry,source,value.metadata,value.witness,guard)
  concrete:=ei_capture(probe,read64(value.witness+24),source,value.metadata,value.witness,guard)
  assert concrete==info&&obj_header(info).refs==2&&obj_header(owner).refs==before;objc_release(owner)
  ei_empty(first);objc_release(first);ei_empty(second);objc_release(second)
  assert obj_header(concrete).refs==1&&obj_header(concrete).keys.len==1&&cf_dictionary_value(concrete,domain)==domain;objc_release(concrete)
  assert C.mprotect(voidptr(guard-u64(page)),page,C.PROT_READ|C.PROT_WRITE)==0
  unsafe{*(&u64(source))=0};ei_reject(source,value.metadata,value.witness)
  merge:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss11_MergeErrorON')or{panic(err)}
  table:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss11_MergeErrorOs0B0sWP')or{panic(err)}
  for receiver in [u64(0),guard,~u64(0)]!{result:=ei_capture(probe,entry,receiver,merge,table,guard);ei_empty(result);objc_release(result)}
  mut workers:=[]thread{};for _ in 0..8{workers<<spawn ei_worker(probe,entry,merge,table,guard)};workers.wait()
  assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib',ei_symbol+'Extra')==none
  assert runtime_symbol('/usr/lib/libSystem.B.dylib',ei_symbol)==none
  ios_runtime.swift_concurrency_retired=true;ei_reject(guard,guard,guard);assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib',ei_symbol)==none
  ios_runtime.swift_concurrency_retired=false
  assert ios_runtime.objects.len==0&&ios_runtime.live==0&&ios_runtime.swift_strings.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0
  objc_stop();assert ios_runtime.swift_error_arena==0;ei_reject(guard,guard,guard)
  for offset in [usize(0),page]!{
   $if macos{assert C.mprotect(voidptr(arena+u64(offset)),page,C.PROT_READ)==-1}
   $else{mut resident:=u8(0);assert C.mincore(voidptr(arena+u64(offset)),page,unsafe{&resident})==-1}
  }
 }
 println('IOS-ERROR-USER-INFO: native owned empty defaults for CFError/MergeError, readonly reference boundary and protected zero-size Self/x8, preserved contexts, borrowed owner unchanged, distinct concrete dictionary and both results survive Error destruction, invalid/retired rejection, eight cold publishers/workers and two drained/unmapped lifetimes')
}
