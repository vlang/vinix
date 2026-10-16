// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
struct HVAPI { native bool cm u64 cf u64 }
struct HVCase { vps string depth i64 sps string pps string hvcc string width i32 height i32 progressive bool aspect_width i64 aspect_height i64 color bool full_range bool chroma string }
type HVMake=fn(u64,u64,&u64,&u64,i32,u64,&u64)i32
type HVGet=fn(u64,u64,&u64,&u64,&u64,&i32)i32
type HVQuery=fn(u64)u64
type HVMedia=fn(u64)u32
type HVDims=fn(u64)CMVideoDimensions
type HVType=fn()u64
type HVDrop=fn(u64)
type HVString=fn(u64,&char,u32)u64
type HVDictionary=fn(u64,i64,u64,u64)u64
type HVSet=fn(u64,u64,u64)
type HVValue=fn(u64,u64)u64
type HVEqual=fn(u64,u64)bool
type HVNumber=fn(u64,i64,u64)u64
type HVData=fn(u64,u64,i64)u64
type HVGeneric=fn(u64,u32,u32,u64,&u64)i32
type HVSample=fn(u64,u64,u8,u64,u64,u64,i64,i64,&CMSampleTiming,i64,&u64,&u64)i32
fn hv_symbol(api HVAPI,name string,core bool)u64{
 if api.native{address:=u64(C.dlsym(unsafe{voidptr(if core{api.cf}else{api.cm})},unsafe{&char(name.str+1)}));assert address!=0,name;return address}
 return runtime_symbol(if core{'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'}else{'/System/Library/Frameworks/CoreMedia.framework/CoreMedia'},name)or{panic(err)}
}
fn hv_query(api HVAPI,name string,object u64,core bool)u64{return unsafe{HVQuery(voidptr(hv_symbol(api,name,core)))(object)}}
fn hv_drop(api HVAPI,object u64){unsafe{HVDrop(voidptr(hv_symbol(api,'_CFRelease',true)))(object)}}
fn hv_string(api HVAPI,text string)u64{return unsafe{HVString(voidptr(hv_symbol(api,'_CFStringCreateWithCString',true)))(0,&char(text.str),0x08000100)}}
fn hv_dict(api HVAPI)u64{return unsafe{HVDictionary(voidptr(hv_symbol(api,'_CFDictionaryCreateMutable',true)))(0,0,hv_symbol(api,'_kCFTypeDictionaryKeyCallBacks',true),hv_symbol(api,'_kCFTypeDictionaryValueCallBacks',true))}}
fn hv_put(api HVAPI,dict u64,name string,value u64){key:=hv_string(api,name);unsafe{HVSet(voidptr(hv_symbol(api,'_CFDictionarySetValue',true)))(dict,key,value)};hv_drop(api,key)}
fn hv_value(api HVAPI,dict u64,name string)u64{key:=hv_string(api,name);value:=unsafe{HVValue(voidptr(hv_symbol(api,'_CFDictionaryGetValue',true)))(dict,key)};hv_drop(api,key);return value}
fn hv_equal(api HVAPI,a u64,b u64)bool{return unsafe{HVEqual(voidptr(hv_symbol(api,'_CFEqual',true)))(a,b)}}
fn hv_number(api HVAPI,value i64)u64{return unsafe{HVNumber(voidptr(hv_symbol(api,'_CFNumberCreate',true)))(0,4,u64(&value))}}
fn hv_put_text(api HVAPI,dict u64,name string,text string){value:=hv_string(api,text);hv_put(api,dict,name,value);hv_drop(api,value)}
fn hv_put_number(api HVAPI,dict u64,name string,value i64){number:=hv_number(api,value);hv_put(api,dict,name,number);hv_drop(api,number)}
fn hv_expected(api HVAPI,row HVCase,hvcc []u8)u64{
 result:=hv_dict(api);hv_put_number(api,result,'BitsPerComponent',row.depth);atoms:=hv_dict(api);data:=unsafe{HVData(voidptr(hv_symbol(api,'_CFDataCreate',true)))(0,u64(hvcc.data),i64(hvcc.len))}
 hv_put(api,atoms,'hvcC',data);hv_put(api,result,'SampleDescriptionExtensionAtoms',atoms);hv_drop(api,data);hv_drop(api,atoms)
 if row.progressive{hv_put_number(api,result,'CVFieldCount',1)}
 hv_put_text(api,result,'CVImageBufferChromaLocationTopField',row.chroma);hv_put_text(api,result,'CVImageBufferChromaLocationBottomField',row.chroma)
 if row.aspect_width!=0{aspect:=hv_dict(api);hv_put_number(api,aspect,'HorizontalSpacing',row.aspect_width);hv_put_number(api,aspect,'VerticalSpacing',row.aspect_height);hv_put(api,result,'CVPixelAspectRatio',aspect);hv_drop(api,aspect)}
 if row.color{for key in ['CVImageBufferColorPrimaries','CVImageBufferTransferFunction','CVImageBufferYCbCrMatrix']!{hv_put_text(api,result,key,'ITU_R_709_2')}}
 hv_put(api,result,'FullRangeVideo',read64(hv_symbol(api,if row.full_range{'_kCFBooleanTrue'}else{'_kCFBooleanFalse'},true)))
 return result
}
fn hv_check_record(api HVAPI,object u64,units [][]u8,header i32){
 query:=unsafe{HVGet(voidptr(hv_symbol(api,'_CMVideoFormatDescriptionGetHEVCParameterSetAtIndex',false)))}
 for index in [u64(0),1,2,3,999]!{for mask in [u32(0),1,2,4,8,15]!{
  mut pointer:=u64(0xfeed);mut size:=u64(0xfeed);mut count:=u64(0xfeed);mut h:=i32(0xfeed)
  status:=query(object,index,if mask&1!=0{&pointer}else{unsafe{nil}},if mask&2!=0{&size}else{unsafe{nil}},if mask&4!=0{&count}else{unsafe{nil}},if mask&8!=0{&h}else{unsafe{nil}})
  valid:=index<u64(units.len)
  assert status==if !valid&&mask&3!=0{-12712}else{0}
  if mask&4!=0{assert count==u64(units.len)}else{assert count==0xfeed};if mask&8!=0{assert h==header}else{assert h==0xfeed}
  if mask&2!=0{assert size==if valid{u64(units[index].len)}else{u64(0)}}else{assert size==0xfeed}
  if mask&1!=0{if valid{assert pointer!=0;assert C.memcmp(unsafe{voidptr(pointer)},units[index].data,usize(units[index].len))==0}else{assert pointer==0}}else{assert pointer==0xfeed}
 }}
}
fn hv_reader(api HVAPI,object u64,units [][]u8,header i32){for _ in 0..16{assert hv_query(api,'_CFRetain',object,true)==object;hv_check_record(api,object,units,header);hv_drop(api,object)}}
fn hv_cases(api HVAPI){
 make:=unsafe{HVMake(voidptr(hv_symbol(api,'_CMVideoFormatDescriptionCreateFromHEVCParameterSets',false)))}
 for row in [HVCase{'40010c01ffff01600000030090000003000003005a959409',8,'42010101600000030090000003000003005aa0050201e16595952930b9a020000003002000000303c1','4401c073c089','0101600000009000000000005af000fcfdf8f800000f03a00001001840010c01ffff01600000030090000003000003005a959409a10001002942010101600000030090000003000003005aa0050201e16595952930b9a020000003002000000303c1a2000100064401c073c089',640,480,true,0,0,false,false,'Left'},
		HVCase{'40010c01ffff01600000030090000003000003005a959409',8,'42010101600000030090000003000003005aa0050201e1d56595952930b9a020000003002000000303c1','4401c073c089','0101600000009000000000005af000fcfdf8f800000f03a00001001840010c01ffff01600000030090000003000003005a959409a10001002a42010101600000030090000003000003005aa0050201e1d56595952930b9a020000003002000000303c1a2000100064401c073c089',638,478,true,0,0,false,false,'Left'},
		HVCase{'40010c01ffff01600000030090000003000003005a959409',8,'42010101600000030090000003000003005aa0050201e16595952930bc39a020000003002000000303c1','4401c073c089','0101600000009000000000005af000fcfdf8f800000f03a00001001840010c01ffff01600000030090000003000003005a959409a10001002a42010101600000030090000003000003005aa0050201e16595952930bc39a020000003002000000303c1a2000100064401c073c089',640,480,true,4,3,false,false,'Left'},
		HVCase{'40010c01ffff01600000030090000003000003005a959409',8,'42010101600000030090000003000003005aa0050201e16595952930b9b808080f08000003000800000300f040','4401c073c089','0101600000009000000000005af000fcfdf8f800000f03a00001001840010c01ffff01600000030090000003000003005a959409a10001002d42010101600000030090000003000003005aa0050201e16595952930b9b808080f08000003000800000300f040a2000100064401c073c089',640,480,true,0,0,true,true,'Left'},
		HVCase{'40010c01ffff01600000030090000003000003005a959409',8,'42010101600000030090000003000003005aa0050201e16595952930bc05a020000003002000000303c1','4401c073c089','0101600000009000000000005af000fcfdf8f800000f03a00001001840010c01ffff01600000030090000003000003005a959409a10001002a42010101600000030090000003000003005aa0050201e16595952930bc05a020000003002000000303c1a2000100064401c073c089',640,480,true,1,1,false,false,'Left'},
		HVCase{'40010c01ffff01600000030090000003000003005a959409',8,'42010101600000030090000003000003005aa0050201e16595952930b9b020000003002000000303c1','4401c073c089','0101600000009000000000005af000fcfdf8f800000f03a00001001840010c01ffff01600000030090000003000003005a959409a10001002942010101600000030090000003000003005aa0050201e16595952930b9b020000003002000000303c1a2000100064401c073c089',640,480,true,0,0,false,true,'Left'},
		HVCase{'40010c01ffff01600000030090000003000003005a959409',8,'42010101600000030090000003000003005aa0050201e16595952930b9a52080000003008000000f04','4401c073c089','0101600000009000000000005af000fcfdf8f800000f03a00001001840010c01ffff01600000030090000003000003005a959409a10001002942010101600000030090000003000003005aa0050201e16595952930b9a52080000003008000000f04a2000100064401c073c089',640,480,true,0,0,false,false,'Center'},
		HVCase{'40010c01ffff01600000030090000003000003005a959409',8,'42010101600000030090000003000003005aa0050201e16595952930bffc001c0015a020000003002000000303c1','4401c073c089','0101600000009000000000005af000fcfdf8f800000f03a00001001840010c01ffff01600000030090000003000003005a959409a10001002e42010101600000030090000003000003005aa0050201e16595952930bffc001c0015a020000003002000000303c1a2000100064401c073c089',640,480,true,7,5,false,false,'Left'},
		HVCase{'40010c01ffff01600000030090000003000003005a959409',8,'42010101600000030090000003000003005aa0050201e16595952930b9a020000003002000000303c1','4401c073c089','0101600000009000000000005af000fcfdf8f800000f03a00001001840010c01ffff01600000030090000003000003005a959409a10001002942010101600000030090000003000003005aa0050201e16595952930b9a020000003002000000303c1a2000100064401c073c089',640,480,true,0,0,false,false,'Left'},
		HVCase{'40010c01ffff01600000030090000003000003005a959809',8,'42010101600000030090000003000003005aa0050201e165959a4932b9a020000003002000000303c1','4401c172b42240','0101600000009000000000005af000fcfdf8f800000f03a00001001840010c01ffff01600000030090000003000003005a959809a10001002942010101600000030090000003000003005aa0050201e165959a4932b9a020000003002000000303c1a2000100074401c172b42240',640,480,true,0,0,false,false,'Left'},
		HVCase{'40010c01ffff02200000030090000003000003005a959409',10,'42010102200000030090000003000003005aa0050201e136595952930b9a020000030002000003003c10','4401c073c089','0102200000009000000000005af000fcfdfafa00000f03a00001001840010c01ffff02200000030090000003000003005a959409a10001002a42010102200000030090000003000003005aa0050201e136595952930b9a020000030002000003003c10a2000100064401c073c089',640,480,true,0,0,false,false,'Left'},
		HVCase{'40010c01ffff01600000030090000003000003005a959409',8,'42010101600000030090000003000003005aa0050201e16595952930b9a020000003002000000303c1','4401c073c089','0101600000009000000000005af000fcfdf8f800000f03a00001001840010c01ffff01600000030090000003000003005a959409a10001002942010101600000030090000003000003005aa0050201e16595952930b9a020000003002000000303c1a2000100064401c073c089',640,480,true,0,0,false,false,'Left'}]!{
  vps:=hex.decode(row.vps)or{panic(err)};sps:=hex.decode(row.sps)or{panic(err)};pps:=hex.decode(row.pps)or{panic(err)}
  units:=[vps,sps,pps]
  for length_size in [i32(1),2,4]!{
   mut inputs:=[vps.clone(),sps.clone(),pps.clone()];mut hvcc:=hex.decode(row.hvcc)or{panic(err)};hvcc[21]=(hvcc[21]&0xfc)|u8(length_size-1)
   mut pointers:=[u64(inputs[2].data),u64(inputs[1].data),u64(inputs[0].data),u64(inputs[1].data)]!;mut sizes:=[u64(inputs[2].len),u64(inputs[1].len),u64(inputs[0].len),u64(inputs[1].len)]!
   mut object:=u64(0);assert make(0,4,unsafe{&pointers[0]},unsafe{&sizes[0]},length_size,0,&object)==0&&object!=0
   for input in inputs{C.memset(input.data,0,usize(input.len))};pointers=[4]u64{};sizes=[4]u64{}
   assert unsafe{HVMedia(voidptr(hv_symbol(api,'_CMFormatDescriptionGetMediaType',false)))(object)}==0x76696465
   assert unsafe{HVMedia(voidptr(hv_symbol(api,'_CMFormatDescriptionGetMediaSubType',false)))(object)}==0x68766331
   assert unsafe{HVDims(voidptr(hv_symbol(api,'_CMVideoFormatDescriptionGetDimensions',false)))(object)}==CMVideoDimensions{row.width,row.height}
   assert hv_query(api,'_CFGetTypeID',object,true)==unsafe{HVType(voidptr(hv_symbol(api,'_CMFormatDescriptionGetTypeID',false)))()}
   hv_check_record(api,object,units,length_size)
   actual:=hv_query(api,'_CMFormatDescriptionGetExtensions',object,false);expected:=hv_expected(api,row,hvcc);assert hv_equal(api,actual,expected)
   for subtype in [u32(0x68766331),0x68657631]!{
    mut reconstructed:=u64(0);assert unsafe{HVGeneric(voidptr(hv_symbol(api,'_CMFormatDescriptionCreate',false)))(0,0x76696465,subtype,expected,&reconstructed)}==0
    hv_check_record(api,reconstructed,units,length_size);hv_drop(api,reconstructed)
   };hv_drop(api,expected)
   mut sample:=u64(0);assert unsafe{HVSample(voidptr(hv_symbol(api,'_CMSampleBufferCreate',false)))(0,0,1,0,0,object,0,0,nil,0,nil,&sample)}==0
   hv_drop(api,object);assert hv_query(api,'_CMSampleBufferGetFormatDescription',sample,false)==object
   mut workers:=[]thread{};for _ in 0..4{workers<<spawn hv_reader(api,object,units,length_size)};workers.wait();unsafe{workers.free()}
   data:=hv_value(api,hv_value(api,actual,'SampleDescriptionExtensionAtoms'),'hvcC');assert hv_query(api,'_CFRetain',data,true)==data
   hv_drop(api,sample);assert hv_query(api,'_CFDataGetLength',data,true)==u64(hvcc.len);assert C.memcmp(unsafe{voidptr(hv_query(api,'_CFDataGetBytePtr',data,true))},hvcc.data,usize(hvcc.len))==0;hv_drop(api,data)
   for input in inputs{unsafe{input.free()}};unsafe{inputs.free();hvcc.free()}
  }
  // Caller extensions override derived fields, are deep snapshots, and can be
  // destroyed immediately after construction. This covers the seventh ABI arg.
  pointers:=[u64(vps.data),u64(sps.data),u64(pps.data)]!;sizes:=[u64(vps.len),u64(sps.len),u64(pps.len)]!
  for key in ['Custom','CVFieldCount','FullRangeVideo']!{
   extra:=hv_dict(api);nested:=hv_dict(api);hv_put_text(api,nested,'Nested','original');hv_put(api,extra,key,nested)
   mut object:=u64(0);assert make(0,3,unsafe{&pointers[0]},unsafe{&sizes[0]},4,extra,&object)==0
   record:=hex.decode(row.hvcc)or{panic(err)};expected:=hv_expected(api,row,record);unsafe{record.free()};hv_put(api,expected,key,nested)
   hv_put_text(api,nested,'Nested','changed');hv_drop(api,nested);hv_drop(api,extra)
   // Expected needs the original value because CFDictionarySetValue retains.
   original:=hv_dict(api);hv_put_text(api,original,'Nested','original');hv_put(api,expected,key,original);hv_drop(api,original)
   assert hv_equal(api,hv_query(api,'_CMFormatDescriptionGetExtensions',object,false),expected)
   hv_drop(api,expected);hv_drop(api,object)
  }
  if row.width==640&&row.aspect_width==0&&!row.color&&!row.full_range&&row.chroma=='Left'&&row.depth==8{
   for cut in u64(0)..u64(sps.len){mut shortened:=[u64(vps.len),cut,u64(pps.len)]!;mut object:=u64(0xfeed);assert make(0,3,unsafe{&pointers[0]},unsafe{&shortened[0]},4,0,&object)==if cut==0{-12712}else{-12714};assert object==0xfeed}
   for item in [0,2]!{for cut in u64(0)..u64(units[item].len){mut shortened:=[u64(vps.len),u64(sps.len),u64(pps.len)]!;shortened[item]=cut;mut object:=u64(0xfeed);status:=make(0,3,unsafe{&pointers[0]},unsafe{&shortened[0]},4,0,&object);if cut>=if item==0{u64(21)}else{u64(3)}{assert status==0;hv_drop(api,object)}else{assert status==if cut==0{-12712}else{-12714};assert object==0xfeed}}}
  }
  for length_size in [i32(-1),0,3,5]!{mut object:=u64(0xfeed);assert make(0,3,unsafe{&pointers[0]},unsafe{&sizes[0]},length_size,0,&object)==-12712&&object==0xfeed}
  for count in [u64(0),1]!{mut object:=u64(0xfeed);assert make(0,count,unsafe{&pointers[0]},unsafe{&sizes[0]},4,0,&object)==-12710&&object==0xfeed}
  mut object:=u64(0);assert make(0,2,unsafe{&pointers[0]},unsafe{&sizes[0]},4,0,&object)==0;hv_check_record(api,object,[vps,sps],4);hv_drop(api,object)
  unsafe{vps.free();sps.free();pps.free();units.free()}
 }
}
fn hv_private(){
 before:=ios_runtime.live;mut out:=u64(0xfeed)
 assert cm_hevc_create(0,3,unsafe{nil},unsafe{nil},4,0,&out)==-12712&&out==0xfeed
 page:=C.mmap(unsafe{nil},4096,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANON,-1,0);assert page!=voidptr(-1)
 pointers:=[u64(page),u64(page),u64(page)]!;sizes:=[u64(65536),2,2]!
 assert cm_hevc_create(0,3,unsafe{&pointers[0]},unsafe{&sizes[0]},4,0,&out)==-12712&&out==0xfeed
 assert C.munmap(page,4096)==0
 // Unsupported extensions and NAL kinds fail without publishing a handle or
 // retaining an extension snapshot. Invalid hvcC records never publish outputs.
 vps:=hex.decode('40010c01ffff01600000030090000003000003005a959409')or{panic(err)}
 sps:=hex.decode('42010101600000030090000003000003005aa0050201e16595952930b9a020000003002000000303c1')or{panic(err)}
 mut nal:=[u8(0x4e),1,0x80]!
 ps:=[u64(vps.data),u64(sps.data),u64(unsafe{&nal[0]})]!;sz:=[u64(vps.len),u64(sps.len),u64(nal.len)]!
 assert cm_hevc_create(0,3,unsafe{&ps[0]},unsafe{&sz[0]},4,0,&out)==-12718&&out==0xfeed
 extra:=hv_dict(HVAPI{});hv_put_text(HVAPI{},extra,'SampleDescriptionExtensionAtoms','unsupported')
 assert cm_hevc_create(0,2,unsafe{&ps[0]},unsafe{&sz[0]},4,extra,&out)==-12718&&out==0xfeed;hv_drop(HVAPI{},extra)
 raw:=cf_dictionary_mutable(0,0,0,0);cf_dictionary_set(raw,1,1)
 assert cm_hevc_create(0,2,unsafe{&ps[0]},unsafe{&sz[0]},4,raw,&out)==-12710&&out==0xfeed;objc_release(raw)
 mut unaligned:=[57]u8{}
 C.memcpy(unsafe{voidptr(u64(&unaligned[0])+1)},unsafe{voidptr(&ps[0])},16)
 C.memcpy(unsafe{voidptr(u64(&unaligned[0])+18)},unsafe{voidptr(&sz[0])},16)
 assert cm_hevc_create(0,2,unsafe{&u64(u64(&unaligned[0])+1)},unsafe{&u64(u64(&unaligned[0])+18)},4,0,unsafe{&u64(u64(&unaligned[0])+35)})==0
 unaligned_object:=h264_word(u64(unsafe{&unaligned[0]})+35)
 assert cm_hevc_parameter(unaligned_object,0,unsafe{&u64(u64(&unaligned[0])+1)},unsafe{&u64(u64(&unaligned[0])+10)},unsafe{&u64(u64(&unaligned[0])+19)},unsafe{&i32(u64(&unaligned[0])+28)})==0
 assert h264_word(u64(unsafe{&unaligned[0]})+10)==u64(vps.len)&&h264_word(u64(unsafe{&unaligned[0]})+19)==2
 objc_release(unaligned_object)
 for cut in 0..32{
  mut record:=[]u8{len:cut};if cut>0{record[0]=1};if cut>22{record[22]=1};if cut>25{record[25]=1}
  metadata:=hv_dict(HVAPI{});atoms:=hv_dict(HVAPI{});data:=cf_data_create(0,u64(record.data),i64(record.len));hv_put(HVAPI{},atoms,'hvcC',data);hv_put(HVAPI{},metadata,'SampleDescriptionExtensionAtoms',atoms);objc_release(data);objc_release(atoms)
  mut object:=u64(0);assert cm_format_create(0,0x76696465,0x68766331,metadata,&object)==0;objc_release(metadata)
  mut pointer:=u64(0xfeed);mut size:=u64(0xfeed);mut count:=u64(0xfeed);mut header:=i32(0xfeed)
  assert cm_hevc_parameter(object,0,&pointer,&size,&count,&header)==-12710&&pointer==0xfeed&&size==0xfeed&&count==0xfeed&&header==0xfeed
  objc_release(object);unsafe{record.free()}
 }
 unsafe{vps.free();sps.free()}
 for lib in ['/System/Library/Frameworks/Foundation.framework/Foundation','/usr/lib/libSystem.B.dylib']!{if _:=runtime_symbol(lib,'_CMVideoFormatDescriptionCreateFromHEVCParameterSets'){assert false}}
 assert cm_hevc_parameter(0,0,unsafe{nil},unsafe{nil},unsafe{nil},unsafe{nil})==-12710
 assert ios_runtime.live==before
}
fn test_hevc_format(){
 $if macos{api:=HVAPI{true,u64(C.dlopen(c'/System/Library/Frameworks/CoreMedia.framework/CoreMedia',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2))};hv_cases(api);println('IOS-HEVC-FORMAT-NATIVE: local libx265 VPS/SPS/PPS fixtures, Main/Main10,crop,aspect,chroma,709/range,exact hvcC,duplicates,borrowed getters,extensions,errors and retained owners')}
 for _ in 0..2{objc_start();hv_cases(HVAPI{});hv_private();assert ios_runtime.live==ios_runtime.framework_objects.len&&ios_runtime.objects.len==ios_runtime.framework_objects.len;objc_stop();assert ios_runtime.live==0&&ios_runtime.objects.len==0}
 println('IOS-HEVC-FORMAT: copied HEVC parameters,bounded RBSP parsing,owned hvcC metadata,deep extension snapshots,dimensions,VUI,borrowed parameters,CF/sample ownership,concurrent readers,two drained runtimes;codec execution unavailable')
}
