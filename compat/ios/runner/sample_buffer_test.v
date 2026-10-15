// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.fork() i32
struct SBAPI { native bool cm u64 cf u64 }
struct SBPayload {mut: base u64 frees int }
struct SBContext { api SBAPI mut: calls int status i32 reentrant bool action int }
type SBCreate=fn(u64,u64,u8,u64,u64,u64,i64,i64,&CMSampleTiming,i64,&u64,&u64)i32
type SBBlock=fn(u64,u64,u64,u64,u64,u64,u64,u32,&u64)i32
type SBFormat=fn(u64,u32,u32,u64,&u64)i32
type SBQuery=fn(u64)u64
type SBBool=fn(u64)u8
type SBStatus=fn(u64)i32
type SBSet=fn(u64,u64)i32
type SBType=fn()u64
type SBTime=fn(u64)CMTime
type SBSize=fn(u64,i64)u64
type SBTimingArray=fn(u64,i64,&CMSampleTiming,&i64)i32
type SBSizeArray=fn(u64,i64,&u64,&i64)i32
type SBTimingAt=fn(u64,i64,&CMSampleTiming)i32
type SBDrop=fn(u64)
fn sb_symbol(api SBAPI,name string,cf bool)u64{
 if api.native{p:=u64(C.dlsym(unsafe{voidptr(if cf{api.cf}else{api.cm})},unsafe{&char(name.str+1)}));assert p!=0,name;return p}
 return runtime_symbol(if cf{'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'}else{'/System/Library/Frameworks/CoreMedia.framework/CoreMedia'},name)or{panic(err)}
}
fn sb_query(api SBAPI,name string,object u64,cf bool)u64{if !api.native&&name=='_CFGetRetainCount'{return u64(obj_header(object).refs)};return unsafe{SBQuery(voidptr(sb_symbol(api,name,cf)))(object)}}
fn sb_bool(api SBAPI,name string,object u64)u8{return unsafe{SBBool(voidptr(sb_symbol(api,name,false)))(object)}}
fn sb_status(api SBAPI,name string,object u64)i32{return unsafe{SBStatus(voidptr(sb_symbol(api,name,false)))(object)}}
fn sb_time(api SBAPI,name string,object u64)CMTime{return unsafe{SBTime(voidptr(sb_symbol(api,name,false)))(object)}}
fn sb_drop(api SBAPI,object u64){unsafe{SBDrop(voidptr(sb_symbol(api,'_CFRelease',true)))(object)}}
fn sb_reader(api SBAPI,object u64,count u64){for _ in 0..64{assert sb_query(api,'_CFRetain',object,true)==object;assert sb_query(api,'_CMSampleBufferGetNumSamples',object,false)==count;assert sb_bool(api,'_CMSampleBufferIsValid',object)==1;sb_drop(api,object)}}
fn sb_ready_callback(object u64,context u64)i32{mut c:=unsafe{&SBContext(context)};c.calls++;worker:=spawn sb_reader(c.api,object,3);worker.wait();if c.reentrant{assert cm_sample_make_ready(object)==-12733};if c.action!=0{assert sb_status(c.api,if c.action==1{'_CMSampleBufferSetDataReady'}else{'_CMSampleBufferInvalidate'},object)==0};return c.status}
fn sb_payload_free(context u64,memory u64,size u64){mut c:=unsafe{&SBPayload(context)};assert size==32&&memory==c.base&&c.frees==0;c.frees++;C.free(unsafe{voidptr(memory)})}
fn sb_owners(api SBAPI){
 make:=unsafe{SBCreate(voidptr(sb_symbol(api,'_CMSampleBufferCreate',false)))};set_data:=unsafe{SBSet(voidptr(sb_symbol(api,'_CMSampleBufferSetDataBuffer',false)))}
 for invalidating in [false,true]!{
  context:=unsafe{&SBPayload(C.calloc(1,sizeof(SBPayload)))};unsafe{context.base=u64(C.malloc(32))};assert context.base!=0;C.memset(unsafe{voidptr(context.base)},0x53,32)
  mut wire:=[28]u8{};callback:=u64(unsafe{voidptr(sb_payload_free)});address:=u64(context);C.memcpy(unsafe{&wire[12]},&callback,8);C.memcpy(unsafe{&wire[20]},&address,8)
  mut block:=u64(0);assert unsafe{SBBlock(voidptr(sb_symbol(api,'_CMBlockBufferCreateWithMemoryBlock',false)))(0,context.base,32,0,u64(&wire[0]),4,12,0,&block)}==0
  mut format:=u64(0);assert unsafe{SBFormat(voidptr(sb_symbol(api,'_CMFormatDescriptionCreate',false)))(0,0x6d657461,1,0,&format)}==0
  before:=sb_query(api,'_CFGetRetainCount',format,true)
  mut timing:=CMSampleTiming{CMTime{1,30,1,0},CMTime{60,30,1,2},CMTime{}};mut size:=u64(4);mut object:=u64(0)
  assert make(0,block,1,0,0,format,3,1,&timing,1,&size,&object)==0&&object!=0
  assert sb_query(api,'_CFGetRetainCount',format,true)==before+1
  timing=CMSampleTiming{};size=0;wire=[28]u8{}
  assert sb_time(api,'_CMSampleBufferGetDuration',object)==CMTime{3,30,1,0}
  assert sb_query(api,'_CMSampleBufferGetDataBuffer',object,false)==block&&sb_query(api,'_CMSampleBufferGetFormatDescription',object,false)==format
  assert sb_query(api,'_CMSampleBufferGetImageBuffer',object,false)==0&&set_data(object,block)==-12732
  assert sb_query(api,'_CFGetTypeID',object,true)==unsafe{SBType(voidptr(sb_symbol(api,'_CMSampleBufferGetTypeID',false)))()}
  assert sb_query(api,'_CFRetain',object,true)==object;sb_drop(api,object)
  assert sb_query(api,'_CFRetain',block,true)==block&&sb_query(api,'_CFRetain',format,true)==format
  sb_drop(api,block);sb_drop(api,format)
  mut workers:=[]thread{};for _ in 0..8{workers<<spawn sb_reader(api,object,3)};workers.wait();unsafe{workers.free()}
  if invalidating{
   assert sb_status(api,'_CMSampleBufferInvalidate',object)==0&&sb_status(api,'_CMSampleBufferInvalidate',object)==-12744
   assert sb_bool(api,'_CMSampleBufferIsValid',object)==0&&sb_bool(api,'_CMSampleBufferDataIsReady',object)==0&&sb_query(api,'_CMSampleBufferGetNumSamples',object,false)==0
   assert sb_query(api,'_CMSampleBufferGetDataBuffer',object,false)==0&&sb_query(api,'_CMSampleBufferGetFormatDescription',object,false)==0&&sb_time(api,'_CMSampleBufferGetDuration',object)==CMTime{}
   assert sb_status(api,'_CMSampleBufferSetDataReady',object)==-12744&&sb_status(api,'_CMSampleBufferMakeDataReady',object)==-12744&&set_data(object,block)==-12744
   assert sb_query(api,'_CFGetRetainCount',format,true)==before+1
  }
  sb_drop(api,object);assert context.frees==0
  assert unsafe{*(&u8(context.base+4))}==0x53;sb_drop(api,block);sb_drop(api,format);assert context.frees==1;C.free(context)
 }
 // Attaching data later retains it and does not implicitly mark data ready.
 mut object:=u64(0);mut block:=u64(0);assert make(0,0,0,0,0,0,3,0,unsafe{nil},0,unsafe{nil},&object)==0
 assert unsafe{SBBlock(voidptr(sb_symbol(api,'_CMBlockBufferCreateWithMemoryBlock',false)))(0,0,12,0,0,0,12,1,&block)}==0
 assert set_data(object,0)==-12731&&set_data(object,block)==0&&set_data(object,block)==-12732;sb_drop(api,block)
 assert sb_bool(api,'_CMSampleBufferDataIsReady',object)==0&&sb_query(api,'_CMSampleBufferGetDataBuffer',object,false)==block
 assert sb_status(api,'_CMSampleBufferSetDataReady',object)==0;sb_drop(api,object)
}
fn sb_cases(api SBAPI){
 assert sizeof(CMTime)==24&&sizeof(CMSampleTiming)==72
 make:=unsafe{SBCreate(voidptr(sb_symbol(api,'_CMSampleBufferCreate',false)))};timing_array:=unsafe{SBTimingArray(voidptr(sb_symbol(api,'_CMSampleBufferGetSampleTimingInfoArray',false)))};sizes:=unsafe{SBSizeArray(voidptr(sb_symbol(api,'_CMSampleBufferGetSampleSizeArray',false)))};at:=unsafe{SBTimingAt(voidptr(sb_symbol(api,'_CMSampleBufferGetSampleTimingInfo',false)))};get_size:=unsafe{SBSize(voidptr(sb_symbol(api,'_CMSampleBufferGetSampleSize',false)))}
 for entries in [i64(0),1,3]!{
  mut rows:=[CMSampleTiming{CMTime{1,30,1,0},CMTime{60,30,1,2},CMTime{}},CMSampleTiming{CMTime{2,30,1,0},CMTime{30,30,1,2},CMTime{10,30,1,2}},CMSampleTiming{CMTime{3,30,1,0},CMTime{90,30,1,2},CMTime{20,30,1,2}}]!
  mut input_sizes:=[u64(4),5,6]!;mut wire:=[220]u8{};C.memcpy(unsafe{&wire[4]},unsafe{&rows[0]},216)
  mut object:=u64(0);assert make(0,0,0,0,0,0,3,entries,unsafe{&CMSampleTiming(&wire[4])},entries,unsafe{&input_sizes[0]},&object)==0
  rows=[3]CMSampleTiming{};input_sizes=[3]u64{};wire=[220]u8{}
  assert sb_query(api,'_CMSampleBufferGetNumSamples',object,false)==3&&sb_bool(api,'_CMSampleBufferDataIsReady',object)==0
  assert sb_time(api,'_CMSampleBufferGetDuration',object)==if entries==0{CMTime{0,1,1,0}}else{CMTime{if entries==1{i64(3)}else{i64(6)},30,1,0}}
  assert sb_query(api,'_CMSampleBufferGetTotalSampleSize',object,false)==if entries==0{u64(0)}else if entries==1{u64(12)}else{u64(15)}
  assert sb_time(api,'_CMSampleBufferGetPresentationTimeStamp',object)==if entries==0{CMTime{}}else{CMTime{if entries==1{i64(60)}else{i64(30)},30,1,2}}
  assert sb_time(api,'_CMSampleBufferGetDecodeTimeStamp',object)==if entries==3{CMTime{10,30,1,2}}else{CMTime{}}
  mut needed:=i64(0xfeed);assert timing_array(object,0,unsafe{nil},&needed)==if entries==0{-12736}else{0};assert needed==entries
  needed=0xfeed;assert sizes(object,0,unsafe{nil},&needed)==if entries==0{-12735}else{0};assert needed==entries
  mut output:=[3]CMSampleTiming{};mut size_out:=[3]u64{}
  assert timing_array(object,0,unsafe{&output[0]},&needed)==if entries==0{-12736}else{-12737}
  assert sizes(object,0,unsafe{&size_out[0]},&needed)==if entries==0{-12735}else{-12737}
  assert timing_array(object,3,unsafe{&output[0]},&needed)==if entries==0{-12736}else{0}
  assert sizes(object,3,unsafe{&size_out[0]},&needed)==if entries==0{-12735}else{0}
  for index in [i64(-1),0,1,2,3]!{
   marker:=CMSampleTiming{CMTime{99,99,99,99},CMTime{},CMTime{}};mut row:=marker
   expected:=if entries==0{-12736}else if index<0||index>=3{-12734}else{0}
   assert at(object,index,&row)==expected
   if expected!=0{assert row==marker;assert get_size(object,index)==0}else{
    assert row.duration==CMTime{if entries==1{i64(1)}else{index+1},30,1,0}
    assert row.pts==CMTime{if entries==1{60+index}else{if index==0{i64(60)}else if index==1{i64(30)}else{i64(90)}},30,1,2}
    assert get_size(object,index)==if entries==1{u64(4)}else{u64(index+4)}
   }
  }
  assert sb_status(api,'_CMSampleBufferMakeDataReady',object)==-12733&&sb_status(api,'_CMSampleBufferSetDataReady',object)==0
  assert sb_status(api,'_CMSampleBufferMakeDataReady',object)==0
  assert sb_status(api,'_CMSampleBufferInvalidate',object)==0;needed=0xfeed;assert timing_array(object,0,unsafe{nil},&needed)==-12744&&needed==0xfeed;assert sizes(object,0,unsafe{nil},&needed)==-12744&&needed==0xfeed;sb_drop(api,object)
 }
 // The supplied IPA uses this twelve-argument ABI with one sample/timing and no sizes.
 mut row:=CMSampleTiming{CMTime{1001,30000,1,0},CMTime{90000,30000,1,0},CMTime{}};mut object:=u64(0)
 assert make(0,0,1,0,0,0,1,1,&row,0,unsafe{nil},&object)==0&&sb_time(api,'_CMSampleBufferGetDuration',object)==row.duration;sb_drop(api,object)
 for time in [CMTime{},CMTime{-1,30,1,0},CMTime{0,0,5,0},CMTime{0,0,17,0},CMTime{1,30,3,0}]!{
  row=CMSampleTiming{time,CMTime{},CMTime{}};assert make(0,0,1,0,0,0,3,1,&row,0,unsafe{nil},&object)==0
  assert sb_time(api,'_CMSampleBufferGetDuration',object)==if time.flags&28!=0||time.flags==0{time}else{CMTime{time.value*3,time.scale,time.flags,time.epoch}};sb_drop(api,object)
 }
 for ready in [u8(0),1]!{assert make(0,0,ready,0,0,0,0,0,unsafe{nil},0,unsafe{nil},&object)==0&&sb_bool(api,'_CMSampleBufferDataIsReady',object)==ready;assert sb_time(api,'_CMSampleBufferGetDuration',object)==CMTime{0,1,1,0};sb_drop(api,object)}
 mut times:=[3]CMSampleTiming{};mut bytes:=[3]u64{}
 for counts in [[i64(3),2,0]!,[i64(3),0,2]!,[i64(0),1,1]!,[i64(3),-1,0]!]!{object=0xfeed;assert make(0,0,0,0,0,0,counts[0],counts[1],unsafe{&times[0]},counts[2],unsafe{&bytes[0]},&object)==-12738&&object==0}
 for mode in 0..8{
  mut context:=SBContext{api:api,status:if mode in [1,5,7]!{i32(-123)}else{i32(0)},reentrant:!api.native&&mode==0,action:if mode in [4,5]!{2}else if mode in [6,7]!{1}else{0}}
  assert make(0,0,u8(mode==2),u64(unsafe{voidptr(sb_ready_callback)}),u64(&context),0,3,0,unsafe{nil},0,unsafe{nil},&object)==0
  if mode==3{sb_drop(api,object);assert context.calls==0;continue}
  expected:=context.status;assert sb_status(api,'_CMSampleBufferMakeDataReady',object)==expected
  if mode in [4,5]!{assert context.calls==1&&sb_bool(api,'_CMSampleBufferIsValid',object)==0&&sb_status(api,'_CMSampleBufferMakeDataReady',object)==-12744;sb_drop(api,object);continue}
  if mode==1{assert context.calls==1&&sb_bool(api,'_CMSampleBufferDataIsReady',object)==0;context.status=0;assert sb_status(api,'_CMSampleBufferMakeDataReady',object)==0;assert context.calls==2}else{assert context.calls==if mode==2{0}else{1}}
  assert sb_status(api,'_CMSampleBufferMakeDataReady',object)==0;sb_drop(api,object)
 }
 assert sb_bool(api,'_CMSampleBufferIsValid',0)==0&&sb_bool(api,'_CMSampleBufferDataIsReady',0)==0&&sb_query(api,'_CMSampleBufferGetNumSamples',0,false)==0&&sb_time(api,'_CMSampleBufferGetDuration',0)==CMTime{}
 for name in ['_CMSampleBufferMakeDataReady','_CMSampleBufferSetDataReady','_CMSampleBufferInvalidate']!{assert sb_status(api,name,0)==-12731}
 sb_owners(api)
}
fn sb_private(){
 for name in ['_CMSampleBufferCreateForImageBuffer','_CMSampleBufferCopyPCMDataIntoAudioBufferList','_CMTimeMake']!{if _:=runtime_symbol('/System/Library/Frameworks/CoreMedia.framework/CoreMedia',name){assert false}}
 for library in ['/System/Library/Frameworks/Foundation.framework/Foundation','/usr/lib/libSystem.B.dylib']!{if _:=runtime_symbol(library,'_CMSampleBufferCreate'){assert false}}
 before:=ios_runtime.live;mut out:=u64(0xfeed);assert cm_sample_create(0,0,0,0,0,0,3,1,unsafe{nil},0,unsafe{nil},&out)==-12731&&out==0
 out=0xfeed;assert cm_sample_create(0,0,0,0,0,0,65537,0,unsafe{nil},0,unsafe{nil},&out)==-12731&&out==0
 row:=CMSampleTiming{CMTime{9223372036854775807,30,1,0},CMTime{},CMTime{}};out=0xfeed;assert cm_sample_create(0,0,0,0,0,0,2,1,&row,0,unsafe{nil},&out)==-12740&&out==0&&ios_runtime.live==before
 mixed:=[CMSampleTiming{CMTime{1,30,1,0},CMTime{},CMTime{}},CMSampleTiming{CMTime{1,60,1,0},CMTime{},CMTime{}}]!;out=0xfeed;assert cm_sample_create(0,0,0,0,0,0,2,2,unsafe{&mixed[0]},0,unsafe{nil},&out)==-12740&&out==0&&ios_runtime.live==before
 for mode in 0..3{
  mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.fork();assert pid>=0
  if pid==0{
   C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1])
   mut bad:=u64(0)
   if mode==0{bad=u64(C.mmap(unsafe{nil},4096,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANON,-1,0));assert bad!=~u64(0)}else if mode==1{assert cm_sample_create(0,0,0,0,0,0,0,0,unsafe{nil},0,unsafe{nil},&bad)==0;objc_release(bad)}else{bad=objc_new(ios_runtime.names['NSObject'])}
   cm_sample_count(bad);C._exit(0)
  }
  C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0
  for{assert length<bytes.len;n:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if n==0{break};if n<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert n>0;length+=int(n)}
  C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
  output:=unsafe{tos(&bytes[0],length)};assert output.contains('iOS: expected a live CMSampleBuffer')&&!output.contains('AddressSanitizer')&&!output.contains('runtime error:'),output
 }
}
fn test_sample_buffer(){
 $if macos{api:=SBAPI{true,u64(C.dlopen(c'/System/Library/Frameworks/CoreMedia.framework/CoreMedia',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2))};sb_cases(api);println('IOS-SAMPLE-BUFFER-NATIVE: copied timing/sizes,24-byte time return,12-argument creation,owners,readiness callback retry,invalidation and concurrent readers')}
 for _ in 0..2{objc_start();sb_cases(SBAPI{});sb_private();assert ios_runtime.live==ios_runtime.framework_objects.len&&ios_runtime.objects.len==ios_runtime.framework_objects.len;objc_stop();assert ios_runtime.live==0&&ios_runtime.objects.len==0}
 println('IOS-SAMPLE-BUFFER: block data and format owners,copied packed timing/sizes,checked duration/timestamps,readiness callbacks,invalidation,concurrent readers,two drained runtimes;image sample construction,codecs and general CMTime operations remain unavailable')
}
