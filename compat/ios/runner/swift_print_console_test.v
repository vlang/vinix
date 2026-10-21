// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
#include <stdio.h>
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.tmpfile() &C.FILE
fn C.clearerr(&C.FILE)
fn C.ferror(&C.FILE)i32
fn C.dup(i32)i32
type PcPrint=fn(u64,u64,u64,u64,u64)
type PcProbe=fn(u64,u64,u64,u64,u64,u64,&u64,u64)
type PcLiteral=fn(&u8,i64,bool)SwiftStringWords
type PcAllocate=fn(i64,u64)SwiftArrayAllocation
type PcDrop=fn(u64)
struct PcApi{
 entry u64
 code u64
 any u64
 string_type u64
 int_type u64
 bool_type u64
 static_type u64
 void_type u64
 merge_type u64
 literal PcLiteral @[required]
 allocate PcAllocate @[required]
 drop PcDrop @[required]
}
struct PcCapture{file &C.FILE saved i32}
fn pc_emit(code u64){
 for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0603f3,0xaa0503f0,0xaa0703f4,
  u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0703e8,0xd63f0200,
  0xa9005674,0xf9000a76,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
}
fn pc_begin()PcCapture{
 assert C.fflush(C.stdout)==0
 file:=C.tmpfile();assert file!=unsafe{nil};saved:=C.dup(1);assert saved>=0&&C.dup2(C.fileno(file),1)==1
 return PcCapture{file,saved}
}
fn pc_end(capture PcCapture)string{
 assert C.fflush(C.stdout)==0&&C.dup2(capture.saved,1)==1&&C.close(capture.saved)==0
 assert C.fseek(capture.file,0,2)==0;length:=C.ftell(capture.file);assert length>=0&&length<=2097152
 assert C.fseek(capture.file,0,0)==0
 data:=u64(C.malloc(usize(length+1)));assert data!=0
 assert C.fread(voidptr(data),1,usize(length),capture.file)==usize(length)&&C.fclose(capture.file)==0
 unsafe{*(&u8(data+u64(length)))=0};return unsafe{tos(&u8(data),int(length))}
}
fn pc_invoke(api PcApi,owner u64,separator SwiftStringWords,terminator SwiftStringWords,guard u64){
 mut result:=[u64(0xcafe),0,0,0,0xbeef]!
 unsafe{PcProbe(voidptr(api.code))(owner,separator.first,separator.second,terminator.first,terminator.second,api.entry,&result[1],guard)}
 assert result==[u64(0xcafe),guard,0x5121,0x5222,0xbeef]!
}
fn pc_check(api PcApi,owner u64,separator SwiftStringWords,terminator SwiftStringWords,guard u64,expected string){
 capture:=pc_begin();pc_invoke(api,owner,separator,terminator,guard);actual:=pc_end(capture)
 assert actual==expected,'console output mismatch';unsafe{actual.free()}
}
fn pc_word(api PcApi,text string)SwiftStringWords{return api.literal(text.str,i64(text.len),text.is_ascii())}
fn pc_slots(api PcApi,count i64)SwiftArrayAllocation{
 allocation:=api.allocate(count,api.any)
 if count!=0{C.memset(voidptr(allocation.bytes),0,usize(count*32))}
 return allocation
}
fn pc_forget(api PcApi,owner u64){
 // Elements borrow the independently held fixture values. Publish zero
 // initialized elements before releasing the Array's owned allocation.
 if read64(owner+16)!=0{unsafe{*(&u64(owner+16))=0}}
 api.drop(owner)
}
fn pc_cases(api PcApi,guard u64){
 space:=pc_word(api,' ');newline:=pc_word(api,'\n');empty:=pc_word(api,'')
 defer{api.drop(space.second);api.drop(newline.second);api.drop(empty.second)}
 zero:=pc_slots(api,0);pc_check(api,zero.owner,SwiftStringWords{~u64(0),guard},newline,guard,'\n');api.drop(zero.owner)
 for text in ['','plain','π/🎮/é','a\x00b','an independently held long String passed through Array Any']!{
  words:=pc_word(api,text);one:=pc_slots(api,1)
  unsafe{*(&SwiftStringWords(one.bytes))=words;*(&u64(one.bytes+24))=api.string_type}
  before:=read64(one.owner+8)
  pc_check(api,one.owner,SwiftStringWords{~u64(0),guard},empty,guard,text)
  assert read64(one.owner+8)==before&&read64(one.bytes)==words.first&&read64(one.bytes+8)==words.second
  pc_forget(api,one.owner);api.drop(words.second)
 }
 for sep_text in ['',' | ','π\x00🎮','long independently borrowed separator']!{for end_text in ['','\n','END\x00終']!{
  sep:=pc_word(api,sep_text);end:=pc_word(api,end_text);text:=pc_word(api,'hello 🎮')
  array:=pc_slots(api,8)
  unsafe{
   *(&SwiftStringWords(array.bytes))=text;*(&u64(array.bytes+24))=api.string_type
   *(&u64(array.bytes+32))=u64(i64(-9223372036854775807-1));*(&u64(array.bytes+56))=api.int_type
   *(&u64(array.bytes+64))=9223372036854775807;*(&u64(array.bytes+88))=api.int_type
   *(&u64(array.bytes+96))=1;*(&u64(array.bytes+120))=api.bool_type
   *(&u64(array.bytes+128))=0;*(&u64(array.bytes+152))=api.bool_type
   *(&u64(array.bytes+160))=u64('static\x00text'.str);*(&u64(array.bytes+168))=11;*(&u64(array.bytes+176))=2;*(&u64(array.bytes+184))=api.static_type
   *(&u64(array.bytes+216))=api.void_type;*(&u64(array.bytes+248))=api.merge_type
  }
  expected:=['hello 🎮','-9223372036854775808','9223372036854775807','true','false','static\x00text','()','keyCollision'].join(sep_text)+end_text
  pc_check(api,array.owner,sep,end,guard,expected)
  pc_forget(api,array.owner);api.drop(text.second);api.drop(sep.second);api.drop(end.second);unsafe{expected.free()}
 }}
 // The Swift literal borrows immutable bytes ending exactly at a guard.
 page:=usize(C.getpagesize());span:=u64(C.mmap(unsafe{nil},65536+page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert span!=~u64(0)
 source:=span+u64(page)
 C.memset(voidptr(source),`x`,65536);assert C.mprotect(voidptr(span),65536+page,C.PROT_READ)==0&&C.mprotect(voidptr(source+65536),page,C.PROT_NONE)==0
 words:=api.literal(unsafe{&u8(source)},65536,true);one:=pc_slots(api,1)
 unsafe{*(&SwiftStringWords(one.bytes))=words;*(&u64(one.bytes+24))=api.string_type}
 pc_check(api,one.owner,space,empty,guard,unsafe{tos(&u8(source),65536)})
 pc_forget(api,one.owner);api.drop(words.second);assert C.munmap(voidptr(span),65536+page*2)==0
}
fn pc_writer(api PcApi,owner u64,sep SwiftStringWords,end SwiftStringWords){
 call:=unsafe{PcPrint(voidptr(api.entry))}
 for _ in 0..32{call(owner,sep.first,sep.second,end.first,end.second)}
}
fn pc_parallel(api PcApi,guard u64){
 a:=pc_word(api,'left');b:=pc_word(api,'right');sep:=pc_word(api,'|');end:=pc_word(api,'\n');array:=pc_slots(api,2)
 unsafe{*(&SwiftStringWords(array.bytes))=a;*(&u64(array.bytes+24))=api.string_type;*(&SwiftStringWords(array.bytes+32))=b;*(&u64(array.bytes+56))=api.string_type}
 before:=read64(array.owner+8);capture:=pc_begin();mut workers:=[]thread{}
 for _ in 0..8{workers<<spawn pc_writer(api,array.owner,sep,end)};workers.wait()
 actual:=pc_end(capture);lines:=actual.split_into_lines();assert lines.len==256
 for line in lines{assert line=='left|right'}
 assert read64(array.owner+8)==before;unsafe{actual.free()}
 pc_forget(api,array.owner);for words in [a,b,sep,end]!{api.drop(words.second)}
}
fn pc_failed_stdout(api PcApi,guard u64){
 text:=pc_word(api,'failed stdout\n');array:=pc_slots(api,0);empty:=pc_word(api,'')
 assert C.fflush(C.stdout)==0;saved:=C.dup(1);assert saved>=0&&C.close(1)==0
 pc_invoke(api,array.owner,empty,text,guard)
 C.fflush(C.stdout);assert C.ferror(C.stdout)!=0;C.clearerr(C.stdout);assert C.dup2(saved,1)==1&&C.close(saved)==0
 api.drop(array.owner);api.drop(text.second);api.drop(empty.second)
}

fn pc_compat(code u64)PcApi{
 page:=u64(C.getpagesize())
 return PcApi{entry:runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss5print_9separator10terminatoryypd_S2StF')or{panic(err)},code:code,
  any:swift_any_full_metadata()+8,string_type:swift_string_metadata(),int_type:swift_integer_metadata(),
  bool_type:(swift_bool_metadata_arena_checked()or{panic(err)})+page+16,
  static_type:(swift_static_string_metadata_arena_checked()or{panic(err)})+page+16,
  void_type:swift_void_full_metadata()+8,merge_type:(swift_merge_error_metadata_arena_checked()or{panic(err)})+page+16,
  literal:swift_string_literal,allocate:swift_array_allocate,drop:swift_bridge_release}
}
fn pc_raw(api PcApi,fixture u64,guard u64){
 page:=u64(C.getpagesize());metadata:=fixture+32;swift_array_class_descriptor()
 unsafe{
  *(&u64(metadata-16))=u64(voidptr(swift_void_destroy));*(&u64(metadata))=metadata
  *(&u64(metadata+32))=2;*(&u64(metadata+64))=swift_array_class_descriptor();*(&u64(metadata+144))=api.any
 }
 write32(metadata+40,2);write32(metadata+48,32)
 mut loaded:=LoadedModule{image:macho.Image{segments:[macho.Segment{name:'__DATA_CONST',address:0,size:page,filesize:page,prot:1}]},layout:macho.Layout{base:0,size:page},base:fixture}
 mut runtime:=ModuleRuntime{modules:[&loaded]};assert module_runtime==unsafe{nil};module_runtime=unsafe{&runtime};defer{module_runtime=unsafe{nil}}
 assert C.mprotect(voidptr(fixture),usize(page),C.PROT_READ)==0
 text:=pc_word(api,'raw heap array');empty:=pc_word(api,'');owner:=swift_heap_allocate(metadata,64,7)
 unsafe{*(&u64(owner+16))=1;*(&u64(owner+24))=2;*(&SwiftStringWords(owner+32))=text;*(&u64(owner+56))=api.string_type}
 pc_check(api,owner,empty,empty,guard,'raw heap array')
 for offset in [u64(16),24]!{saved:=read64(owner+offset);unsafe{*(&u64(owner+offset))=~u64(0)};if _:=swift_print_console_render(owner,empty,empty){assert false};unsafe{*(&u64(owner+offset))=saved}}
 swift_heap_deallocate_uninitialized(owner,64,7);api.drop(text.second);api.drop(empty.second)
 assert C.mprotect(voidptr(fixture),usize(page),C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(fixture),0,usize(page))
}
fn pc_invalid(api PcApi,guard u64){
 empty:=pc_word(api,'');defer{api.drop(empty.second)}
 for owner in [u64(0),1,guard,~u64(0)]!{if _:=swift_print_console_render(owner,empty,empty){assert false}}
 wrong:=swift_array_buffer_allocate(1,api.int_type);if _:=swift_print_console_render(wrong,empty,empty){assert false};swift_bridge_release(wrong)
 array:=pc_slots(api,2);source_words:=u64(C.__builtin_alloca(16));owned_text:='first long value is released on later failure'
 unsafe{*(&SwiftStringWords(source_words))=swift_interpolation_init(64,0)}
 swift_string_append_bytes(source_words,u64(owned_text.str),u64(owned_text.len));text:=unsafe{*(&SwiftStringWords(source_words))}
 unsafe{*(&SwiftStringWords(array.bytes))=text;*(&u64(array.bytes+24))=api.string_type;*(&u64(array.bytes+56))=guard}
 before:=ios_runtime.swift_strings.len;references:=read64(text.second+8)
 for _ in 0..32{if _:=swift_print_console_render(array.owner,empty,empty){assert false};assert ios_runtime.swift_strings.len==before&&read64(text.second+8)==references}
 unsafe{*(&u64(array.bytes+56))=api.string_type;*(&SwiftStringWords(array.bytes+32))=empty}
 for value in [u64(1),3,~u64(0)]!{saved:=read64(array.owner+24);unsafe{*(&u64(array.owner+24))=value};if _:=swift_print_console_render(array.owner,empty,empty){assert false};unsafe{*(&u64(array.owner+24))=saved}}
 huge:=SwiftStringWords{first:0x1000000000100001,second:guard|0x8000000000000000}
 if _:=swift_print_console_render(array.owner,huge,empty){assert false}
 pc_forget(api,array.owner);api.drop(text.second)
 limit:=pc_slots(api,512);for i in 0..512{unsafe{*(&u64(limit.bytes+u64(i*32)+24))=api.void_type}}
 maximum:=swift_print_console_render(limit.owner,empty,empty)or{panic(err)};assert maximum.count==1024;C.free(voidptr(maximum.address));pc_forget(api,limit.owner)
 count:=pc_slots(api,513);if _:=swift_print_console_render(count.owner,empty,empty){assert false};pc_forget(api,count.owner)
 // Message cap: held long Strings must be released when their sum is too big.
 source:=u64(C.malloc(524288));assert source!=0;C.memset(voidptr(source),`x`,524288)
 words:=api.literal(unsafe{&u8(source)},524288,true);two:=pc_slots(api,2)
 for i in 0..2{unsafe{*(&SwiftStringWords(two.bytes+u64(i*32)))=words;*(&u64(two.bytes+u64(i*32)+24))=api.string_type}}
 newline:=pc_word(api,'\n');if _:=swift_print_console_render(two.owner,empty,newline){assert false}
 result:=swift_print_console_render(two.owner,empty,empty)or{panic(err)};assert result.count==1048576;C.free(voidptr(result.address))
 pc_forget(api,two.owner);api.drop(words.second);api.drop(newline.second);C.free(voidptr(source))
}
fn pc_resolve()u64{return runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss5print_9separator10terminatoryypd_S2StF')or{panic(err)}}
fn test_swift_print_console(){
 $if !arm64{return}
 page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page*3,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
 pc_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+64));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
 guard:=code+u64(page*2);assert C.mprotect(voidptr(guard),page,C.PROT_NONE)==0;defer{assert C.munmap(voidptr(code),page*3)==0}
 $if macos{
  core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);api:=PcApi{entry:u64(C.dlsym(core,c'$ss5print_9separator10terminatoryypd_S2StF')),code:code,
   any:u64(C.dlsym(core,c'$sypN'))+8,string_type:u64(C.dlsym(core,c'$sSSN')),int_type:u64(C.dlsym(core,c'$sSiN')),bool_type:u64(C.dlsym(core,c'$sSbN')),
   static_type:u64(C.dlsym(core,c'$ss12StaticStringVN')),void_type:u64(C.dlsym(core,c'$sytN'))+8,merge_type:u64(C.dlsym(core,c'$ss11_MergeErrorON')),
   literal:unsafe{PcLiteral(C.dlsym(core,c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC'))},allocate:unsafe{PcAllocate(C.dlsym(core,c'$ss27_allocateUninitializedArrayySayxG_BptBwlF'))},drop:unsafe{PcDrop(C.dlsym(core,c'swift_bridgeObjectRelease'))}}
  assert api.entry!=0&&api.any!=8;pc_cases(api,guard);pc_parallel(api,guard);pc_failed_stdout(api,guard)
  println('NATIVE-PRINT-CONSOLE: five-word borrowed public print ABI, Array Any, String/Int/Bool/StaticString/Void/enum formatting, Unicode/NUL separators and terminators, unused separator, guarded 64KiB literal, preserved x20/x21/x22 and protected x8, serialized concurrent messages, failed stdout returns')
 }
 for _ in 0..2{
  objc_start();mut publishers:=[]thread u64{};for _ in 0..8{publishers<<spawn pc_resolve()};entries:=publishers.wait();for entry in entries{assert entry==entries[0]}
  api:=pc_compat(code);assert api.entry==entries[0];pc_cases(api,guard);pc_parallel(api,guard);pc_failed_stdout(api,guard);pc_raw(api,code+u64(page),guard);pc_invalid(api,guard)
  assert runtime_symbol('/usr/lib/libSystem.B.dylib','_$ss5print_9separator10terminatoryypd_S2StF')==none&&runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss5print_9separator10terminatoryypd_S2StFExtra')==none
  assert ios_runtime.swift_strings.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.objects.len==0&&ios_runtime.live==0
  ios_runtime.swift_concurrency_retired=true;assert swift_print_console_symbol('_$ss5print_9separator10terminatoryypd_S2StF')==none
  if _:=swift_print_console_render(guard,SwiftStringWords{},SwiftStringWords{}){assert false}
  ios_runtime.swift_concurrency_retired=false;objc_stop();assert ios_runtime.swift_print_unlocked_retired&&swift_print_console_symbol('_$ss5print_9separator10terminatoryypd_S2StF')==none
 }
 println('IOS-PRINT-CONSOLE: native borrowed formatting/stdout comparison, registered typed and image-backed native Array Any, bounded complete messages before stdout lock, guarded unknown inputs and 512-item/1MiB limits, partial failure cleanup, preserved contexts/protected x8, failed stdout, eight cold publishers/writers and two drained lifetimes; general printing conformances and storage-class instantiation remain unsupported')
}
