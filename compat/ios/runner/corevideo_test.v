// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type CKName = fn (&char) u64
type CKMessage = fn (u64, u64, u64, u64, u64) u64
type CKRetain = fn (u64) u64
type CKRelease = fn (u64)
type CKPool = fn () u64
type CKBytes = fn (u64, &char, i64, u32) bool
struct CKApi { native bool foundation u64 objc u64 core u64 }
struct CKCells { values [17]u64 }
__global corevideo_keys_teardown_calls = 0
__global corevideo_unused_calls = 0
__global corevideo_unused_note = u64(0)
__global corevideo_unused_api = CKApi{}
fn ck_names() [17]string { return ['_kCVImageBufferColorPrimariesKey','_kCVImageBufferGammaLevelKey','_kCVImageBufferTransferFunctionKey','_kCVImageBufferTransferFunction_ITU_R_709_2','_kCVImageBufferTransferFunction_SMPTE_240M_1995','_kCVImageBufferTransferFunction_UseGamma','_kCVImageBufferYCbCrMatrixKey','_kCVPixelBufferBytesPerRowAlignmentKey','_kCVPixelBufferMetalCompatibilityKey','_kCVPixelBufferOpenGLESCompatibilityKey','_kCVImageBufferColorPrimaries_ITU_R_709_2','_kCVImageBufferColorPrimaries_SMPTE_C','_kCVImageBufferColorPrimaries_EBU_3213','_kCVImageBufferYCbCrMatrix_ITU_R_709_2','_kCVImageBufferYCbCrMatrix_SMPTE_240M_1995','_kCVImageBufferYCbCrMatrix_ITU_R_601_4','_kCVPixelBufferPixelFormatTypeKey',]! }
fn ck_texts() [17]string { return ['CVImageBufferColorPrimaries','CVImageBufferGammaLevel','CVImageBufferTransferFunction','ITU_R_709_2','SMPTE_240M_1995','UseGamma','CVImageBufferYCbCrMatrix','BytesPerRowAlignment','MetalCompatibility','OpenGLESCompatibility','ITU_R_709_2','SMPTE_C','EBU_3213','ITU_R_709_2','SMPTE_240M_1995','ITU_R_601_4','PixelFormatType',]! }
fn ck_api(native bool) CKApi {
	$if macos { if native {
		return CKApi{true, u64(C.dlopen(c'/System/Library/Frameworks/CoreVideo.framework/CoreVideo', 2)), u64(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2))}
	} }
	return CKApi{}
}
fn ck_cell(api CKApi, name string) u64 {
	if api.native { return u64(C.dlsym(voidptr(api.foundation), unsafe { &char(name.str + 1) })) }
	return runtime_symbol('/System/Library/Frameworks/CoreVideo.framework/CoreVideo', name) or { panic(err) }
}
fn ck_class(api CKApi, name &char) u64 {
	if api.native { return unsafe { CKName(C.dlsym(voidptr(api.objc), c'objc_getClass'))(name) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn ck_msg(api CKApi, object u64, name &char, a u64, b u64, c u64) u64 {
	if api.native {
		selector := unsafe { CKName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) }
		return unsafe { CKMessage(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, selector, a, b, c) }
	}
	return unsafe { CKMessage(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c) }
}
fn ck_retain(api CKApi, value u64) u64 {
	if api.native { return unsafe { CKRetain(C.dlsym(voidptr(api.objc), c'objc_retain'))(value) } }
	return objc_retain(value)
}
fn ck_release(api CKApi, value u64) {
	if api.native { unsafe { CKRelease(C.dlsym(voidptr(api.objc), c'objc_release'))(value) }; return }
	objc_release(value)
}
fn ck_pool(api CKApi) u64 {
	if api.native { return unsafe { CKPool(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPush'))() } }
	return objc_pool_push()
}
fn ck_pop(api CKApi, pool u64) {
	if api.native { unsafe { CKRelease(C.dlsym(voidptr(api.objc), c'objc_autoreleasePoolPop'))(pool) }; return }
	objc_pool_pop(pool)
}
fn ck_text(api CKApi, value u64, expected string) {
	assert value != 0
	if !api.native { assert string_text(value) == expected; return }
	mut buffer := [1024]u8{}
	assert unsafe { CKBytes(C.dlsym(voidptr(api.core), c'CFStringGetCString'))(value, &char(&buffer[0]), 1024, 0x08000100) }
	assert buffer[expected.len] == 0 && C.memcmp(unsafe { &buffer[0] }, expected.str, usize(expected.len)) == 0
}

type CKMessage4 = fn (u64, u64, u64, u64, u64, u64) u64
type CKAllocateClass = fn (u64, &char, usize) u64
type CKAddMethod = fn (u64, u64, u64, &char) bool
fn ck_selector(api CKApi, name &char) u64 {
 if api.native { return unsafe { CKName(C.dlsym(voidptr(api.objc), c'sel_registerName'))(name) } }
 return u64(name)
}
fn ck_msg4(api CKApi, object u64, name &char, a u64, b u64, c u64, d u64) u64 {
 if api.native { return unsafe { CKMessage4(C.dlsym(voidptr(api.objc), c'objc_msgSend'))(object, ck_selector(api, name), a, b, c, d) } }
 return unsafe { CKMessage4(voidptr(C.ios_objc_builtin))(object, u64(name), a, b, c, d) }
}
fn ck_reader(api CKApi, offset int) CKCells {
 mut cells := [17]u64{}; names := ck_names(); texts := ck_texts()
 for turn in 0 .. 16 {
  pool := ck_pool(api)
  for step in 0 .. 17 {
   i := (offset + step) % 17; cell := ck_cell(api, names[i]); assert cell != 0 && cell % 8 == 0
   if turn == 0 { cells[i] = cell } else { assert cells[i] == cell }
   value := read64(cell); ck_text(api, value, texts[i]); assert ck_retain(api, value) == value; ck_release(api, value)
   assert ck_msg(api, ck_retain(api, value), c'autorelease', 0, 0, 0) == value
  }
  ck_pop(api, pool)
 }
 return CKCells{cells}
}
fn ck_shared(api CKApi) {
 mut workers := []thread CKCells{}
 for offset in 0 .. 8 { workers << spawn ck_reader(api, offset) }
 mut cells := [17]u64{}
 for i, worker in workers {got := worker.wait().values; if i == 0 {cells = got} else {assert cells == got}}
 unsafe {workers.free()}
 mut values := [17]u64{}; mut unique := [14]u64{}; mut next := 0
 for i, cell in cells {
  values[i] = read64(cell)
  for j in 0 .. i {assert cell != cells[j]; assert (values[i] == values[j]) == (ck_texts()[i] == ck_texts()[j])}
  if i !in [10,13,14]! {unique[next] = values[i]; next++}
 }
 assert next == 14
 pool := ck_pool(api)
 array := ck_msg(api, ck_class(api,c'NSArray'),c'arrayWithObjects:count:',u64(unsafe{&values[0]}),17,0)
 dictionary := ck_msg(api,ck_class(api,c'NSDictionary'),c'dictionaryWithObjects:forKeys:count:',u64(unsafe{&unique[0]}),u64(unsafe{&unique[0]}),14)
 ck_retain(api,array);ck_retain(api,dictionary);ck_pop(api,pool)
 check := ck_pool(api); assert ck_msg(api,array,c'count',0,0,0)==17 && ck_msg(api,dictionary,c'count',0,0,0)==14
 for i,text in ck_texts(){equal:=ck_msg(api,ck_class(api,c'NSString'),c'stringWithUTF8String:',u64(text.str),0,0);ck_text(api,ck_msg(api,array,c'objectAtIndex:',u64(i),0,0),text);ck_text(api,ck_msg(api,dictionary,c'objectForKey:',equal,0,0),text)}
 ck_release(api,array);ck_release(api,dictionary);ck_pop(api,check)
 if !api.native {assert ios_runtime.live==0&&ios_runtime.objects.len==0}
}
type CPCreate=fn (u64,u64,u64,u32,u64,u64,u64,u64,u64,&u64) i32
type CPPlanar=fn (u64,u64,u64,u32,u64,u64,u64,&u64,&u64,&u64,&u64,u64,u64,u64,&u64) i32
type CPQuery=fn (u64) u64
type CPFormat=fn (u64) u32
type CPBool=fn (u64) u8
type CPPlane=fn (u64,u64) u64
type CPFlag=fn (u64,u64) i32
type CPType=fn () u64
type CPDrop=fn (u64)
struct CPApi {native bool lib u64 core u64}
struct CPContext {mut: allocation u64 base u64 size u64 planes u64 addresses [2]u64 calls int}
fn cp_symbol(api CPApi,name string) u64 {
 value:=if api.native{u64(C.dlsym(voidptr(api.lib),unsafe{&char(name.str+1)}))}else{runtime_symbol('/System/Library/Frameworks/CoreVideo.framework/CoreVideo',name)or{panic(err)}}
 assert value!=0,name;return value
}
fn cp_drop(api CPApi,object u64){unsafe{CPDrop(voidptr(cp_symbol(api,'_CVPixelBufferRelease')))(object)}}
fn cp_query(api CPApi,name string,object u64) u64{return unsafe{CPQuery(voidptr(cp_symbol(api,name)))(object)}}
fn cp_plane(api CPApi,name string,object u64,index u64) u64{return unsafe{CPPlane(voidptr(cp_symbol(api,name)))(object,index)}}
fn cp_flag(api CPApi,name string,object u64,flags u64) i32{return unsafe{CPFlag(voidptr(cp_symbol(api,name)))(object,flags)}}
fn cp_release_bytes(context u64,base u64){mut state:=unsafe{&CPContext(context)};assert state.calls==0&&base==state.base;state.calls++;C.free(voidptr(state.allocation))}
fn cp_release_planes(context u64,base u64,size u64,count u64,addresses &u64){mut state:=unsafe{&CPContext(context)};assert state.calls==0&&base==state.base&&size==state.size&&count==state.planes;for i in 0..2{assert unsafe{addresses[i]}==state.addresses[i]};state.calls++;C.free(voidptr(state.allocation))}
fn cp_reader(api CPApi,object u64,width u64) {
 for _ in 0..64 {
  assert cp_query(api,'_CVPixelBufferRetain',object)==object
  assert cp_query(api,'_CVPixelBufferGetWidth',object)==width
  assert cp_flag(api,'_CVPixelBufferLockBaseAddress',object,1)==0
  assert cp_flag(api,'_CVPixelBufferUnlockBaseAddress',object,1)==0
  cp_drop(api,object)
 }
}
fn cp_cases(api CPApi) {
 cp_drop(api,0);assert cp_query(api,'_CVPixelBufferRetain',0)==0
 for mode in 0..6 {
  mut state:=unsafe{&CPContext(C.calloc(1,sizeof(CPContext)))};assert state!=unsafe{nil}
  allocation:=u64(C.calloc(1,512));assert allocation!=0;state.allocation=allocation
  packed:=mode<2;contiguous:=mode>=4;width:=if packed{u64(7)}else{u64(8)};height:=if packed{u64(3)}else{u64(4)}
  stride:=if mode==1{u64(1)}else{u64(32)};format:=if packed{u32(0x42475241)}else if mode%2==0{u32(0x34323076)}else{u32(0x34323066)}
  state.base=if packed||contiguous{allocation}else{u64(0)};state.size=if contiguous{u64(96)}else{u64(0)};state.planes=if packed{u64(0)}else{u64(2)}
  state.addresses=[allocation+32,allocation+160]!
  mut addresses:=state.addresses;mut widths:=[u64(8),4]!;mut heights:=[u64(4),2]!;mut strides:=[u64(16),16]!
  mut output:=[u64(0xcafe),0,0xbeef]!
  status:=if packed{unsafe{CPCreate(voidptr(cp_symbol(api,'_CVPixelBufferCreateWithBytes')))(0,width,height,format,allocation,stride,u64(voidptr(cp_release_bytes)),u64(state),0,&output[1])}}else{unsafe{CPPlanar(voidptr(cp_symbol(api,'_CVPixelBufferCreateWithPlanarBytes')))(0,width,height,format,state.base,state.size,2,&addresses[0],&widths[0],&heights[0],&strides[0],u64(voidptr(cp_release_planes)),u64(state),0,&output[1])}}
  assert status==0&&output[0]==0xcafe&&output[2]==0xbeef&&output[1]!=0
  object:=output[1];addresses=[u64(0),0]!;widths=[u64(0),0]!;heights=[u64(0),0]!;strides=[u64(0),0]!
  for flags in [u64(0),1,256]!{assert cp_flag(api,'_CVPixelBufferLockBaseAddress',object,flags)==0;assert cp_flag(api,'_CVPixelBufferUnlockBaseAddress',object,flags)==0}
  assert cp_flag(api,'_CVPixelBufferLockBaseAddress',object,0)==0
  assert cp_query(api,'_CVPixelBufferGetWidth',object)==width&&cp_query(api,'_CVPixelBufferGetHeight',object)==height
  assert unsafe{CPFormat(voidptr(cp_symbol(api,'_CVPixelBufferGetPixelFormatType')))(object)}==format
  assert unsafe{CPBool(voidptr(cp_symbol(api,'_CVPixelBufferIsPlanar')))(object)}==u8(!packed)
  assert cp_query(api,'_CVPixelBufferGetPlaneCount',object)==state.planes
  assert cp_query(api,'_CVPixelBufferGetBaseAddress',object)==state.base
  assert cp_query(api,'_CVPixelBufferGetDataSize',object)==if packed{stride*height}else{state.size}
  assert cp_query(api,'_CVPixelBufferGetBytesPerRow',object)==if packed{stride}else{state.size/height}
  for index in [u64(0),1,2,~u64(0)]!{
   expected_width:=if packed{if index==0{width}else{u64(0)}}else{if index==0{u64(8)}else if index==1{u64(4)}else{u64(0)}}
   expected_height:=if packed{if index==0{height}else{u64(0)}}else{if index==0{u64(4)}else if index==1{u64(2)}else{u64(0)}}
   expected_stride:=if packed{if index==0{stride}else{u64(0)}}else{if index<2{u64(16)}else{u64(0)}}
   expected_base:=if packed{if index==0{allocation}else{u64(0)}}else{if index<2{state.addresses[int(index)]}else{u64(0)}}
   assert cp_plane(api,'_CVPixelBufferGetWidthOfPlane',object,index)==expected_width
   assert cp_plane(api,'_CVPixelBufferGetHeightOfPlane',object,index)==expected_height
   assert cp_plane(api,'_CVPixelBufferGetBytesPerRowOfPlane',object,index)==expected_stride
   assert cp_plane(api,'_CVPixelBufferGetBaseAddressOfPlane',object,index)==expected_base
  }
  pointer:=if packed{allocation}else{state.addresses[1]};unsafe{*(&u8(pointer))=0x5a};assert unsafe{*(&u8(pointer))}==0x5a
  assert cp_flag(api,'_CVPixelBufferUnlockBaseAddress',object,0)==0
  type_id:=unsafe{CPType(voidptr(cp_symbol(api,'_CVPixelBufferGetTypeID')))()}
  if api.native{assert unsafe{CPQuery(C.dlsym(voidptr(api.core),c'CFGetTypeID'))(object)}==type_id;assert unsafe{CPQuery(C.dlsym(voidptr(api.core),c'CFRetain'))(object)}==object}else{assert cf_type_id(object)==type_id;assert objc_retain(object)==object}
  mut workers:=[]thread{};for _ in 0..8{workers<<spawn cp_reader(api,object,width)};workers.wait();unsafe{workers.free()}
  cp_drop(api,object);assert state.calls==0
  if api.native{unsafe{CPDrop(C.dlsym(voidptr(api.core),c'CFRelease'))(object)}}else{objc_release(object)}
  assert state.calls==1;C.free(state)
 }
 mut pixels:=[128]u8{};base:=u64(unsafe{&pixels[0]})
 mut borrowed:=u64(0);assert unsafe{CPCreate(voidptr(cp_symbol(api,'_CVPixelBufferCreateWithBytes')))(0,7,3,0x42475241,base,32,0,0,0,&borrowed)}==0;cp_drop(api,borrowed);pixels[0]=123;assert pixels[0]==123
 for dimensions in [[u64(0),3]!,[u64(7),0]!]!{mut out:=u64(0xfeed);assert unsafe{CPCreate(voidptr(cp_symbol(api,'_CVPixelBufferCreateWithBytes')))(0,dimensions[0],dimensions[1],0x42475241,base,32,0,0,0,&out)}==-6661;assert out==0xfeed}
}
fn ck_teardown(object u64,selector &char){for i,name in ck_names(){cell:=corevideo_constant_symbol(name)or{panic('CoreVideo globals retired before pool callbacks')};assert string_text(read64(cell))==ck_texts()[i]};corevideo_keys_teardown_calls++}
fn cp_child(mode string){
 objc_start()
 guard:=C.mmap(unsafe{nil},usize(C.getpagesize()),C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert guard!=voidptr(-1)
 if mode=='foreign'{cv_pixel_width(u64(guard));exit(0)}
 mut object:=u64(0);assert cv_pixel_create_bytes(0,7,3,0x42475241,u64(guard),32,0,0,0,&object)==0;cv_pixel_release(object);cv_pixel_width(object);exit(0)
}
fn cp_rejections(){
 for mode in ['foreign','stale']!{mut p:=os.new_process(os.executable());p.set_redirect_stdio_merged();mut env:=os.environ();env['VINIX_IOS_CV_CHILD']=mode;p.set_environment(env);p.run();s:=p.stdout_slurp();p.wait();code:=p.code;p.close();assert code!=0&&s.contains('expected a live CPU CVPixelBuffer')&&!s.contains('ERROR: AddressSanitizer')&&!s.contains('runtime error:');unsafe{s.free()}}
}
fn test_corevideo(){
 mode:=os.getenv('VINIX_IOS_CV_CHILD');if mode!=''{cp_child(mode);return}
 $if macos {keys:=ck_api(true);ck_shared(keys);cp_cases(CPApi{true,keys.foundation,keys.core});println('IOS-COREVIDEO-NATIVE: seventeen CFString cells and aliases,retained collections,BGRA and 420v/420f packed/disjoint/contiguous storage,plane-zero quirks,short stride,callbacks,CF ownership and eight concurrent readers')}
 cp_rejections()
 if _:=corevideo_constant_symbol('_kCVImageBufferGammaLevelKey'){assert false}
 for _ in 0..2{
  objc_start();ck_shared(CKApi{});cp_cases(CPApi{})
  assert ios_runtime.live==0&&ios_runtime.objects.len==0
  for name in ck_names(){for lib in ['/System/Library/Frameworks/Foundation.framework/Foundation','/usr/lib/libSystem.B.dylib']!{if _:=runtime_symbol(lib,name){assert false}}}
  for name in ['_CVMetalTextureCacheCreate','_CVMetalTextureCacheCreateTextureFromImage','_CVMetalTextureGetTexture']!{if _:=runtime_symbol('/System/Library/Frameworks/CoreVideo.framework/CoreVideo',name){assert false}}
  probe:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixCoreVideoTeardownProbe',0);assert probe!=0;assert objc_add_method(probe,u64(c'dealloc'),u64(unsafe{voidptr(ck_teardown)}),c'v16@0:8');objc_register_class(probe);objc_autorelease(objc_new(probe))
  before:=corevideo_keys_teardown_calls;objc_stop();assert corevideo_keys_teardown_calls==before+1&&ios_runtime.corevideo_constants_arena==0&&ios_runtime.live==0&&ios_runtime.objects.len==0
  if _:=corevideo_constant_symbol('_kCVImageBufferGammaLevelKey'){assert false}
 }
 println('IOS-COREVIDEO: CPU pixel buffer creation/queries/locking,exact final-release callbacks and copied plane arrays,CF retain/release,stable sealed metadata aliases,concurrent readers,two drained runtimes;Metal textures remain unsupported')
}
