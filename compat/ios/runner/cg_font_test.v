// SPDX-License-Identifier: GPL-2.0-or-later
// Fixture: HarfBuzz subset of desktop/fonts/VinixJapanese-Regular.ttf.
// Font data remains under the SIL OFL in desktop/FONT-LICENSE.txt.
module main
import os
import encoding.hex
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
struct GFAPI {native bool cg u64 cf u64 ct u64}
type GFQuery=fn(u64)u64
type GFUnits=fn(u64)i32
type GFType=fn()u64
type GFProvider=fn(voidptr,voidptr,u64,u64)u64
type GFTable=fn(u64,u32)u64
type GFAt=fn(u64,i64)u64
type GFDrop=fn(u64)
type GFString=fn(u64,&char,u32)u64
type GFText=fn(u64,&char,i64,u32)bool
type GFURL=fn(u64,&u8,i64,bool)u64
type GFRegister=fn(u64,u32,&u64)bool
fn gf_symbol(api GFAPI,name string,framework string)u64{
 if api.native{handle:=match framework{'CoreGraphics'{api.cg}'CoreText'{api.ct}else{api.cf}};pointer:=u64(C.dlsym(unsafe{voidptr(handle)},unsafe{&char(name.str+1)}));assert pointer!=0,name;return pointer}
 return runtime_symbol('/System/Library/Frameworks/'+framework+'.framework/'+framework,name)or{panic(err)}
}
fn gf_query(api GFAPI,name string,object u64,framework string)u64{return unsafe{GFQuery(voidptr(gf_symbol(api,name,framework)))(object)}}
fn gf_drop(api GFAPI,object u64){unsafe{GFDrop(voidptr(gf_symbol(api,'_CGFontRelease','CoreGraphics')))(object)}}
fn gf_string(api GFAPI,text string)u64{return unsafe{GFString(voidptr(gf_symbol(api,'_CFStringCreateWithCString','CoreFoundation')))(0,&char(text.str),0x08000100)}}
fn gf_text(api GFAPI,object u64)string{mut bytes:=[1024]u8{};assert unsafe{GFText(voidptr(gf_symbol(api,'_CFStringGetCString','CoreFoundation')))(object,&char(&bytes[0]),1024,0x08000100)};return unsafe{(&char(&bytes[0])).vstring()}.clone()}
fn gf_be(data []u8,at int,count int)u32{mut value:=u32(0);for i in 0..count{value=(value<<8)|data[at+i]};return value}
fn gf_put(mut data []u8,at int,value u32,count int){for i in 0..count{data[at+i]=u8(value>>u32((count-i-1)*8))}}
fn gf_fixture()[]u8{return hex.decode('000100000012010000040020424153456bfb792900000354000000de47504f5344744c75000001600000001e475355426d22591000000270000000404f532f32bc07458e000002f4000000605354415478926cdd000002080000002e636d61706740f0ed000002b00000004467617370000000100000013400000008676c79661657c73800000434000001a0686561641f35ca45000002380000003668686561087202d9000001c000000024686d747804be00830000013c0000000a6c6f636100f10063000001480000000a6d617870001900cf00000180000000206e616d6527e94312000005d4000001f8706f7374ff860032000001a0000000207072657068068c850000012c000000077668656105de120d000001e400000024766d7478049f0029000001540000000ab801ff85b0048d0000010001ffff000f03e8006400b0001f00260000000000000021006300d0000003e80000006c0029004b000000010000000a001c001c000144464c540008000400000000ffff00000000000000010000000400ce0014000000000001000000000000000000000000000000000003000000000000ff8300320000000000000000000000000000000000000000000100000488fee0000003e8000f000f03d90001000000000000000000000000000000010001100001f4fe0c000003e80017001803d000000001000000000000000000000000000100010001000800010000001400010000001c00027767687401010000000200030000000200020190000002bc0000000000010000000201068e5e1de75f0f3cf5000303e800000000dcb0221f00000000df856344000fffa003d9035900000006000200000000000000010000000a003e003e000644464c54002a6379726c00266772656b002668616e6900266b616e6100266c61746e002600000000000400000000ffff000000000000000200000003000000140003000100000014000400300000000800080002000065e5672c8a9effff000065e5672c8a9effff9a1c98d6756500010000000000000000000403e6019000050000028a02580000004b028a02580000015e003201450000020b0200000000000000000000000800000000000000000000004144424f004065e58a9e0370ff880000048801206006010700000000021f02dd00000020000600010001006a000c0000000000c00004000644464c5400386379726c00266772656b002668616e6900386b616e6100386c61746e00260006000000000003000400280022007c001e0006000000000002000400160010006a000c00010078000303be00000003002a000000620004000644464c5400386379726c00266772656b002668616e6900386b616e6100386c61746e002600060000000000030004002c00260022001e00060000000000020004001a00140010000c000100000001ff880003034600000003ffb20000000469636662696366746964656f726f6d6e0000000300b0ffbb034003040007000b000f000053211123112111231321152103211521b0029050fe0d4d34022efdd2020231fdcf0304fcbc02f9fd0201ef4afee74b000005001fffb003cc034700030007000b00190026000053211521132115211333112303170e02072e02273e03371e02170e02072e0227410368fc98c701d2fe2ec44f4f18442d829e56061413093f776b569d287e9d5609151407579f802c02754cfe8e4c02dcfc6902ac166ac19b320917160821627b8a455fb18d2a0816190b3199c068000c0026ffb003c403250007000d0018001c002000240028002c00300034003c00400000412111231121112303211523352137170e0207233e032721152103211521132115210121152113211521032115210321152113331123353335232733112301df01a749fee9471b01a748fea191490818180b49091212109a01effe111f022efdd26a0166fe9afe56011afee6060113feed06011afee630016cfe9453fbfbb8b82542420118fe9c0120fedc02caf5b4d1073d8d842f24606a684742fec643febe4402363c014d3cfea23b014f3efea1fedd3da83efeaf0000000800660003000104090000009c00f60003000104090001001c00da0003000104090002000e00cc0003000104090003002a00a20003000104090004002c00760003000104090005006a000c0003000104090006002a00a20003000104090101000c000000570065006900670068007400560065007200730069006f006e00200032002e003000300034002d00480032003b0068006f00740063006f006e007600200031002e0030002e003100310038003b006d0061006b0065006f0074006600650078006500200032002e0035002e0036003500360030003300560069006e006900780020004a006100700061006e00650073006500200052006500670075006c0061007200560069006e00690078004a006100700061006e006500730065002d0052006500670075006c006100720052006500670075006c0061007200560069006e006900780020004a006100700061006e00650073006500280063002900200032003000310034002d0032003000320031002000410064006f00620065002000280068007400740070003a002f002f007700770077002e00610064006f00620065002e0063006f006d002f0029002c0020007700690074006800200052006500730065007200760065006400200046006f006e00740020004e0061006d0065002000270053006f00750072006300650027002e')or{panic(err)}}
fn gf_input(raw []u8,mode int)[]u8{
 mut data:=raw.clone();n:=int(gf_be(raw,4,2))
 if mode==1{for i in 0..n/2{for j in 0..16{temporary:=data[12+i*16+j];data[12+i*16+j]=data[12+(n-i-1)*16+j];data[12+(n-i-1)*16+j]=temporary}}}
 if mode==2{data[0]=0xff};if mode==3{shortened:=data[..12].clone();unsafe{data.free()};return shortened}
 if mode==4{mut collection:=[]u8{len:raw.len+20};gf_put(mut collection,0,0x74746366,4);gf_put(mut collection,4,0x10000,4);gf_put(mut collection,8,2,4);gf_put(mut collection,12,20,4);gf_put(mut collection,16,20,4);for i,b in raw{collection[20+i]=b};for i in 0..n{position:=20+12+i*16+8;gf_put(mut collection,position,gf_be(collection,position,4)+20,4)};unsafe{data.free()};return collection}
 if mode==5{end:=12+n*16;mut extended:=[]u8{len:raw.len+16};for i in 0..end{extended[i]=raw[i]};for i in end..raw.len{extended[i+16]=raw[i]};gf_put(mut extended,4,u32(n+1),2);for i in 0..n{position:=12+i*16+8;gf_put(mut extended,position,gf_be(extended,position,4)+16,4)};gf_put(mut extended,end,0x7a7a7a7a,4);gf_put(mut extended,end+8,u32(extended.len),4);unsafe{data.free()};return extended}
 return data
}
fn gf_released(info voidptr,_data voidptr,_size u64){unsafe{*(&u64(info))+=1}}
fn gf_reader(api GFAPI,font u64){
 for _ in 0..8{assert gf_query(api,'_CGFontRetain',font,'CoreGraphics')==font;data:=unsafe{GFTable(voidptr(gf_symbol(api,'_CGFontCopyTableForTag','CoreGraphics')))(font,0x68656164)};assert data!=0&&gf_query(api,'_CFDataGetLength',data,'CoreFoundation')==54;gf_drop(api,data);gf_drop(api,font)}
}
fn gf_cases(api GFAPI){
 raw:=gf_fixture();defer{unsafe{raw.free()}}
 make:=unsafe{GFQuery(voidptr(gf_symbol(api,'_CGFontCreateWithDataProvider','CoreGraphics')))};provider:=unsafe{GFProvider(voidptr(gf_symbol(api,'_CGDataProviderCreateWithData','CoreGraphics')))};table:=unsafe{GFTable(voidptr(gf_symbol(api,'_CGFontCopyTableForTag','CoreGraphics')))};at:=unsafe{GFAt(voidptr(gf_symbol(api,'_CFArrayGetValueAtIndex','CoreFoundation')))}
 for mode in 0..6{
  data:=gf_input(raw,mode);gold:=data.clone();mut calls:=u64(0);source:=provider(unsafe{voidptr(&calls)},unsafe{voidptr(data.data)},u64(data.len),u64(unsafe{voidptr(gf_released)}));font:=make(source)
  if mode in [2,3]!{assert font==0&&calls==0;gf_drop(api,source);assert calls==1;unsafe{data.free();gold.free()};continue}
  assert font!=0&&calls==0
  assert gf_query(api,'_CFGetTypeID',font,'CoreFoundation')==unsafe{GFType(voidptr(gf_symbol(api,'_CGFontGetTypeID','CoreGraphics')))()}
  for name,expected in {'_CGFontCopyPostScriptName':'VinixJapanese-Regular','_CGFontCopyFullName':'Vinix Japanese Regular'}{value:=gf_query(api,name,font,'CoreGraphics');assert value!=0;actual:=gf_text(api,value);assert actual==expected;unsafe{actual.free()};gf_drop(api,value)}
  tags:=gf_query(api,'_CGFontCopyTableTags',font,'CoreGraphics');count:=gf_query(api,'_CFArrayGetCount',tags,'CoreFoundation');base:=if mode==4{20}else{0};assert count==u64(gf_be(data,base+4,2))
  mut copies:=[]u64{cap:int(count)}
  for i in 0..int(count){record:=base+12+i*16;tag:=gf_be(gold,record,4);assert at(tags,i64(i))==u64(tag)
   value:=table(font,tag);size:=gf_be(gold,record+12,4);if size==0{assert value==0}else{assert value!=0;assert gf_query(api,'_CFDataGetLength',value,'CoreFoundation')==size};copies<<value
  }
  assert table(font,0)==0&&table(font,0xffffffff)==0
  assert gf_query(api,'_CGFontGetNumberOfGlyphs',font,'CoreGraphics')==4
  assert unsafe{GFUnits(voidptr(gf_symbol(api,'_CGFontGetUnitsPerEm','CoreGraphics')))(font)}==1000
  mut workers:=[]thread{};for _ in 0..4{workers<<spawn gf_reader(api,font)};workers.wait();unsafe{workers.free()}
  gf_drop(api,source);assert calls==0;gf_drop(api,font);assert calls==1
  // Native CFData aliases the provider's immutable input; retain that input
  // through its views. Vinix's owned copies also survive discarded input.
  if !api.native { C.memset(data.data,0,usize(data.len)) }
  for i,value in copies{record:=base+12+i*16;offset:=gf_be(gold,record+8,4);size:=gf_be(gold,record+12,4);if size!=0{pointer:=gf_query(api,'_CFDataGetBytePtr',value,'CoreFoundation');assert C.memcmp(unsafe{voidptr(pointer)},unsafe{voidptr(u64(gold.data)+offset)},usize(size))==0,'table bytes mode=${mode} tag=${gf_be(gold,record,4):08x}'};gf_drop(api,value)}
  // Raw tag arrays survive the font and contain integers, never CFNumbers.
  assert at(tags,0)==u64(gf_be(gold,base+12,4));gf_drop(api,tags);assert calls==1
  unsafe{copies.free();data.free();gold.free()}
 }
 for name in ['_CGFontCreateWithDataProvider','_CGFontCopyTableTags','_CGFontCopyPostScriptName','_CGFontCopyFullName','_CGFontRetain','_CGFontGetNumberOfGlyphs']!{assert gf_query(api,name,0,'CoreGraphics')==0};assert unsafe{GFUnits(voidptr(gf_symbol(api,'_CGFontGetUnitsPerEm','CoreGraphics')))(0)}==0;assert table(0,0x68656164)==0;gf_drop(api,0)
}
fn gf_registered(api GFAPI){
 raw:=gf_fixture();defer{unsafe{raw.free()}}
 path:=os.temp_dir()+'/vinix-cg-font-'+os.getpid().str()+if api.native{'-native.ttf'}else{'-runtime.ttf'};os.write_file_array(path,raw)or{panic(err)};defer{os.rm(path)or{panic(err)};unsafe{path.free()}}
 mut url:=u64(0)
 if api.native{url=unsafe{GFURL(voidptr(gf_symbol(api,'_CFURLCreateFromFileSystemRepresentation','CoreFoundation')))(0,raw_path(path),i64(path.len),false)}}else{url=objc_allocate(ios_runtime.names['NSURL']);mut header:=obj_header(url);header.fields[0]=owned_string(path)}
 assert url!=0&&unsafe{GFRegister(voidptr(gf_symbol(api,'_CTFontManagerRegisterFontsForURL','CoreText')))(url,1,nil)}
 for name in ['VinixJapanese-Regular','Vinix Japanese Regular']!{text:=gf_string(api,name);font:=gf_query(api,'_CGFontCreateWithFontName',text,'CoreGraphics');gf_drop(api,text);assert font!=0
  value:=unsafe{GFTable(voidptr(gf_symbol(api,'_CGFontCopyTableForTag','CoreGraphics')))(font,0x68656164)};assert value!=0&&gf_query(api,'_CFDataGetLength',value,'CoreFoundation')==54;gf_drop(api,value);gf_drop(api,font)
 }
 missing:=gf_string(api,'VinixMissingFont-4f30d1');assert gf_query(api,'_CGFontCreateWithFontName',missing,'CoreGraphics')==0;gf_drop(api,missing)
 if api.native{assert unsafe{GFRegister(voidptr(gf_symbol(api,'_CTFontManagerUnregisterFontsForURL','CoreText')))(url,1,nil)}}
 gf_drop(api,url)
}
fn raw_path(path string)&u8{return path.str}
fn gf_private(){
 before:=ios_runtime.live
 page:=C.mmap(unsafe{nil},4096,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANON,-1,0);assert page!=voidptr(-1)
 assert cg_font_bytes(u64(page),16777217,0,0)==0&&cg_font_bytes(u64(page),0,0,0)==0;assert C.munmap(page,4096)==0
 raw:=gf_fixture();mut malformed:=raw.clone()
 for variant in 0..4{C.memcpy(malformed.data,raw.data,usize(raw.len));if variant==0{gf_put(mut malformed,4,4097,2)}else if variant==1{gf_put(mut malformed,20,0xffffffff,4)}else if variant==2{gf_put(mut malformed,24,0xffffffff,4)}else{gf_put(mut malformed,28,gf_be(raw,12,4),4)}
  assert cg_font_bytes(u64(malformed.data),u64(malformed.len),0,0)==0}
 for lib in ['/System/Library/Frameworks/CoreText.framework/CoreText','/System/Library/Frameworks/Foundation.framework/Foundation','/usr/lib/libSystem.B.dylib']!{if _:=runtime_symbol(lib,'_CGFontCopyTableForTag'){assert false};if _:=runtime_symbol(lib,'_CGFontCreateWithFontName'){assert false}}
 unsafe{raw.free();malformed.free()};assert ios_runtime.live==before
}
fn test_cg_font(){
 $if macos{api:=GFAPI{true,u64(C.dlopen(c'/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreText.framework/CoreText',2))};gf_cases(api);gf_registered(api);println('IOS-CG-FONT-NATIVE: local HarfBuzz SFNT subset,table order/raw tags,exact bytes,TrueType collections,empty tables,names,registered lookup,metrics,provider callbacks and independent copies')}
 for _ in 0..2{objc_start();$if ios_text?{text_start()or{panic(err)}};gf_cases(GFAPI{});gf_private();$if ios_text?{gf_registered(GFAPI{})};objc_stop();assert ios_runtime.live==0&&ios_runtime.objects.len==0}
 println('IOS-CG-FONT: owned TrueType SFNT descriptions,table order and raw tags,independent table copies,provider and CF ownership,registered-name text backend,concurrent readers,two drained runtimes;CFF/WOFF and glyph rasterization remain outside this API profile')
}
