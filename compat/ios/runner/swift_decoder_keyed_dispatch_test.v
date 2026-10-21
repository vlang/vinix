// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.mincore(voidptr,usize,&u8)i32
$if macos{
 #include <mach/mach.h>
 fn C.mach_task_self()u32
 fn C.vm_region_64(u32,&u64,&u64,i32,&i32,&u32,&u32)i32
 fn C.mach_port_deallocate(u32,u32)i32
}
type DkdProbe=fn(u64,u64,u64,u64,u64,u64,u64)
type DkdSign=fn(u64,u64)u64
fn dkd_pair(load bool,vector bool,a u32,b u32,base u32,offset int)u32{
 width:=if vector{16}else{8};assert offset%width==0&&offset>=0&&offset/width<64
 return (if vector{u32(0xad000000)}else{u32(0xa9000000)})|(if load{u32(0x00400000)}else{u32(0)})|(u32(offset/width)<<15)|(b<<10)|(base<<5)|a
}
fn dkd_store(register u32,base u32,offset u32)u32{assert offset%8==0;return 0xf9000000|((offset/8)<<10)|(base<<5)|register}
fn dkd_mov(register u32,value u32)u32{assert value<=65535;return 0xd2800000|(value<<5)|register}
fn dkd_code(code u64){
 mut ops:=[u32(0xa9ba7bfd)]
 for i in 0..5{ops<<dkd_pair(false,false,u32(19+i*2),u32(20+i*2),31,16+i*16)}
 // C(entry,table,Self,result,observations,returned,incoming) -> Swift.
 ops<<[u32(0xaa0003f0),0xaa0203f4,0xaa0503f3,0xaa0603f5,0xaa0303e8,0xaa0103f1,0xaa0403e7,0xaa1103e4,
  dkd_mov(22,0x5222),u32(0x91004280),0x91008281,0x9100c282,0x91010283,dkd_mov(5,0x5105),dkd_mov(6,0x5106)]
 pc:=code+u64(ops.len*4);distance:=u32(code+640-pc);ops<<u32(0x10000017|((distance&3)<<29)|((distance>>2)<<5))
 for i in 0..4{ops<<dkd_pair(true,true,u32(i*2),u32(i*2+1),23,i*32)}
 ops<<u32(0xd63f0200)
 ops<<[dkd_pair(false,false,0,1,19,0),dkd_pair(false,false,20,21,19,16),dkd_pair(false,false,22,8,19,32)]
 for i in 0..4{ops<<dkd_pair(false,true,u32(i*2),u32(i*2+1),19,48+i*32)}
 for i in 0..5{ops<<dkd_pair(true,false,u32(19+i*2),u32(20+i*2),31,16+i*16)}
 ops<<[u32(0xa8c67bfd),0xd65f03c0];assert ops.len*4<=256
 for i,op in ops{write32(code+u64(i*4),op)}
 for variant in 0..2{
  mut method:=[]u32{}
  for register in u32(0)..9{method<<dkd_store(register,7,register*8)}
  method<<[dkd_pair(false,false,20,21,7,72),dkd_store(22,7,88)]
  for i in 0..4{method<<dkd_pair(false,true,u32(i*2),u32(i*2+1),7,96+i*32)}
  method<<[dkd_mov(9,u32(0x6000+variant)),dkd_store(9,7,272),u32(0xf9407ce9),0xb4000069,0xf94080ea,0xf900010a,
   dkd_pair(true,false,0,1,7,224),u32(0xf94078f5),0xd65f03c0]
  assert method.len*4<=128;for i,op in method{write32(code+256+u64(variant*128+i*4),op)}
 }
 write32(code+512,0xdac10020);write32(code+516,0xd65f03c0)
 for i in 0..16{unsafe{*(&u64(code+640+u64(i*8)))=u64(0x12340000+i)}}
 C.__builtin___clear_cache(voidptr(code),voidptr(code+768))
}
fn dkd_case(entry u64,table u64,self u64,result u64,guard u64,probe DkdProbe,variant int,bits u64,incoming u64,thrown u64){
 mut observed:=[36]u64{};mut returned:=[26]u64{};mut local:=u64(0xcafe)
 destination:=if thrown!=0{guard}else if result==0{u64(unsafe{&local})}else{result}
 observed[28]=bits;observed[29]=~bits;observed[30]=thrown;observed[31]=u64(thrown==0);observed[32]=bits
 observed[33]=0xcafe;observed[35]=0xbeef;returned[0]=0xcafe;returned[23]=0xbeef;returned[25]=0xabcd
 probe(entry,table,self,destination,u64(unsafe{&observed[0]}),u64(unsafe{&returned[1]}),incoming)
 for i in 0..4{assert observed[i]==self+u64(16+i*16)}
 assert observed[4]==table&&observed[5]==0x5105&&observed[6]==0x5106&&observed[7]==u64(unsafe{&observed[0]})&&observed[8]==destination
 assert observed[9]==self&&observed[10]==incoming&&observed[11]==0x5222&&observed[34]==u64(0x6000+variant)
 assert returned[1]==bits&&returned[2]==~bits&&returned[3]==self&&returned[4]==thrown&&returned[5]==0x5222&&returned[6]==destination
 for i in 0..16{assert observed[12+i]==u64(0x12340000+i)&&returned[7+i]==u64(0x12340000+i)}
 if thrown==0{assert read64(destination)==bits}
 assert observed[28]==bits&&observed[29]==~bits&&observed[30]==thrown&&observed[31]==u64(thrown==0)&&observed[32]==bits
 assert observed[33]==0xcafe&&observed[35]==0xbeef&&returned[0]==0xcafe&&returned[23]==0xbeef&&returned[25]==0xabcd
}
fn dkd_worker(entry u64,table u64,self u64,guard u64,probe DkdProbe,variant int){
 for i in 0..64{dkd_case(entry,table,self,0,guard,probe,variant,u64(i)|0x8000000000000000,u64(i%2)*0xab21,u64(i%3)*0xde21)}
}
fn dkd_spans(entry u64,code u64,native bool){
 page:=usize(C.getpagesize());probe:=unsafe{DkdProbe(voidptr(code))}
 for placement in 0..4{for variant in 0..2{
  table_pages:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
  result_pages:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
  assert table_pages!=~u64(0)&&result_pages!=~u64(0)
  assert C.mprotect(voidptr(table_pages+u64(page)),page,C.PROT_READ|C.PROT_WRITE)==0&&C.mprotect(voidptr(result_pages+u64(page)),page,C.PROT_READ|C.PROT_WRITE)==0
  slot:=table_pages+u64(page)+if placement&1!=0{u64(page)-8}else{u64(0)}
  result:=result_pages+u64(page)+if placement&2!=0{u64(page)-8}else{u64(0)}
  mut target:=code+256+u64(variant*128)
  $if macos{if native{target=unsafe{DkdSign(voidptr(code+512))}(target,slot|(u64(0x6f72)<<48))}}
  unsafe{*(&u64(slot))=target};assert C.mprotect(voidptr(table_pages+u64(page)),page,C.PROT_READ)==0
  for bits in [u64(0),1,0x7fffffffffffffff,0x8000000000000000,~u64(0)]!{for incoming in [u64(0),0xab21]!{for thrown in [u64(0),0xde21]!{
   unsafe{*(&u64(result))=0xfeed};dkd_case(entry,slot-24,table_pages,result,result_pages,probe,variant,bits,incoming,thrown)
   if thrown!=0{assert read64(result)==0xfeed}
  }}}
  mut workers:=[]thread{};for _ in 0..8{workers<<spawn dkd_worker(entry,slot-24,table_pages,result_pages,probe,variant)};workers.wait();unsafe{workers.free()}
  assert read64(slot)==target
  assert C.munmap(voidptr(table_pages),page*3)==0&&C.munmap(voidptr(result_pages),page*3)==0
 }}
}
fn dkd_mapping(address u64,mapped bool){
 $if macos{
  mut start:=address;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object:=u32(0);task:=C.mach_task_self()
  status:=C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe{&info[0]},&count,&object)
  if mapped{assert status==0&&start<=address&&address+8<=start+size&&info[0]==C.PROT_READ|C.PROT_EXEC}else{assert status!=0||start>address}
  if object!=0{assert C.mach_port_deallocate(task,object)==0}
 }$else{
  mut found:=false;for line in (os.read_file('/proc/self/maps')or{panic(err)}).split_into_lines(){fields:=line.fields();if fields.len<2{continue};range:=fields[0].split('-');if range.len!=2{continue};start:=strconv.parse_uint(range[0],16,64)or{panic(err)};end:=strconv.parse_uint(range[1],16,64)or{panic(err)};if address>=start&&address<end{assert mapped&&address+8<=end&&fields[1]=='r-xp';found=true;break}};assert found==mapped
 }
}
fn dkd_publish()u64{mut entry:=u64(0);for _ in 0..128{entry=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss7DecoderP9container7keyedBys22KeyedDecodingContainerVyqd__Gqd__m_tKs9CodingKeyRd__lFTj')or{panic(err)}};return entry}
fn test_swift_decoder_keyed_dispatch(){
 $if !arm64{return}
 page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)
 dkd_code(code);assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
 $if macos{
  core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert core!=unsafe{nil};entry:=u64(C.dlsym(core,c'$ss7DecoderP9container7keyedBys22KeyedDecodingContainerVyqd__Gqd__m_tKs9CodingKeyRd__lFTj'));assert entry!=0
  dkd_spans(entry,code,true)
  println('NATIVE-DECODER-KEYED-DISPATCH: Decoder slot24, unchanged x0-x8 and vector arguments, borrowed protected x20 and exact incoming/returned x21, preserved x22, two supplied witnesses, exact guarded eight-byte slot/results, protected absent result and eight concurrent callers')
 }
 assert swift_decoder_keyed_dispatch_symbol('_$ss7DecoderP9container7keyedBys22KeyedDecodingContainerVyqd__Gqd__m_tKs9CodingKeyRd__lFTj')==none
 for order in 0..2{
  objc_start();assert ios_runtime.swift_hash_code==0
  for symbol in ['_$ss7DecoderP9container7keyedBys22KeyedDecodingContainerVyqd__Gqd__m_tKs9CodingKeyRd__lFTjExtra','$ss7DecoderP9container7keyedBys22KeyedDecodingContainerVyqd__Gqd__m_tKs9CodingKeyRd__lFTj','_$ss7EncoderP9container7keyedBys22KeyedEncodingContainerVyqd__Gqd__m_ts9CodingKeyRd__lFTj']!{assert swift_decoder_keyed_dispatch_symbol(symbol)==none}
  for library in ['/usr/lib/libSystem.B.dylib','/usr/lib/swift/libswiftFoundation.dylib','/System/Library/Frameworks/Foundation.framework/Foundation']!{assert runtime_symbol(library,'_$ss7DecoderP9container7keyedBys22KeyedDecodingContainerVyqd__Gqd__m_tKs9CodingKeyRd__lFTj')==none};assert ios_runtime.swift_hash_code==0
  ios_runtime.swift_concurrency_retired=true;assert swift_decoder_keyed_dispatch_symbol('_$ss7DecoderP9container7keyedBys22KeyedDecodingContainerVyqd__Gqd__m_tKs9CodingKeyRd__lFTj')==none&&ios_runtime.swift_hash_code==0;ios_runtime.swift_concurrency_retired=false
  if order==1{swift_hash_entry(1728)};mut publishers:=[]thread u64{};for _ in 0..8{publishers<<spawn dkd_publish()};entries:=publishers.wait();entry:=entries[0];for candidate in entries{assert candidate==entry};unsafe{publishers.free();entries.free()}
  assert entry==ios_runtime.swift_hash_code+1792;dkd_mapping(entry,true);dkd_spans(entry,code,false)
  assert ios_runtime.live==0&&ios_runtime.objects.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_strings.len==0
  ios_runtime.swift_concurrency_retired=true;assert swift_decoder_keyed_dispatch_symbol('_$ss7DecoderP9container7keyedBys22KeyedDecodingContainerVyqd__Gqd__m_tKs9CodingKeyRd__lFTj')==none
  objc_stop();assert ios_runtime.swift_hash_code==0;dkd_mapping(entry,false)
 }
 assert C.munmap(voidptr(code),page)==0
 println('IOS-DECODER-KEYED-DISPATCH: real supplied Decoder witness with native scalar/vector/indirect/error forwarding, protected values/types/arguments and exact slot/result spans, no ARC/result/error ownership work, shared sealed dispatch page, eight publishers/callers and both publication orders, two drained/unmapped lifetimes; JSON backend remains unsupported')
}
