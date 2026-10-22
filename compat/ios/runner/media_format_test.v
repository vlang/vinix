// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
$if macos {
 #include <mach/mach.h>
 fn C.mach_task_self() u32
 fn C.vm_region_recurse_64(u32,&u64,&u64,&u32,&i32,&u32)i32
}
struct MFAPI { native bool cm u64 cf u64 }
type MFGeneric=fn(u64,u32,u32,u64,&u64)i32
type MFAudio=fn(u64,&AudioFormat,u64,u64,u64,u64,u64,&u64)i32
type MFVideo=fn(u64,u32,i32,i32,u64,&u64)i32
type MFQuery=fn(u64)u64
type MFType=fn()u64
type MFMedia=fn(u64)u32
type MFDims=fn(u64)CMVideoDimensions
type MFDrop=fn(u64)
type MFEqual=fn(u64,u64)bool
type MFString=fn(u64,&char,u32)u64
type MFDict=fn(u64,i64,u64,u64)u64
type MFSet=fn(u64,u64,u64)
type MFGet=fn(u64,u64)u64
type MFData=fn(u64,i64)u64
type MFLength=fn(u64,i64)
type MFText=fn(u64,&char,i64,u32)bool
type MFArray=fn(u64,u64,i64,u64)u64
type MFNumber=fn(u64,i64,u64)u64
type MFDate=fn(u64,f64)u64
fn mf_symbol(api MFAPI,name string,cf bool)u64{
 if api.native{handle:=if cf{api.cf}else{api.cm};p:=u64(C.dlsym(unsafe{voidptr(handle)},unsafe{&char(name.str+1)}));assert p!=0,name;return p}
 return runtime_symbol(if cf{'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'}else{'/System/Library/Frameworks/CoreMedia.framework/CoreMedia'},name)or{panic(err)}
}
fn mf_query(api MFAPI,name string,object u64,cf bool)u64{return unsafe{MFQuery(voidptr(mf_symbol(api,name,cf)))(object)}}
fn mf_drop(api MFAPI,object u64){unsafe{MFDrop(voidptr(mf_symbol(api,'_CFRelease',true)))(object)}}
fn mf_string(api MFAPI,text &char)u64{return unsafe{MFString(voidptr(mf_symbol(api,'_CFStringCreateWithCString',true)))(0,text,0x08000100)}}
fn mf_dict(api MFAPI)u64{return unsafe{MFDict(voidptr(mf_symbol(api,'_CFDictionaryCreateMutable',true)))(0,0,mf_symbol(api,'_kCFTypeDictionaryKeyCallBacks',true),mf_symbol(api,'_kCFTypeDictionaryValueCallBacks',true))}}
fn mf_set(api MFAPI,dict u64,key u64,value u64){unsafe{MFSet(voidptr(mf_symbol(api,'_CFDictionarySetValue',true)))(dict,key,value)}}
fn mf_get(api MFAPI,dict u64,key u64)u64{return unsafe{MFGet(voidptr(mf_symbol(api,'_CFDictionaryGetValue',true)))(dict,key)}}
fn mf_equal(api MFAPI,left u64,right u64,cf bool)bool{return unsafe{MFEqual(voidptr(mf_symbol(api,if cf{'_CFEqual'}else{'_CMFormatDescriptionEqual'},cf)))(left,right)}}
fn mf_reader(api MFAPI,format u64,media u32,subtype u32){for _ in 0..64{assert mf_query(api,'_CFRetain',format,true)==format;assert unsafe{MFMedia(voidptr(mf_symbol(api,'_CMFormatDescriptionGetMediaType',false)))(format)}==media;assert unsafe{MFMedia(voidptr(mf_symbol(api,'_CMFormatDescriptionGetMediaSubType',false)))(format)}==subtype;mf_drop(api,format)}}
fn mf_extensions(api MFAPI){
 make:=unsafe{MFGeneric(voidptr(mf_symbol(api,'_CMFormatDescriptionCreate',false)))}
 key:=mf_string(api,c'vinix-nested');inner_key:=mf_string(api,c'vinix-data');source:=mf_dict(api);inner:=mf_dict(api)
 primaries_key:=mf_string(api,c'CVImageBufferColorPrimaries');primaries:=read64(mf_symbol(api,'_kCMFormatDescriptionColorPrimaries_P3_D65',false));mf_set(api,source,primaries_key,primaries)
 data:=unsafe{MFData(voidptr(mf_symbol(api,'_CFDataCreateMutable',true)))(0,3)};unsafe{MFLength(voidptr(mf_symbol(api,'_CFDataSetLength',true)))(data,3)}
 bytes:=mf_query(api,'_CFDataGetMutableBytePtr',data,true);unsafe{*(&u8(bytes))=0x31;*(&u8(bytes+1))=0x41;*(&u8(bytes+2))=0x59}
 mf_set(api,inner,inner_key,data);mf_set(api,source,key,inner)
 array_key:=mf_string(api,c'vinix-array');integer:=i64(42);number:=unsafe{MFNumber(voidptr(mf_symbol(api,'_CFNumberCreate',true)))(0,4,u64(&integer))};date:=unsafe{MFDate(voidptr(mf_symbol(api,'_CFDateCreate',true)))(0,12345.25)}
 values:=[inner,number,date,read64(mf_symbol(api,'_kCFBooleanTrue',true))]!
 array:=unsafe{MFArray(voidptr(mf_symbol(api,'_CFArrayCreate',true)))(0,u64(&values[0]),4,mf_symbol(api,'_kCFTypeArrayCallBacks',true))};mf_set(api,source,array_key,array)
 mut first:=u64(0);mut same:=u64(0);assert make(0,0x6d657461,0x6d656278,source,&first)==0;assert make(0,0x6d657461,0x6d656278,source,&same)==0
 assert mf_equal(api,first,same,false)&&mf_equal(api,first,same,true)
 // Native format descriptions have identity hashes even when CFEqual succeeds.
 if !api.native{assert mf_query(api,'_CFHash',first,true)==mf_query(api,'_CFHash',same,true)}
 snapshot:=mf_query(api,'_CMFormatDescriptionGetExtensions',first,false);assert snapshot!=0;assert mf_equal(api,snapshot,source,true);assert mf_query(api,'_CFRetain',snapshot,true)==snapshot
 assert mf_equal(api,mf_get(api,snapshot,primaries_key),primaries,true)
 assert mf_query(api,'_CFArrayGetCount',mf_get(api,snapshot,array_key),true)==4
 nested:=mf_get(api,snapshot,key);copy:=mf_get(api,nested,inner_key);assert copy!=0&&mf_query(api,'_CFDataGetLength',copy,true)==3
 // A deep copy stays unchanged when nested mutable bytes are reused.
 unsafe{*(&u8(bytes))=0x99};replacement:=mf_string(api,c'replaced');mf_set(api,source,key,replacement)
 assert unsafe{*(&u8(mf_query(api,'_CFDataGetBytePtr',copy,true)))}==0x31
 assert unsafe{MFGet(voidptr(mf_symbol(api,'_CMFormatDescriptionGetExtension',false)))(first,key)}==nested
 mut different:=u64(0);assert make(0,0x6d657461,0x6d656278,source,&different)==0;assert !mf_equal(api,first,different,false)
 mf_drop(api,source);mf_drop(api,inner);mf_drop(api,data);mf_drop(api,replacement);mf_drop(api,first);mf_drop(api,same);mf_drop(api,different)
 mf_drop(api,array);mf_drop(api,number);mf_drop(api,date);mf_drop(api,array_key)
 assert unsafe{*(&u8(mf_query(api,'_CFDataGetBytePtr',copy,true)))}==0x31
 assert mf_equal(api,mf_get(api,snapshot,primaries_key),primaries,true)
 mf_drop(api,snapshot);mf_drop(api,key);mf_drop(api,inner_key);mf_drop(api,primaries_key)
}
fn mf_audio_equality(api MFAPI){
 create:=unsafe{MFAudio(voidptr(mf_symbol(api,'_CMAudioFormatDescriptionCreate',false)))}
 base:=AudioFormat{48000,0x6c70636d,12,4,1,4,2,16,0};mut first:=u64(0);assert create(0,&base,0,0,0,0,0,&first)==0
 for i,format in [AudioFormat{48000,0x6c70636d,12,4,1,4,2,16,0xfeed},AudioFormat{48001,0x6c70636d,12,4,1,4,2,16,0},AudioFormat{48000,0x6c70636d,4,4,1,4,2,16,0}]!{mut second:=u64(0);assert create(0,&format,0,0,0,0,0,&second)==0;assert mf_equal(api,first,second,false)==(i==0)&&mf_equal(api,first,second,true)==(i==0);mf_drop(api,second)}
 mf_drop(api,first)
}
fn mf_cases(api MFAPI){
 make:=unsafe{MFGeneric(voidptr(mf_symbol(api,'_CMFormatDescriptionCreate',false)))};audio:=unsafe{MFAudio(voidptr(mf_symbol(api,'_CMAudioFormatDescriptionCreate',false)))};video:=unsafe{MFVideo(voidptr(mf_symbol(api,'_CMVideoFormatDescriptionCreate',false)))}
 assert sizeof(AudioFormat)==40&&sizeof(CMVideoDimensions)==8
 mut bad:=u64(0xfeed);assert make(0,0,1,0,&bad)==-12710&&bad==0xfeed;assert make(0,0x6d657461,1,0,unsafe{nil})==-12710
 bad=0xfeed;assert audio(0,unsafe{nil},0,0,0,0,0,&bad)==-12710&&bad==0
 zero:=AudioFormat{};bad=0xfeed;assert audio(0,&zero,0,0,0,0,0,&bad)==-12710&&bad==0
 for pair in [[u32(0x736f756e),0x6c70636d]!,[u32(0x76696465),0x61766331]!,[u32(0x6d657461),0x6d656278]!,[u32(0x78787878),1]!]!{
  mut object:=u64(0);assert make(0,pair[0],pair[1],0,&object)==0&&object!=0
  assert mf_query(api,'_CFGetTypeID',object,true)==unsafe{MFType(voidptr(mf_symbol(api,'_CMFormatDescriptionGetTypeID',false)))()}
  mf_reader(api,object,pair[0],pair[1]);assert mf_query(api,'_CMFormatDescriptionGetExtensions',object,false)==0
  p:=mf_query(api,'_CMAudioFormatDescriptionGetStreamBasicDescription',object,false)
  if pair[0]==0x736f756e{assert p!=0&&C.memcmp(unsafe{voidptr(p)},&zero,sizeof(AudioFormat))==0}else{assert p==0}
  assert unsafe{MFDims(voidptr(mf_symbol(api,'_CMVideoFormatDescriptionGetDimensions',false)))(object)}==CMVideoDimensions{}
  mf_drop(api,object)
 }
 for format in [AudioFormat{48000,0x6c70636d,12,4,1,4,2,16,0xfeed},AudioFormat{44100,0x6c70636d,41,4,1,4,2,32,0},AudioFormat{48000,0x61616320,0,0,1024,0,2,0,0},AudioFormat{-1,0x6c70636d,0,0,0,0,0,0,0},AudioFormat{48000,0,12,4,1,4,2,16,0}]!{
  mut input:=format;mut object:=u64(0);assert audio(0,&input,0,0,0,0,0,&object)==0&&object!=0
  pointer:=mf_query(api,'_CMAudioFormatDescriptionGetStreamBasicDescription',object,false);assert pointer!=0&&C.memcmp(unsafe{voidptr(pointer)},&format,sizeof(AudioFormat))==0
  input=AudioFormat{};assert C.memcmp(unsafe{voidptr(pointer)},&format,sizeof(AudioFormat))==0
  mut same:=u64(0);assert audio(0,&format,0,0,0,0,0,&same)==0&&mf_equal(api,object,same,false)&&mf_equal(api,object,same,true)
  mut readers:=[]thread{};for _ in 0..8{readers<<spawn mf_reader(api,object,0x736f756e,format.id)};readers.wait();unsafe{readers.free()}
  assert mf_query(api,'_CFRetain',object,true)==object;mf_drop(api,object);assert mf_query(api,'_CMAudioFormatDescriptionGetStreamBasicDescription',object,false)==pointer;mf_drop(api,object);mf_drop(api,same)
 }
 for wh in [[i32(7),3]!,[i32(0),3]!,[i32(-1),3]!,[i32(7),0]!]!{
  mut object:=u64(0);assert video(0,0x61766331,wh[0],wh[1],0,&object)==0
  assert unsafe{MFDims(voidptr(mf_symbol(api,'_CMVideoFormatDescriptionGetDimensions',false)))(object)}==CMVideoDimensions{wh[0],wh[1]}
  assert mf_query(api,'_CMAudioFormatDescriptionGetStreamBasicDescription',object,false)==0;mf_drop(api,object)
 }
 assert mf_equal(api,0,0,false)
 mf_extensions(api)
 mf_audio_equality(api)
 for pair in mf_constant_pairs(){
  cell:=mf_symbol(api,pair[0],false);object:=read64(cell);assert cell!=0&&cell%8==0&&object!=0&&object!=cell&&cell==mf_symbol(api,pair[0],false)
  assert mf_query(api,'_CFGetTypeID',object,true)==unsafe{MFType(voidptr(mf_symbol(api,'_CFStringGetTypeID',true)))()}
  assert mf_query(api,'_CFStringGetLength',object,true)==u64(pair[1].len)
  owned:=mf_string(api,unsafe{&char(pair[1].str)});assert mf_equal(api,object,owned,true)&&mf_query(api,'_CFHash',object,true)==mf_query(api,'_CFHash',owned,true)
  assert mf_query(api,'_CFRetain',object,true)==object;mf_drop(api,object);mf_drop(api,owned)
  mut text:=[128]u8{};assert unsafe{MFText(voidptr(mf_symbol(api,'_CFStringGetCString',true)))(object,&char(&text[0]),128,0x08000100)};assert text[pair[1].len]==0&&C.memcmp(&text[0],pair[1].str,usize(pair[1].len))==0
 }
 primaries:=mf_symbol(api,'_kCMFormatDescriptionColorPrimaries_ITU_R_2020',false);matrix:=mf_symbol(api,'_kCMFormatDescriptionYCbCrMatrix_ITU_R_2020',false)
 assert primaries!=matrix&&read64(primaries)==read64(matrix)
}
fn mf_private_failures(){
 value:=objc_new(ios_runtime.names['NSObject']);dict:=mf_dict(MFAPI{});key:=owned_string('invalid');mf_set(MFAPI{},dict,key,value);before:=ios_runtime.live;mut out:=u64(0xfeed)
 assert cm_format_create(0,0x6d657461,1,dict,&out)==-12710&&out==0xfeed&&ios_runtime.live==before
 objc_release(dict);objc_release(key);objc_release(value)
 format:=AudioFormat{48000,0x6c70636d,12,4,1,4,2,16,0};out=0xfeed;assert cm_audio_create(0,&format,12,0,0,0,0,&out)==-12718&&out==0
 assert (runtime_symbol('/System/Library/Frameworks/CoreMedia.framework/CoreMedia','_CMBlockBufferCreateWithMemoryBlock')or{panic(err)})!=0
 for name in ['_CMVideoFormatDescriptionCreateForImageBuffer']!{if _:=runtime_symbol('/System/Library/Frameworks/CoreMedia.framework/CoreMedia',name){assert false}}
 for name in ['_CMAudioFormatDescriptionGetStreamBasicDescription','_CMFormatDescriptionGetExtensions','_kCMFormatDescriptionTransferFunction_sRGB','_kCMFormatDescriptionColorPrimaries_P3_D65']!{for lib in ['/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/CoreVideo.framework/CoreVideo','/usr/lib/libSystem.B.dylib']!{if _:=runtime_symbol(lib,name){assert false}}}
}
fn mf_constant_pairs() [11][2]string {
 return [['_kCMFormatDescriptionExtension_FullRangeVideo','FullRangeVideo']!,['_kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms','SampleDescriptionExtensionAtoms']!,['_kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG','ITU_R_2100_HLG']!,['_kCMFormatDescriptionTransferFunction_Linear','Linear']!,['_kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ','SMPTE_ST_2084_PQ']!,['_kCMFormatDescriptionTransferFunction_SMPTE_ST_428_1','SMPTE_ST_428_1']!,['_kCMFormatDescriptionTransferFunction_sRGB','IEC_sRGB']!,['_kCMFormatDescriptionColorPrimaries_P3_D65','P3_D65']!,['_kCMFormatDescriptionColorPrimaries_DCI_P3','DCI_P3']!,['_kCMFormatDescriptionColorPrimaries_ITU_R_2020','ITU_R_2020']!,['_kCMFormatDescriptionYCbCrMatrix_ITU_R_2020','ITU_R_2020']!]!
}
fn mf_constant_reader(offset int){
 pairs:=mf_constant_pairs();mut cells:=[11]u64{}
 for turn in 0..32{for step in 0..pairs.len{index:=(offset+step)%pairs.len;pair:=pairs[index];cell:=coremedia_constant_symbol(pair[0])or{panic('missing CoreMedia key')};assert string_text(read64(cell))==pair[1];if turn==0{cells[index]=cell}else{assert cells[index]==cell}}}
}
fn mf_constants_start(){
 assert ios_runtime.coremedia_constants_arena==0
 for name in ['kCMFormatDescriptionColorPrimaries_P3_D65','_kCMFormatDescriptionColorPrimaries_P3_D65_suffix','_kCMFormatDescriptionColorPrimaries_P3_DCI']!{if _:=coremedia_constant_symbol(name){assert false}}
 assert ios_runtime.coremedia_constants_arena==0
 ios_runtime.swift_concurrency_retired=true
 if _:=coremedia_constant_symbol('_kCMFormatDescriptionColorPrimaries_P3_D65'){assert false}
 assert ios_runtime.coremedia_constants_arena==0
 ios_runtime.swift_concurrency_retired=false
}
fn mf_constants_stop_check(arena u64,objects [11]u64){
 assert ios_runtime.coremedia_constants_arena==0&&ios_runtime.live==0&&ios_runtime.objects.len==0
 for object in objects{assert object !in ios_runtime.constants}
 // mprotect must fail for the retired mapping. No access to unmapped storage.
 assert C.mprotect(unsafe{voidptr(arena)},usize(C.getpagesize()),C.PROT_READ)==-1
}
fn mf_maps_hex(maps string,first int)(u64,int){
 mut cursor:=first;mut value:=u64(0)
 for cursor<maps.len{
  digit:=match maps[cursor]{`0`...`9`{u64(maps[cursor]-`0`)} `a`...`f`{u64(maps[cursor]-`a`+10)} else{break}}
  assert cursor-first<16;value=value*16+digit;cursor++
 }
 assert cursor>first;return value,cursor
}
fn mf_constants_permissions(arena u64){
 page:=u64(C.getpagesize())
 $if macos{
  mut start:=arena;mut size:=u64(0);mut info:=[64]i32{};mut count:=u32(C.VM_REGION_SUBMAP_INFO_COUNT_64);mut depth:=u32(999)
  assert C.vm_region_recurse_64(C.mach_task_self(),&start,&size,&depth,unsafe{&info[0]},&count)==0
  assert start<=arena&&arena+page<=start+size&&info[0]==C.PROT_READ
 }$else{
  // Own one snapshot; do not allocate line/field substrings under -gc none.
  maps:=os.read_file('/proc/self/maps')or{panic(err)};defer{unsafe{maps.free()}}
  mut cursor:=0
  for cursor<maps.len{
   start,after_start:=mf_maps_hex(maps,cursor);cursor=after_start;assert cursor<maps.len&&maps[cursor]==`-`;cursor++
   end,after_end:=mf_maps_hex(maps,cursor);cursor=after_end;assert cursor<maps.len&&maps[cursor]==` `
   for cursor<maps.len&&maps[cursor]==` `{cursor++};assert cursor+4<=maps.len
   if arena>=start&&arena<end{assert page<=end-arena&&maps[cursor]==`r`&&maps[cursor+1]==`-`&&maps[cursor+2]==`-`&&maps[cursor+3]==`p`;return}
   for cursor<maps.len&&maps[cursor]!=`\n`{cursor++};if cursor<maps.len{cursor++}
  }
  assert false,'CoreMedia constants mapping absent'
 }
}
fn test_media_format(){
 $if macos{api:=MFAPI{true,u64(C.dlopen(c'/System/Library/Frameworks/CoreMedia.framework/CoreMedia',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2))};mf_cases(api);println('IOS-MEDIA-FORMAT-NATIVE: generic/audio/video construction,owned ASBD copies,signed dimensions,deep extension snapshots,CF equality/ownership,concurrent readers and exact metadata strings')}
 for _ in 0..2{
  objc_start();mf_constants_start();mut readers:=[]thread{};for offset in 0..8{readers<<spawn mf_constant_reader(offset)};readers.wait();unsafe{readers.free()}
  mf_cases(MFAPI{});mf_private_failures();arena:=ios_runtime.coremedia_constants_arena;mf_constants_permissions(arena);mut objects:=[11]u64{}
  for i,pair in mf_constant_pairs(){cell:=coremedia_constant_symbol(pair[0])or{panic('missing CoreMedia key')};assert cell==arena+u64(i*8);objects[i]=read64(cell);assert objects[i]==if i==10{objects[9]}else{arena+88+u64(i*32)};assert read64(objects[i]+16)>=arena+440&&read64(objects[i]+16)+u64(pair[1].len)<arena+u64(C.getpagesize());assert objects[i] in ios_runtime.constants}
  ios_runtime.swift_concurrency_retired=true
  assert (coremedia_constant_symbol('_kCMFormatDescriptionColorPrimaries_P3_D65')or{panic('cached global retired too early')})==arena+56
  ios_runtime.swift_concurrency_retired=false
  assert ios_runtime.live==ios_runtime.framework_objects.len&&ios_runtime.objects.len==ios_runtime.framework_objects.len;for object in ios_runtime.framework_objects{assert obj_header(object).refs==1}
  objc_stop();mf_constants_stop_check(arena,objects)
 }
 println('IOS-MEDIA-FORMAT: owned format descriptions,deep immutable extension snapshots,ASBD pointers,signed dimensions,CF equality/ownership,eleven sealed globals with P3/2020 color strings and shared 2020 identity,eight cold readers,two drained/unmapped runtimes;image sample buffers and codecs remain unavailable')
}
