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
type RnAccess=fn(u64,u64,u64,u64)SwiftAssociatedMetadata
fn rn_relative(field u64)u64{return u64(i64(field)+i64(i32(read32(field))))}
fn rn_text(address u64)string{return unsafe{(&char(address)).vstring()}}
fn rn_signature(descriptor u64,protocol u64,native bool){
 // Compare the stable copyable signature. New native runtimes additionally
 // describe inverted protocols; this nominal-only export omits those trailers.
 assert read32(descriptor)&~u32(0x20)==0xd2&&rn_text(rn_relative(descriptor+8))=='Result'
 parent:=rn_relative(descriptor+4);assert read32(parent)==0&&rn_text(rn_relative(parent+8))=='Swift'
 assert read32(descriptor+20)==0x05000002&&read32(descriptor+24)==0
 assert read32(descriptor+36)&0xffff==2&&read32(descriptor+40)&0xffff==3&&read32(descriptor+44)==0x8080
 assert read32(descriptor+48)==0x80&&rn_text(rn_relative(descriptor+52))=='q_'
 reference:=rn_relative(descriptor+56);target:=if reference&1!=0{read64(reference-1)}else{reference}
 assert target==protocol&&rn_text(rn_relative(target+8))=='Error'&&read32(target)==0x70043
 assert rn_relative(descriptor+12)!=0
 if !native{
  assert read32(descriptor)==0xd2&&read32(descriptor+36)==0x10002&&read32(descriptor+40)==3
  for offset in [u64(16),28,32]!{assert read32(descriptor+offset)==0}
 }
}
fn rn_resolve()u64{return runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss6ResultOMn')or{panic(err)}}
fn rn_protection(address u64,executable bool){
 $if macos{
  mut start:=address;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object:=u32(0);task:=C.mach_task_self()
  assert C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe{&info[0]},&count,&object)==0
  assert start<=address&&address<start+size&&info[0]==(C.PROT_READ|if executable{C.PROT_EXEC}else{0})
  if object!=0{assert C.mach_port_deallocate(task,object)==0}
 }$else{
  mut found:=false
  for line in (os.read_file('/proc/self/maps')or{panic(err)}).split_into_lines(){
   fields:=line.fields();if fields.len<2{continue};range:=fields[0].split('-');if range.len!=2{continue}
   start:=strconv.parse_uint(range[0],16,64)or{panic(err)};end:=strconv.parse_uint(range[1],16,64)or{panic(err)}
   if address>=start&&address<end{assert fields[1]==if executable{'r-xp'}else{'r--p'};found=true;break}
  };assert found
 }
}
fn rn_symbolic(descriptor u64){
 page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=~u64(0)
 guard:=base+u64(page);name:=guard-5;slot:=base+64
 unsafe{*(&u64(slot))=descriptor};assert C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
 for tag in [u8(1),2]!{
  unsafe{*(&u8(name))=tag};target:=if tag==1{descriptor}else{slot};delta:=i64(target)-i64(name+1);assert i64(i32(delta))==delta
  for i in u64(0)..4{unsafe{*(&u8(name+1+i))=u8(u32(i32(delta))>>(i*8))}}
  assert C.mprotect(voidptr(base),page,C.PROT_READ)==0
  for request in [u64(0),0x3f,0xff,0x100,0x13f,0x1ff]!{for _ in 0..32{
   if _:=swift_mangled_state_lookup_checked(request,name,5,guard,guard){assert false}else{assert err.msg()=='iOS: unsupported Swift symbolic context descriptor'}
  }}
  assert C.mprotect(voidptr(base),page,C.PROT_READ|C.PROT_WRITE)==0
 }
 assert C.munmap(voidptr(base),page*2)==0
}
fn rn_access(descriptor u64){
 page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=~u64(0)
 accessor:=unsafe{RnAccess(voidptr(rn_relative(descriptor+12)))}
 for request in [u64(0),0xff,0x1ff,~u64(0)]!{
  mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
  if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);accessor(request,guard,guard,guard);C._exit(0)}
  C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0
  for{assert length<bytes.len;count:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if count==0{break};if count<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert count>0;length+=int(count)}
  C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
  output:=unsafe{tos(&bytes[0],length)};assert output.contains('iOS: Swift Result generic instantiation is not implemented')&&!output.contains('runtime error:')&&!output.contains('AddressSanitizer')
 }
 assert C.munmap(voidptr(guard),page)==0
}
fn rn_reader()u64{mut first:=u64(0);for _ in 0..128{descriptor:=rn_resolve();if first==0{first=descriptor};assert first==descriptor&&read32(descriptor)==0xd2};return first}
__global rn_teardown_calls=0
fn rn_teardown(_object u64,_selector &char){assert ios_runtime.swift_concurrency_retired;descriptor:=rn_resolve();assert rn_text(rn_relative(descriptor+8))=='Result';assert rn_relative(descriptor+56)==ios_runtime.swift_error_arena+u64(C.getpagesize())+240;rn_teardown_calls++}
fn test_swift_result_nominal(){
 $if !arm64{return}
 $if macos{
  core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);descriptor:=u64(C.dlsym(core,c'$ss6ResultOMn'));protocol:=u64(C.dlsym(core,c'$ss5ErrorMp'));assert descriptor!=0&&protocol!=0
  rn_signature(descriptor,protocol,true)
  println('NATIVE-RESULT-NOMINAL: Swift Result generic enum, two payloads/no empty cases, payload-size word five, Success and Failure key arguments, canonical Failure Error witness; stable copyable signature compared separately from modern invertible-protocol trailers')
 }
 assert swift_result_nominal_symbol('_$ss6ResultOMn')==none
 page:=usize(C.getpagesize())
 for order in 0..2{
  objc_start();assert ios_runtime.swift_error_arena==0
  ios_runtime.swift_concurrency_retired=true;assert swift_result_nominal_symbol('_$ss6ResultOMn')==none&&ios_runtime.swift_error_arena==0;ios_runtime.swift_concurrency_retired=false
  for symbol in ['_$ss6ResultOMa','_$ss6ResultON','_$ss6ResultOWV','_$ss6ResultOMnExtra','$ss6ResultOMn']!{assert swift_result_nominal_symbol(symbol)==none}
  for library in ['/usr/lib/libSystem.B.dylib','/System/Library/Frameworks/SwiftUI.framework/SwiftUI','/System/Library/Frameworks/Foundation.framework/Foundation']!{assert runtime_symbol(library,'_$ss6ResultOMn')==none};assert ios_runtime.swift_error_arena==0
  if order==1{runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss5ErrorMp')or{panic(err)}}
  mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn rn_reader()};entries:=workers.wait();for entry in entries{assert entry==entries[0]}
  descriptor:=entries[0];base:=ios_runtime.swift_error_arena;protocol:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss5ErrorMp')or{panic(err)}
  assert descriptor==base+u64(page)+896&&rn_relative(descriptor+4)==base+u64(page)+320&&rn_relative(descriptor+12)==base+640
  rn_signature(descriptor,protocol,false);rn_protection(base,true);rn_protection(descriptor,false);rn_symbolic(descriptor);rn_access(descriptor)
  assert ios_runtime.swift_optional_arena==0&&ios_runtime.swift_array_arena==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.objects.len==0&&ios_runtime.live==0
  cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixResultNominalTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(rn_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls))
  before:=rn_teardown_calls;ios_runtime.swift_concurrency_retired=true;assert rn_resolve()==descriptor;objc_stop()
  assert rn_teardown_calls==before+1&&ios_runtime.swift_error_arena==0&&ios_runtime.objects.len==0&&ios_runtime.live==0&&swift_result_nominal_symbol('_$ss6ResultOMn')==none
  $if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1}
 }
 println('IOS-RESULT-NOMINAL: eight cold readers and both Error publication orders, canonical shared Swift/Error identities, sealed descriptor/accessor, protected direct/indirect symbolic rejection and generic arguments, explicit specialization diagnostic, no fabricated metadata, callback borrow and two drained/unmapped lifetimes; generic Result values and invertible-protocol trailers remain unsupported')
}
