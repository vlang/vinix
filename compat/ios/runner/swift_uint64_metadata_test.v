// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.mincore(voidptr,usize,&u8)i32
$if macos {
 #include <mach/mach.h>
 fn C.mach_task_self()u32
 fn C.vm_region_64(u32,&u64,&u64,i32,&i32,&u32,&u32)i32
 fn C.mach_port_deallocate(u32,u32)i32
}
type UnProbe=fn(u64,u64,u64,u64,u64,&u64,u64)
type UnAccess=fn(u64)SwiftAssociatedMetadata
struct UnApi{native bool metadata u64 descriptor u64 accessor u64 integer u64 witness u64 code u64}
fn un_relative(p u64)u64{return u64(i64(p)+i64(i32(read32(p))))}
fn un_entry(api UnApi,offset u64)u64{entry:=read64(api.witness+offset);return if api.native{entry&0x0000ffffffffffff}else{entry}}
fn un_emit(code u64){
 for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0503f3,0xaa0403f0,0xaa0603f4,
  u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0603e8,0xd63f0200,
  0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
}
fn un_call(api UnApi,entry u64,a u64,b u64,c u64,d u64,guard u64)[2]u64{
 mut result:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
 unsafe{UnProbe(voidptr(api.code))(a,b,c,d,entry,&result[1],guard)}
 assert result[0]==0xcafe&&result[6]==0xbeef&&result[3]==guard&&result[4]==0x5121&&result[5]==0x5222
 return [result[1],result[2]]!
}
fn un_layout(api UnApi,guard u64){
 assert api.metadata!=api.integer&&read64(api.metadata)==0x200&&read64(api.metadata+8)==api.descriptor&&read32(api.metadata+16)==0
 assert api.witness==(read64(api.integer-8)&if api.native{u64(0x0000ffffffffffff)}else{~u64(0)})
 assert read64(api.witness+64)==8&&read64(api.witness+72)==8&&read64(api.witness+80)==7
 assert read32(api.descriptor)==0x51&&read32(api.descriptor+20)==1&&read32(api.descriptor+24)==2
 assert unsafe{(&char(un_relative(api.descriptor+8))).vstring()}=='UInt64'
 module_descriptor:=un_relative(api.descriptor+4);assert read32(module_descriptor)==0&&unsafe{(&char(un_relative(module_descriptor+8))).vstring()}=='Swift'
 assert un_relative(api.descriptor+12)==api.accessor
 if !api.native{assert module_descriptor==un_relative(read64(api.integer+8)+4)&&read32(api.descriptor+16)==0}
 access:=unsafe{UnAccess(voidptr(api.accessor))}
 for request in [u64(0),0x3f,0xff,0x100,0x13f,0x1ff,~u64(0)]!{
  response:=access(request);assert response.metadata==api.metadata&&response.state==0
  result:=un_call(api,api.accessor,request,guard,guard,guard,guard);assert result==[api.metadata,u64(0)]!
 }
}
fn un_values(api UnApi,span u64,guard u64){
 page:=usize(C.getpagesize());middle:=span+u64(page);source:=u64(C.malloc(8));assert source!=0;defer{C.free(voidptr(source))}
 for at_end in [false,true]!{
  value:=middle+if at_end{u64(page)-8}else{u64(0)}
  for bits in [u64(0),1,0x7fffffffffffffff,0x8000000000000000,~u64(0)]!{
   assert C.mprotect(voidptr(middle),page,C.PROT_READ|C.PROT_WRITE)==0;unsafe{*(&u64(value))=bits}
   assert C.mprotect(voidptr(middle),page,C.PROT_READ)==0
   for offset in [u64(0),16,24,32,40]!{
    result:=un_call(api,un_entry(api,offset),source,value,api.metadata,guard,guard);assert result[0]==source&&read64(source)==bits
    alias:=un_call(api,un_entry(api,offset),source,source,api.metadata,guard,guard);assert alias[0]==source&&read64(source)==bits
   }
   un_call(api,un_entry(api,8),value,api.metadata,guard,guard,guard);assert read64(value)==bits
   assert C.mprotect(voidptr(middle),page,C.PROT_READ|C.PROT_WRITE)==0
   for offset in [u64(0),16,24,32,40]!{result:=un_call(api,un_entry(api,offset),value,source,api.metadata,guard,guard);assert result[0]==value&&read64(value)==bits}
  }
 }
 // Zero-empty-case operations and POD destruction touch no value storage.
 assert u32(un_call(api,un_entry(api,48),guard,0,api.metadata,guard,guard)[0])==0
 un_call(api,un_entry(api,56),guard,0,0,api.metadata,guard);un_call(api,un_entry(api,8),guard,api.metadata,guard,guard,guard)
 // ASan sees exactly nine initialized bytes, including the external tag.
 bytes:=u64(C.malloc(9));assert bytes!=0;defer{C.free(voidptr(bytes))}
 for cases in [u32(1),255,256,0x7fffffff,0x80000000,0xffffffff]!{for tag in [u32(0),1,255,256,0x7fffffff,0x80000000,0xffffffff]!{
  if tag>cases{continue};C.memset(voidptr(bytes),0xa5,9)
  un_call(api,un_entry(api,56),bytes,tag,cases,api.metadata,guard)
  assert u32(un_call(api,un_entry(api,48),bytes,cases,api.metadata,guard,guard)[0])==tag
  for i in u64(0)..8{assert unsafe{*(&u8(bytes+i))}==if tag==0{u8(0xa5)}else{u8(u64(tag-1)>>u32(i*8))}}
  assert unsafe{*(&u8(bytes+8))}==u8(tag!=0)
 }}
}
fn un_protection(address u64,executable bool){
 $if macos{
  mut start:=address;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object:=u32(0);task:=C.mach_task_self()
  assert C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe{&info[0]},&count,&object)==0
  assert start<=address&&address<start+size&&info[0]==(C.PROT_READ|if executable{C.PROT_EXEC}else{0});if object!=0{assert C.mach_port_deallocate(task,object)==0}
 }$else{
  mut found:=false;for line in (os.read_file('/proc/self/maps')or{panic(err)}).split_into_lines(){fields:=line.fields();if fields.len<2{continue};range:=fields[0].split('-');if range.len!=2{continue};start:=strconv.parse_uint(range[0],16,64)or{panic(err)};end:=strconv.parse_uint(range[1],16,64)or{panic(err)};if address>=start&&address<end{assert fields[1]==if executable{'r-xp'}else{'r--p'};found=true;break}};assert found
 }
}
fn un_resolve()u64{return runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss6UInt64VMn')or{panic(err)}}
fn un_compat(code u64)UnApi{
 metadata:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss6UInt64VN')or{panic(err)}
 return UnApi{metadata:metadata,descriptor:un_resolve(),accessor:runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss6UInt64VMa')or{panic(err)},integer:swift_integer_metadata(),witness:read64(metadata-8),code:code}
}
fn un_symbolic(api UnApi,span u64){
 page:=usize(C.getpagesize());middle:=span+u64(page);name:=middle+u64(page)-5;slot:=middle+64;guard:=span+u64(page)*2
 assert C.mprotect(voidptr(middle),page,C.PROT_READ|C.PROT_WRITE)==0;unsafe{*(&u64(slot))=api.descriptor}
 for tag in [u8(1),2]!{
  unsafe{*(&u8(name))=tag};target:=if tag==1{api.descriptor}else{slot};delta:=i64(target)-i64(name+1);assert i64(i32(delta))==delta
  for i in u64(0)..4{unsafe{*(&u8(name+1+i))=u8(u32(i32(delta))>>(i*8))}}
  assert C.mprotect(voidptr(middle),page,C.PROT_READ)==0
  for request in [u64(0),0x3f,0xff,0x100,0x13f,0x1ff]!{
   assert swift_mangled_lookup_request_checked(request,name,5,guard,guard)or{panic(err)}==api.metadata
   assert swift_mangled_state_lookup_checked(request,name,5,guard,guard)or{panic(err)}==api.metadata
  }
  assert C.mprotect(voidptr(middle),page,C.PROT_READ|C.PROT_WRITE)==0
 }
}
fn un_consumers(api UnApi){
 array:=swift_array_allocate(17,api.metadata);assert ios_runtime.swift_arrays[array.owner].element==api.metadata&&ios_runtime.swift_arrays[array.owner].stride==8
 for i in u64(0)..17{unsafe{*(&u64(array.bytes+i*8))=0x8000000000000000|i}};for i in u64(0)..17{assert read64(array.bytes+i*8)==(0x8000000000000000|i)};swift_bridge_release(array.owner)
 optional:=swift_optional_access_checked(0,api.metadata)or{panic(err)};assert read64(optional.metadata+16)==api.metadata&&read64(read64(optional.metadata-8)+64)==9
 mut value:=[u64(0xffffffffffffffff),0]!
 address:=u64(unsafe{&value[0]});swift_optional_inject(address,0,optional.metadata);assert swift_optional_tag(address,optional.metadata)==0&&value[0]==~u64(0)
 swift_optional_inject(address,1,optional.metadata);assert swift_optional_tag(address,optional.metadata)==1;swift_optional_destroy(address,optional.metadata)
 mut source:=[u64(0xffffffffffffffff),0,0,api.metadata]!
 mut destination:=[u64(0),0,0,0]!
 assert swift_any_copy_checked(u64(unsafe{&destination[0]}),u64(unsafe{&source[0]}))or{panic(err)}==u64(unsafe{&destination[0]})
 assert destination[0]==~u64(0)&&destination[3]==api.metadata;swift_any_destroy_checked(u64(unsafe{&destination[0]}))or{panic(err)}
}
fn un_reader()u64{mut first:=u64(0);for _ in 0..128{candidate:=un_resolve();if first==0{first=candidate};assert first==candidate};return first}
__global un_teardown_calls=0
fn un_teardown(_object u64,_selector &char){assert ios_runtime.swift_concurrency_retired;descriptor:=un_resolve();metadata:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss6UInt64VN')or{panic(err)};assert read64(metadata+8)==descriptor&&swift_mangled_nominal(descriptor)or{panic(err)}==metadata;un_teardown_calls++}
fn test_swift_uint64_metadata(){
 $if !arm64{return}
 page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));span:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)&&span!=~u64(0)
 un_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+68));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;guard:=span+u64(page)*2
 defer{assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(span),page*3)==0}
 $if macos{
  core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);metadata:=u64(C.dlsym(core,c'$ss6UInt64VN'));api:=UnApi{native:true,metadata:metadata,descriptor:u64(C.dlsym(core,c'$ss6UInt64VMn')),accessor:u64(C.dlsym(core,c'$ss6UInt64VMa')),integer:u64(C.dlsym(core,c'$sSiN')),witness:read64(metadata-8)&0x0000ffffffffffff,code:code}
  assert api.metadata!=0&&api.descriptor!=0&&api.accessor!=0;un_layout(api,guard);un_values(api,span,guard)
  println('NATIVE-UINT64-METADATA: distinct UInt64 identity and shared Int POD witnesses, every complete accessor request, eight-byte copies/aliases and nine-byte single-payload enums at UInt32 boundaries, protected absent values/read-only guarded words, preserved x20/x21/x22 and protected x8')
 }
 assert swift_uint64_metadata_symbol('_$ss6UInt64VMn')==none
 for order in 0..2{
  objc_start();assert ios_runtime.swift_integer_arena==0;ios_runtime.swift_concurrency_retired=true;assert swift_uint64_metadata_symbol('_$ss6UInt64VMn')==none&&ios_runtime.swift_integer_arena==0;ios_runtime.swift_concurrency_retired=false
  for symbol in ['_$ss6UInt64VMnExtra','$ss6UInt64VMn','_$ss6UInt64VWV','_$ss6UInt32VMn','_$ss6UInt64VSHsWP']!{assert swift_uint64_metadata_symbol(symbol)==none}
  for library in ['/usr/lib/libSystem.B.dylib','/System/Library/Frameworks/SwiftUI.framework/SwiftUI','/System/Library/Frameworks/Foundation.framework/Foundation']!{assert runtime_symbol(library,'_$ss6UInt64VMn')==none};assert ios_runtime.swift_integer_arena==0
  if order==1{swift_integer_metadata()};mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn un_reader()};entries:=workers.wait();for entry in entries{assert entry==entries[0]}
  api:=un_compat(code);base:=ios_runtime.swift_integer_arena;assert api.descriptor==entries[0]&&api.metadata==base+u64(page)+904&&api.descriptor==base+u64(page)+936&&api.accessor==base+416
  un_layout(api,guard);un_values(api,span,guard);un_symbolic(api,span);un_consumers(api);un_protection(base,true);un_protection(api.metadata,false)
  assert ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.objects.len==0&&ios_runtime.live==0
  cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixUInt64MetadataTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(un_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
  before:=un_teardown_calls;ios_runtime.swift_concurrency_retired=true;assert un_resolve()==api.descriptor;objc_stop();assert un_teardown_calls==before+1&&ios_runtime.swift_integer_arena==0&&swift_uint64_metadata_symbol('_$ss6UInt64VMn')==none&&ios_runtime.live==0&&ios_runtime.objects.len==0
  $if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1}
 }
 println('IOS-UINT64-METADATA: native nominal/accessor/POD differential, canonical shared integer arena with distinct UInt64 identity, direct/indirect symbolic lookup, Array/Optional/Any consumers, eight cold readers and both publication orders, sealed pages, guarded bounds/contexts and two drained/unmapped callback lifetimes; unsigned conformances and arithmetic/formatting exports remain separate')
}
