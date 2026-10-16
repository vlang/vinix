// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
struct HFAPI { native bool cm u64 cf u64 }
struct HFCase { sps string pps string avcc string width i32 height i32 progressive bool aspect_width i64 aspect_height i64 color bool full_range bool chroma string }
type HFMake=fn(u64,u64,&u64,&u64,i32,&u64)i32
type HFGet=fn(u64,u64,&u64,&u64,&u64,&i32)i32
type HFQuery=fn(u64)u64
type HFMedia=fn(u64)u32
type HFDims=fn(u64)CMVideoDimensions
type HFType=fn()u64
type HFDrop=fn(u64)
type HFString=fn(u64,&char,u32)u64
type HFDictionary=fn(u64,i64,u64,u64)u64
type HFSet=fn(u64,u64,u64)
type HFValue=fn(u64,u64)u64
type HFEqual=fn(u64,u64)bool
type HFNumber=fn(u64,i64,u64)u64
type HFData=fn(u64,u64,i64)u64
type HFGeneric=fn(u64,u32,u32,u64,&u64)i32
type HFSample=fn(u64,u64,u8,u64,u64,u64,i64,i64,&CMSampleTiming,i64,&u64,&u64)i32
fn hf_symbol(api HFAPI,name string,core bool)u64{
 if api.native{address:=u64(C.dlsym(unsafe{voidptr(if core{api.cf}else{api.cm})},unsafe{&char(name.str+1)}));assert address!=0,name;return address}
 return runtime_symbol(if core{'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'}else{'/System/Library/Frameworks/CoreMedia.framework/CoreMedia'},name)or{panic(err)}
}
fn hf_query(api HFAPI,name string,object u64,core bool)u64{return unsafe{HFQuery(voidptr(hf_symbol(api,name,core)))(object)}}
fn hf_drop(api HFAPI,object u64){unsafe{HFDrop(voidptr(hf_symbol(api,'_CFRelease',true)))(object)}}
fn hf_string(api HFAPI,text string)u64{return unsafe{HFString(voidptr(hf_symbol(api,'_CFStringCreateWithCString',true)))(0,&char(text.str),0x08000100)}}
fn hf_dict(api HFAPI)u64{return unsafe{HFDictionary(voidptr(hf_symbol(api,'_CFDictionaryCreateMutable',true)))(0,0,hf_symbol(api,'_kCFTypeDictionaryKeyCallBacks',true),hf_symbol(api,'_kCFTypeDictionaryValueCallBacks',true))}}
fn hf_put(api HFAPI,dict u64,name string,value u64){key:=hf_string(api,name);unsafe{HFSet(voidptr(hf_symbol(api,'_CFDictionarySetValue',true)))(dict,key,value)};hf_drop(api,key)}
fn hf_value(api HFAPI,dict u64,name string)u64{key:=hf_string(api,name);value:=unsafe{HFValue(voidptr(hf_symbol(api,'_CFDictionaryGetValue',true)))(dict,key)};hf_drop(api,key);return value}
fn hf_equal(api HFAPI,a u64,b u64)bool{return unsafe{HFEqual(voidptr(hf_symbol(api,'_CFEqual',true)))(a,b)}}
fn hf_number(api HFAPI,value i64)u64{return unsafe{HFNumber(voidptr(hf_symbol(api,'_CFNumberCreate',true)))(0,4,u64(&value))}}
fn hf_put_text(api HFAPI,dict u64,name string,text string){value:=hf_string(api,text);hf_put(api,dict,name,value);hf_drop(api,value)}
fn hf_put_number(api HFAPI,dict u64,name string,value i64){number:=hf_number(api,value);hf_put(api,dict,name,number);hf_drop(api,number)}
fn hf_expected(api HFAPI,row HFCase,avcc []u8)u64{
 result:=hf_dict(api);atoms:=hf_dict(api);data:=unsafe{HFData(voidptr(hf_symbol(api,'_CFDataCreate',true)))(0,u64(avcc.data),i64(avcc.len))}
 hf_put(api,atoms,'avcC',data);hf_put(api,result,'SampleDescriptionExtensionAtoms',atoms);hf_drop(api,data);hf_drop(api,atoms)
 if row.progressive{hf_put_number(api,result,'CVFieldCount',1)}
 hf_put_text(api,result,'CVImageBufferChromaLocationTopField',row.chroma);hf_put_text(api,result,'CVImageBufferChromaLocationBottomField',row.chroma)
 if row.aspect_width!=0{aspect:=hf_dict(api);hf_put_number(api,aspect,'HorizontalSpacing',row.aspect_width);hf_put_number(api,aspect,'VerticalSpacing',row.aspect_height);hf_put(api,result,'CVPixelAspectRatio',aspect);hf_drop(api,aspect)}
 if row.color{for key in ['CVImageBufferColorPrimaries','CVImageBufferTransferFunction','CVImageBufferYCbCrMatrix']!{hf_put_text(api,result,key,'ITU_R_709_2')}}
 hf_put(api,result,'FullRangeVideo',read64(hf_symbol(api,if row.full_range{'_kCFBooleanTrue'}else{'_kCFBooleanFalse'},true)))
 return result
}
fn hf_check_record(api HFAPI,object u64,sps []u8,pps []u8,header i32){
 query:=unsafe{HFGet(voidptr(hf_symbol(api,'_CMVideoFormatDescriptionGetH264ParameterSetAtIndex',false)))}
 for index in [u64(0),1,2,999]!{for mask in [u32(0),1,2,4,8,15]!{
  mut pointer:=u64(0xfeed);mut size:=u64(0xfeed);mut count:=u64(0xfeed);mut h:=i32(0xfeed)
  status:=query(object,index,if mask&1!=0{&pointer}else{unsafe{nil}},if mask&2!=0{&size}else{unsafe{nil}},if mask&4!=0{&count}else{unsafe{nil}},if mask&8!=0{&h}else{unsafe{nil}})
  assert status==if index>1&&mask&3!=0{-12712}else{0}
  if mask&4!=0{assert count==2}else{assert count==0xfeed};if mask&8!=0{assert h==header}else{assert h==0xfeed}
  expected:=if index==0{sps}else{pps}
  if mask&2!=0{assert size==if index<2{u64(expected.len)}else{u64(0)}}else{assert size==0xfeed}
  if mask&1!=0{if index<2{assert pointer!=0;assert C.memcmp(unsafe{voidptr(pointer)},expected.data,usize(expected.len))==0}else{assert pointer==0}}else{assert pointer==0xfeed}
 }}
}
fn hf_reader(api HFAPI,object u64,sps []u8,pps []u8,header i32){for _ in 0..16{assert hf_query(api,'_CFRetain',object,true)==object;hf_check_record(api,object,sps,pps,header);hf_drop(api,object)}}
fn hf_cases(api HFAPI){
 make:=unsafe{HFMake(voidptr(hf_symbol(api,'_CMVideoFormatDescriptionCreateFromH264ParameterSets',false)))}
 for row in [HFCase{'6742c01eda0280f684000003000400000300f03c58ba80','68ce0fc8','0142c01effe100176742c01eda0280f684000003000400000300f03c58ba8001000468ce0fc8',640,480,true,0,0,false,false,'Left'},
		HFCase{'6742c01eda0280f7aa84000003000400000300f03c58ba80','68ce0fc8','0142c01effe100186742c01eda0280f7aa84000003000400000300f03c58ba8001000468ce0fc8',638,478,true,0,0,false,false,'Left'},
		HFCase{'6742c01eda0280f6c384000003000400000300f03c58ba80','68ce0fc8','0142c01effe100186742c01eda0280f6c384000003000400000300f03c58ba8001000468ce0fc8',640,480,true,4,3,false,false,'Left'},
		HFCase{'6742c01eda0280f69b808080a0000003002000000781e2c5d4','68ce0fc8','0142c01effe100196742c01eda0280f69b808080a0000003002000000781e2c5d401000468ce0fc8',640,480,true,0,0,true,true,'Left'},
		HFCase{'6742c01eda0280f684000003000400000300f03c58ba80','68ce0fc8','0142c01effe100176742c01eda0280f684000003000400000300f03c58ba8001000468ce0fc8',640,480,true,0,0,false,false,'Left'},
		HFCase{'6764001eacb40501ed08000003000800000301e078b175','68ce0fcb','0164001effe100176764001eacb40501ed08000003000800000301e078b17501000468ce0fcbfdf8f800',640,480,true,0,0,false,false,'Left'},
		HFCase{'674d401ef40503da10000003001000000303c1f142aa','68de0fc8','014d401effe10016674d401ef40503da10000003001000000303c1f142aa01000468de0fc8',640,480,false,0,0,false,false,'Left'},
		HFCase{'6742c01eda0280f6c044000003000400000300f03c58ba80','68ce0fc8','0142c01effe100186742c01eda0280f6c044000003000400000300f03c58ba8001000468ce0fc8',640,480,true,1,1,false,false,'Left'},
		HFCase{'6742c01eda0280f69b20000003002000000781e2c5d4','68ce0fc8','0142c01effe100166742c01eda0280f69b20000003002000000781e2c5d401000468ce0fc8',640,480,true,0,0,false,true,'Left'},
		HFCase{'6742c01eda0280f68a50000003001000000303c0f162ea','68ce0fc8','0142c01effe100176742c01eda0280f68a50000003001000000303c0f162ea01000468ce0fc8',640,480,true,0,0,false,false,'Center'},
		HFCase{'6742c01eda0280f6ffc001c00144000003000400000300f03c58ba80','68ce0fc8','0142c01effe1001c6742c01eda0280f6ffc001c00144000003000400000300f03c58ba8001000468ce0fc8',640,480,true,7,5,false,false,'Left'}]!{
  original_sps:=hex.decode(row.sps)or{panic(err)};original_pps:=hex.decode(row.pps)or{panic(err)}
  for length_size in [i32(1),2,4]!{
   mut sps:=original_sps.clone();mut pps:=original_pps.clone();mut avcc:=hex.decode(row.avcc)or{panic(err)};avcc[4]=u8(0xfc|u32(length_size-1))
   mut pointers:=[u64(pps.data),u64(sps.data)]!;mut sizes:=[u64(pps.len),u64(sps.len)]!
   mut object:=u64(0);assert make(0,2,unsafe{&pointers[0]},unsafe{&sizes[0]},length_size,&object)==0&&object!=0
   C.memset(sps.data,0,usize(sps.len));C.memset(pps.data,0,usize(pps.len));pointers=[2]u64{};sizes=[2]u64{}
   assert unsafe{HFMedia(voidptr(hf_symbol(api,'_CMFormatDescriptionGetMediaType',false)))(object)}==0x76696465
   assert unsafe{HFMedia(voidptr(hf_symbol(api,'_CMFormatDescriptionGetMediaSubType',false)))(object)}==0x61766331
   assert unsafe{HFDims(voidptr(hf_symbol(api,'_CMVideoFormatDescriptionGetDimensions',false)))(object)}==CMVideoDimensions{row.width,row.height}
   assert hf_query(api,'_CFGetTypeID',object,true)==unsafe{HFType(voidptr(hf_symbol(api,'_CMFormatDescriptionGetTypeID',false)))()}
   hf_check_record(api,object,original_sps,original_pps,length_size)
   actual:=hf_query(api,'_CMFormatDescriptionGetExtensions',object,false);expected:=hf_expected(api,row,avcc);assert hf_equal(api,actual,expected)
   mut reconstructed:=u64(0);assert unsafe{HFGeneric(voidptr(hf_symbol(api,'_CMFormatDescriptionCreate',false)))(0,0x76696465,0x61766331,expected,&reconstructed)}==0
   // Parameter queries also accept an independently created avcC metadata atom.
   hf_check_record(api,reconstructed,original_sps,original_pps,length_size);hf_drop(api,expected);hf_drop(api,reconstructed)
   mut sample:=u64(0);assert unsafe{HFSample(voidptr(hf_symbol(api,'_CMSampleBufferCreate',false)))(0,0,1,0,0,object,0,0,nil,0,nil,&sample)}==0
   hf_drop(api,object);assert hf_query(api,'_CMSampleBufferGetFormatDescription',sample,false)==object
   mut workers:=[]thread{};for _ in 0..4{workers<<spawn hf_reader(api,object,original_sps,original_pps,length_size)};workers.wait();unsafe{workers.free()}
   data:=hf_value(api,hf_value(api,actual,'SampleDescriptionExtensionAtoms'),'avcC');assert hf_query(api,'_CFRetain',data,true)==data
   hf_drop(api,sample);assert hf_query(api,'_CFDataGetLength',data,true)==u64(avcc.len);assert C.memcmp(unsafe{voidptr(hf_query(api,'_CFDataGetBytePtr',data,true))},avcc.data,usize(avcc.len))==0;hf_drop(api,data)
   unsafe{sps.free();pps.free();avcc.free()}
  }
  unsafe{original_sps.free();original_pps.free()}
 }
 // Canonical grouping preserves duplicates and ignores the caller's NAL order.
 sps:=hex.decode('6742c01eda0280f684000003000400000300f03c58ba80')or{panic(err)};pps:=hex.decode('68ce0fc8')or{panic(err)}
 mut pointers:=[u64(pps.data),u64(sps.data),u64(pps.data),u64(sps.data)]!;mut sizes:=[u64(pps.len),u64(sps.len),u64(pps.len),u64(sps.len)]!
 mut object:=u64(0);assert make(0,4,unsafe{&pointers[0]},unsafe{&sizes[0]},4,&object)==0
 query:=unsafe{HFGet(voidptr(hf_symbol(api,'_CMVideoFormatDescriptionGetH264ParameterSetAtIndex',false)))}
 for i in u64(0)..4{mut ptr:=u64(0);mut size:=u64(0);mut count:=u64(0);assert query(object,i,&ptr,&size,&count,unsafe{nil})==0&&count==4;expected:=if i<2{sps}else{pps};assert size==u64(expected.len)&&C.memcmp(unsafe{voidptr(ptr)},expected.data,usize(size))==0};hf_drop(api,object)
 for length_size in [i32(-1),0,3,5]!{object=0xfeed;assert make(0,2,unsafe{&pointers[0]},unsafe{&sizes[0]},length_size,&object)==-12712&&object==0xfeed}
 for count in [u64(0),1]!{object=0xfeed;assert make(0,count,unsafe{&pointers[0]},unsafe{&sizes[0]},4,&object)==-12712&&object==0xfeed}
 // Truncated SPS lengths are checked before any metadata object is published.
 pointers=[u64(sps.data),u64(pps.data),0,0]!
 for cut in u64(0)..u64(sps.len){sizes=[cut,u64(pps.len),0,0]!;object=0xfeed;status:=make(0,2,unsafe{&pointers[0]},unsafe{&sizes[0]},4,&object);if cut>=22{assert status==0;hf_drop(api,object)}else{assert status==if cut==0{-12712}else if cut<5{-12714}else{-12710};assert object==0xfeed}}
 for subtype in [u32(0x61766331),0x68766331,0x6d656278]!{object=0;assert unsafe{HFGeneric(voidptr(hf_symbol(api,'_CMFormatDescriptionCreate',false)))(0,0x76696465,subtype,0,&object)}==0
  mut ptr:=u64(0xfeed);mut size:=u64(0xfeed);mut count:=u64(0xfeed);mut header:=i32(0xfeed);assert query(object,0,&ptr,&size,&count,&header)==-12710&&ptr==0xfeed&&size==0xfeed&&count==0xfeed&&header==0xfeed;hf_drop(api,object)
 }
 assert query(0,0,unsafe{nil},unsafe{nil},unsafe{nil},unsafe{nil})==-12710
 unsafe{sps.free();pps.free()}
}
fn hf_private(){
 before:=ios_runtime.live;mut out:=u64(0xfeed)
 assert cm_h264_create(0,2,unsafe{nil},unsafe{nil},4,&out)==-12712&&out==0xfeed
 assert cm_h264_create(0,65,unsafe{nil},unsafe{nil},4,&out)==-12712&&out==0xfeed
 // A guarded input proves oversized NAL units are rejected before reading them.
 page:=C.mmap(unsafe{nil},4096,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANON,-1,0);assert page!=voidptr(-1)
 pointers:=[u64(page),u64(page)]!;sizes:=[u64(65536),2]!
 assert cm_h264_create(0,2,unsafe{&pointers[0]},unsafe{&sizes[0]},4,&out)==-12712&&out==0xfeed
 assert C.munmap(page,4096)==0
 for name in ['_CMVideoFormatDescriptionCreateForImageBuffer']!{if _:=runtime_symbol('/System/Library/Frameworks/CoreMedia.framework/CoreMedia',name){assert false}}
 for lib in ['/System/Library/Frameworks/Foundation.framework/Foundation','/usr/lib/libSystem.B.dylib']!{if _:=runtime_symbol(lib,'_CMVideoFormatDescriptionCreateFromH264ParameterSets'){assert false}}
 assert ios_runtime.live==before
}
fn test_h264_format(){
 $if macos{api:=HFAPI{true,u64(C.dlopen(c'/System/Library/Frameworks/CoreMedia.framework/CoreMedia',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2))};hf_cases(api);println('IOS-H264-FORMAT-NATIVE: local libx264 SPS/PPS fixtures,baseline/main/high,crop,square/extended aspect,chroma location,709/full-range,interlace,exact avcC,borrowed getters,errors,retained sample and data owners,concurrent readers')}
 for _ in 0..2{objc_start();hf_cases(HFAPI{});hf_private();assert ios_runtime.live==ios_runtime.framework_objects.len&&ios_runtime.objects.len==ios_runtime.framework_objects.len;objc_stop();assert ios_runtime.live==0&&ios_runtime.objects.len==0}
 println('IOS-H264-FORMAT: copied H264 parameters,bounded RBSP parsing,owned immutable avcC metadata,dimensions and VUI,borrowed parameter sets,CF/sample ownership,concurrent readers,two drained runtimes;codec execution remains unavailable')
}
