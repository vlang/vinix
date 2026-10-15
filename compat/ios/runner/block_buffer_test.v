// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
struct BBAPI { native bool cm u64 cf u64 }
struct BBContext {mut: base u64 allocations int frees int fail bool reentrant_object u64 }
type BBCreate=fn(u64,u64,u64,u64,u64,u64,u64,u32,&u64)i32
type BBPointer=fn(u64,u64,&u64,&u64,&u64)i32
type BBReplace=fn(u64,u64,u64,u64)i32
type BBCopy=fn(u64,u64,u64,u64)i32
type BBFill=fn(u8,u64,u64,u64)i32
type BBQuery=fn(u64)u64
type BBType=fn()u64
type BBStatus=fn(u64)i32
type BBDrop=fn(u64)
type BBReference=fn(u64,u64,u64,u64,u32,&u64)i32
type BBContiguous=fn(u64,u64,u64)u8
type BBEmpty=fn(u64)u8
fn bb_symbol(api BBAPI,name string,cf bool)u64{
 if api.native{p:=u64(C.dlsym(unsafe{voidptr(if cf{api.cf}else{api.cm})},unsafe{&char(name.str+1)}));assert p!=0,name;return p}
 return runtime_symbol(if cf{'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'}else{'/System/Library/Frameworks/CoreMedia.framework/CoreMedia'},name)or{panic(err)}
}
fn bb_query(api BBAPI,name string,object u64,cf bool)u64{return unsafe{BBQuery(voidptr(bb_symbol(api,name,cf)))(object)}}
fn bb_drop(api BBAPI,object u64){unsafe{BBDrop(voidptr(bb_symbol(api,'_CFRelease',true)))(object)}}
fn bb_callback_reader(object u64){assert cm_block_length(object)==8}
fn bb_allocate(context u64,size u64)u64{mut c:=unsafe{&BBContext(context)};assert size==32;c.allocations++;if c.fail{return 0};if c.reentrant_object!=0{worker:=spawn bb_callback_reader(c.reentrant_object);worker.wait();assert cm_block_assure(c.reentrant_object)==-12707};c.base=u64(C.malloc(usize(size)));assert c.base!=0;C.memset(unsafe{voidptr(c.base)},0x31,usize(size));return c.base}
fn bb_free(context u64,memory u64,size u64){mut c:=unsafe{&BBContext(context)};assert size==32&&memory==c.base&&c.frees==0;c.frees++;C.free(unsafe{voidptr(memory)})}
fn bb_wire(context u64,allocate bool,release bool,version u32)[28]u8{
 mut wire:=[28]u8{};a:=if allocate{u64(unsafe{voidptr(bb_allocate)})}else{u64(0)};f:=if release{u64(unsafe{voidptr(bb_free)})}else{u64(0)}
 C.memcpy(unsafe{&wire[0]},&version,4);C.memcpy(unsafe{&wire[4]},&a,8);C.memcpy(unsafe{&wire[12]},&f,8);C.memcpy(unsafe{&wire[20]},&context,8);return wire
}
fn bb_reader(api BBAPI,object u64,size u64){for _ in 0..64{assert bb_query(api,'_CFRetain',object,true)==object;assert bb_query(api,'_CMBlockBufferGetDataLength',object,false)==size;bb_drop(api,object)}}
fn bb_cases(api BBAPI){
 block_create:=unsafe{BBCreate(voidptr(bb_symbol(api,'_CMBlockBufferCreateWithMemoryBlock',false)))};pointer:=unsafe{BBPointer(voidptr(bb_symbol(api,'_CMBlockBufferGetDataPointer',false)))};replace:=unsafe{BBReplace(voidptr(bb_symbol(api,'_CMBlockBufferReplaceDataBytes',false)))};copy_bytes:=unsafe{BBCopy(voidptr(bb_symbol(api,'_CMBlockBufferCopyDataBytes',false)))};fill:=unsafe{BBFill(voidptr(bb_symbol(api,'_CMBlockBufferFillDataBytes',false)))};assure:=unsafe{BBStatus(voidptr(bb_symbol(api,'_CMBlockBufferAssureBlockMemory',false)))};reference:=unsafe{BBReference(voidptr(bb_symbol(api,'_CMBlockBufferCreateWithBufferReference',false)))}
 null_allocator:=read64(bb_symbol(api,'_kCFAllocatorNull',true))
 mut bad:=u64(0xfeed);mut available:=bad;mut total:=bad
 assert pointer(0,0,&available,&total,&bad)==-12705&&available==0xfeed&&total==0xfeed&&bad==0xfeed
 assert bb_query(api,'_CMBlockBufferGetDataLength',0,false)==0
 assert block_create(0,0,32,0,0,0,8,0,unsafe{nil})==-12705
 for mode in 0..6{
  context:=unsafe{&BBContext(C.calloc(1,sizeof(BBContext)))};assert context!=unsafe{nil}
  custom:=mode<3;provided:=mode in [0,3,5]!;borrowed:=mode==5;flags:=if mode==2{u32(1)}else{u32(0)}
  mut memory:=u64(0);if provided{memory=u64(C.malloc(32));assert memory!=0;C.memset(unsafe{voidptr(memory)},0x31,32);unsafe{context.base=memory}}
  mut wire:=bb_wire(u64(context),true,true,0);mut object:=u64(0)
  assert block_create(0,memory,32,if borrowed{null_allocator}else{u64(0)},if custom{unsafe{u64(&wire[0])}}else{u64(0)},4,12,flags,&object)==0&&object!=0
  wire=[28]u8{} // The callback structure is copied by the constructor.
  assert bb_query(api,'_CMBlockBufferGetDataLength',object,false)==12
  assert bb_query(api,'_CFGetTypeID',object,true)==unsafe{BBType(voidptr(bb_symbol(api,'_CMBlockBufferGetTypeID',false)))()}
  assert unsafe{BBEmpty(voidptr(bb_symbol(api,'_CMBlockBufferIsEmpty',false)))(object)}==0
  assert context.allocations==if mode==2{1}else{0}
  for offset in [u64(0),12,13,~u64(0)]!{
   available=0xfeed;total=0xfeed;bad=0xfeed;status:=pointer(object,offset,&available,&total,&bad)
   if offset>=12{assert status==-12703&&available==0&&total==12&&bad==0}else if !provided&&flags==0{assert status==-12707&&available==0&&total==12&&bad==0}else{assert status==0&&available==12&&total==12&&bad!=0}
  }
  mut bytes:=[32]u8{};for i in 0..bytes.len{bytes[i]=0x53}
  if !provided&&flags==0{assert copy_bytes(object,0,4,u64(&bytes[0]))==-12707}
  assert replace(u64(&bytes[0]),object,20,1)==-12703&&fill(0x44,object,20,1)==-12703&&context.allocations==if mode==2{1}else{0}
  assert replace(u64(&bytes[0]),object,0,12)==0&&assure(object)==0
  assert context.allocations==if custom&&!provided{1}else{0}
  mut data:=u64(0);assert pointer(object,0,&available,&total,&data)==0&&available==12&&total==12&&data!=0
  assert pointer(object,0,unsafe{nil},unsafe{nil},unsafe{nil})==0
  assert fill(0x44,object,3,0)==0
  assert copy_bytes(object,0,12,u64(&bytes[0]))==0
  for i in 0..12{assert bytes[i]==if i<3{u8(0x53)}else{u8(0x44)}}
  for range in [[u64(0),0]!,[u64(3),0]!,[u64(13),0]!,[u64(11),2]!,[u64(0),13]!,[u64(13),1]!,[~u64(0),1]!,[u64(0),~u64(0)]!]!{
   expected:=if range[1]==0{-12704}else if range[0]>=12{-12703}else{-12704}
   assert replace(u64(&bytes[0]),object,range[0],range[1])==expected&&copy_bytes(object,range[0],range[1],u64(&bytes[0]))==expected
  }
  assert unsafe{BBContiguous(voidptr(bb_symbol(api,'_CMBlockBufferIsRangeContiguous',false)))(object,0,0)}==1
  assert unsafe{BBContiguous(voidptr(bb_symbol(api,'_CMBlockBufferIsRangeContiguous',false)))(object,12,0)}==0
  mut first:=u64(0);mut second:=u64(0);assert reference(0,object,2,8,0,&first)==0&&reference(0,first,1,0,4,&second)==0
  assert bb_query(api,'_CMBlockBufferGetDataLength',second,false)==7
  bb_drop(api,object);bb_drop(api,first);assert context.frees==0
  mut view:=u64(0);assert pointer(second,0,&available,&total,&view)==0&&available==7&&total==7&&view==data+3
  assert fill(0x6b,second,0,0)==0&&unsafe{*(&u8(data+3))}==0x6b
  mut workers:=[]thread{};for _ in 0..8{workers<<spawn bb_reader(api,second,7)};workers.wait();unsafe{workers.free()}
  assert bb_query(api,'_CFRetain',second,true)==second;bb_drop(api,second);assert context.frees==0;bb_drop(api,second)
  assert context.frees==if custom{1}else{0}
  if borrowed{assert unsafe{*(&u8(memory))}==0x31;C.free(unsafe{voidptr(memory)})}
  C.free(context)
 }
 // No memory is allocated, or freed, when a deferred block is never used.
 context:=unsafe{&BBContext(C.calloc(1,sizeof(BBContext)))};wire:=bb_wire(u64(context),true,true,0);mut object:=u64(0)
 assert block_create(0,0,32,0,u64(&wire[0]),0,8,0,&object)==0;bb_drop(api,object);assert context.allocations==0&&context.frees==0
 unsafe{context.fail=true};object=0xfeed;assert block_create(0,0,32,0,u64(&wire[0]),0,8,1,&object)==-12701&&object==0&&context.allocations==1&&context.frees==0
 unsafe{context.allocations=0};assert block_create(0,0,32,0,u64(&wire[0]),0,8,0,&object)==0;assert assure(object)==-12701&&context.allocations==1;unsafe{context.fail=false};assert assure(object)==0&&context.allocations==2;bb_drop(api,object);assert context.frees==1;C.free(context)
 for args in [[u64(0),0,0]!,[u64(32),33,0]!,[u64(32),4,29]!,[u64(32),32,0]!,[u64(32),4,0]!]!{object=0xfeed;assert block_create(0,0,args[0],0,0,args[1],args[2],0,&object)==-12704&&object==0}
 for flags in [u32(0),1]!{object=0xfeed;assert block_create(0,0,32,null_allocator,0,0,8,flags,&object)==-12701&&object==0}
}
fn bb_private(){
 for name in ['_CMBlockBufferCreateEmpty','_CMBlockBufferAppendMemoryBlock']!{if _:=runtime_symbol('/System/Library/Frameworks/CoreMedia.framework/CoreMedia',name){assert false}}
 for name in ['_CMBlockBufferCreateWithMemoryBlock','_CMBlockBufferGetDataPointer','_CMBlockBufferReplaceDataBytes']!{for lib in ['/System/Library/Frameworks/Foundation.framework/Foundation','/usr/lib/libSystem.B.dylib']!{if _:=runtime_symbol(lib,name){assert false}}}
 // Allocation callbacks may join a reader on another thread. A callback that
 // tries to allocate the same block again receives an explicit failure.
 context:=unsafe{&BBContext(C.calloc(1,sizeof(BBContext)))};wire:=bb_wire(u64(context),true,true,0);mut object:=u64(0)
 assert cm_block_create(0,0,32,0,u64(&wire[0]),0,8,0,&object)==0
 unsafe{context.reentrant_object=object};assert cm_block_assure(object)==0&&context.allocations==1
 objc_release(object);assert context.frees==1;C.free(context)
}
fn test_block_buffer(){
 $if macos{api:=BBAPI{true,u64(C.dlopen(c'/System/Library/Frameworks/CoreMedia.framework/CoreMedia',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2))};bb_cases(api);println('IOS-BLOCK-BUFFER-NATIVE: owned and borrowed memory,packed custom callbacks,deferred allocation,range errors,write-through slices,CF lifetimes and concurrent readers')}
 for _ in 0..2{objc_start();bb_cases(BBAPI{});bb_private();assert ios_runtime.live==ios_runtime.framework_objects.len&&ios_runtime.objects.len==ios_runtime.framework_objects.len;for object in ios_runtime.framework_objects{assert obj_header(object).refs==1};objc_stop();assert ios_runtime.live==0&&ios_runtime.objects.len==0}
 println('IOS-BLOCK-BUFFER: contiguous owned/borrowed/deferred storage,copied packed callbacks,exact final release,nested shared slices,checked range operations,concurrent readers,two drained runtimes;fragment assembly and image sample buffers remain unavailable')
}
