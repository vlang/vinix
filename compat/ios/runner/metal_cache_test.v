// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
#include <dlfcn.h>
#include <sys/wait.h>
#define ios_metal_waitpid waitpid
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.fork() i32
fn C.ios_metal_waitpid(i32,voidptr,i32) i32
fn C._exit(i32)
$if macos {
 #include <mach/mach.h>
 #include <mach/mach_vm.h>
 fn C.mach_task_self()u32
 fn C.mach_vm_region(u32,voidptr,voidptr,i32,voidptr,voidptr,voidptr)i32
 fn C.mach_port_deallocate(u32,u32)i32
}
type MTName=fn(&char)u64
type MTQuery=fn(u64)u64
type MTPlane=fn(u64,u64)u64
type MTDrop=fn(u64)
type MTDevice=fn()u64
type MTCache=fn(u64,u64,u64,u64,&u64)i32
type MTCreate=fn(u64,u64,u64,u32,u64,&u64)i32
type MTView=fn(u64,u64,u64,u64,u64,u64,u64,u64,&u64)i32
type MTNumber=fn(u64,i64,u64)u64
type MTDict=fn(u64,u64,u64,i64,u64,u64)u64
type MTFlag=fn(u64,u64)i32
type MTFlip=fn(u64)u8
type MTCoords=fn(u64,&f32,&f32,&f32,&f32)
type MTFlush=fn(u64,u64)
type MTMessage=fn(u64,u64)u64
type MTGet=fn(u64,u64,u64,u64,MTRegion,u64)
type MTPut=fn(u64,u64,MTRegion,u64,u64,u64)
type MTText=fn(u64,&char,i64,u32)bool
struct MTRegion { x u64 y u64 z u64 width u64 height u64 depth u64 }
struct MTApi { native bool cv u64 cf u64 objc u64 metal u64 surface u64 }
__global mt_fixture_texture_class=u64(0)
__global mt_fixture_device_class=u64(0)
__global mt_fixture_reject=false
__global mt_fixture_device_deaths=0
__global mt_fixture_texture_deaths=0
fn mt_symbol(api MTApi,name string,group string)u64 {
 lib:=match group{'cf'{'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'}'surface'{'/System/Library/Frameworks/IOSurface.framework/IOSurface'}else{'/System/Library/Frameworks/CoreVideo.framework/CoreVideo'}}
 if api.native{handle:=match group{'cf'{api.cf}'surface'{api.surface}else{api.cv}};p:=u64(C.dlsym(unsafe{voidptr(handle)},unsafe{&char(name.str+1)}));assert p!=0,name;return p}
 return runtime_symbol(lib,name)or{panic(err)}
}
fn mt_query(api MTApi,name string,object u64,group string)u64{return unsafe{MTQuery(voidptr(mt_symbol(api,name,group)))(object)}}
fn mt_plane(api MTApi,name string,object u64,index u64,group string)u64{return unsafe{MTPlane(voidptr(mt_symbol(api,name,group)))(object,index)}}
fn mt_drop(api MTApi,object u64){unsafe{MTDrop(voidptr(mt_symbol(api,'_CFRelease','cf')))(object)}}
fn mt_retain(api MTApi,object u64)u64{return mt_query(api,'_CFRetain',object,'cf')}
fn mt_cell(api MTApi,name string)u64{return read64(mt_symbol(api,name,'cv'))}
fn mt_number(api MTApi,value i64)u64{return unsafe{MTNumber(voidptr(mt_symbol(api,'_CFNumberCreate','cf')))(0,4,u64(&value))}}
fn mt_dict(api MTApi,keys []u64,values []u64)u64{return unsafe{MTDict(voidptr(mt_symbol(api,'_CFDictionaryCreate','cf')))(0,u64(keys.data),u64(values.data),i64(keys.len),mt_symbol(api,'_kCFTypeDictionaryKeyCallBacks','cf'),mt_symbol(api,'_kCFTypeDictionaryValueCallBacks','cf'))}}
fn mt_selector(api MTApi,name &char)u64{return if api.native{unsafe{MTName(C.dlsym(voidptr(api.objc),c'sel_registerName'))(name)}}else{u64(name)}}
fn mt_send_address(api MTApi)u64{return if api.native{u64(C.dlsym(unsafe{voidptr(api.objc)},c'objc_msgSend'))}else{u64(unsafe{voidptr(C.ios_objc_msgsend)})}}
fn mt_property(api MTApi,object u64,name &char)u64{return unsafe{MTMessage(voidptr(mt_send_address(api)))(object,mt_selector(api,name))}}
fn mt_lock(api MTApi,object u64,unlock bool){name:=if unlock{'_CVPixelBufferUnlockBaseAddress'}else{'_CVPixelBufferLockBaseAddress'};assert unsafe{MTFlag(voidptr(mt_symbol(api,name,'cv')))(object,0)}==0}
fn mt_attributes(api MTApi,mode int)u64 {
 empty:=mt_dict(api,[],[]);number:=mt_number(api,1)
 keys:=if mode==0{[mt_cell(api,'_kCVPixelBufferMetalCompatibilityKey')]}else if mode==1{[mt_cell(api,'_kCVPixelBufferIOSurfacePropertiesKey')]}else{[mt_cell(api,'_kCVPixelBufferIOSurfacePropertiesKey'),mt_cell(api,'_kCVPixelBufferMetalCompatibilityKey')]}
 values:=if mode==0{[number]}else if mode==1{[empty]}else{[empty,number]}
 result:=mt_dict(api,keys,values);mt_drop(api,empty);mt_drop(api,number);unsafe{keys.free();values.free()};return result
}
fn mt_fixture_getter(object u64,selector &char)u64{h:=obj_header(object);return match ctext(u64(selector)){'width'{u64(h.number)}'height'{u64(h.section)}'pixelFormat'{u64(h.tag)}'storageMode'{u64(0)}'textureType'{u64(2)}'usage'{u64(h.align)}else{panic('fixture property')}}}
fn mt_fixture_device_dealloc(object u64,selector &char){mt_fixture_device_deaths++}
fn mt_fixture_texture_dealloc(object u64,selector &char){mt_fixture_texture_deaths++}
fn mt_fixture_factory(device u64,selector &char,descriptor u64,surface u64,index u64)u64 {
 if mt_fixture_reject{return 0}
 api:=MTApi{}
 assert objc_is_kind(descriptor,ios_runtime.names['MTLTextureDescriptor'])
 assert mt_property(api,descriptor,c'textureType')==2&&mt_property(api,descriptor,c'depth')==1&&mt_property(api,descriptor,c'mipmapLevelCount')==1&&mt_property(api,descriptor,c'arrayLength')==1&&mt_property(api,descriptor,c'sampleCount')==1
 assert mt_property(api,descriptor,c'storageMode')==0&&mt_property(api,descriptor,c'resourceOptions')==0&&mt_property(api,descriptor,c'cpuCacheMode')==0
 assert mt_property(api,descriptor,c'usage') in [u64(1),23]!
 texture:=objc_allocate(mt_fixture_texture_class);mut h:=obj_header(texture)
 h.number=i64(mt_property(api,descriptor,c'width'));h.section=i64(mt_property(api,descriptor,c'height'));h.tag=i64(mt_property(api,descriptor,c'pixelFormat'));h.align=int(mt_property(api,descriptor,c'usage'))
 h.mutation=cv_surface_plane_row(surface,index);h.external_data=cv_surface_plane_base(surface,index)
 h.fields[0]=objc_retain(surface);h.fields[1]=objc_retain(device)
 return texture
}
fn mt_fixture_transfer(object u64,region MTRegion,bytes u64,row u64,write bool){
 h:=obj_header(object);pixel:=if h.tag in [i64(80),81]!{u64(4)}else if h.tag==10{u64(1)}else{u64(2)}
 assert region.z==0&&region.depth==1&&region.width>0&&region.height>0&&region.x+region.width<=u64(h.number)&&region.y+region.height<=u64(h.section)&&row>=region.width*pixel
 for y:=u64(0);y<region.height;y++{a:=h.external_data+(region.y+y)*h.mutation+region.x*pixel;b:=bytes+y*row;if write{C.memcpy(unsafe{voidptr(a)},unsafe{voidptr(b)},usize(region.width*pixel))}else{C.memcpy(unsafe{voidptr(b)},unsafe{voidptr(a)},usize(region.width*pixel))}}
}
fn mt_fixture_get(object u64,selector &char,bytes u64,row u64,region MTRegion,level u64){assert level==0;mt_fixture_transfer(object,region,bytes,row,false)}
fn mt_fixture_put(object u64,selector &char,region MTRegion,level u64,bytes u64,row u64){assert level==0;mt_fixture_transfer(object,region,bytes,row,true)}
fn mt_fixture_start(){
 mt_fixture_device_class=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixTestSurfaceDevice',0);mt_fixture_texture_class=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixTestSharedTexture',0)
 assert mt_fixture_device_class!=0&&mt_fixture_texture_class!=0
 assert objc_add_method(mt_fixture_device_class,u64(c'newTextureWithDescriptor:iosurface:plane:'),u64(unsafe{voidptr(mt_fixture_factory)}),c'@40@0:8@16^v24Q32')
 assert objc_add_method(mt_fixture_device_class,u64(c'dealloc'),u64(unsafe{voidptr(mt_fixture_device_dealloc)}),c'v16@0:8')
 assert objc_add_method(mt_fixture_texture_class,u64(c'dealloc'),u64(unsafe{voidptr(mt_fixture_texture_dealloc)}),c'v16@0:8')
 for name in [c'width',c'height',c'pixelFormat',c'storageMode',c'textureType',c'usage']!{assert objc_add_method(mt_fixture_texture_class,u64(name),u64(unsafe{voidptr(mt_fixture_getter)}),c'Q16@0:8')}
 assert objc_add_method(mt_fixture_texture_class,u64(c'getBytes:bytesPerRow:fromRegion:mipmapLevel:'),u64(unsafe{voidptr(mt_fixture_get)}),c'v88@0:8^v16Q24{MTLRegion={MTLOrigin=QQQ}{MTLSize=QQQ}}32Q80')
 assert objc_add_method(mt_fixture_texture_class,u64(c'replaceRegion:mipmapLevel:withBytes:bytesPerRow:'),u64(unsafe{voidptr(mt_fixture_put)}),c'v88@0:8{MTLRegion={MTLOrigin=QQQ}{MTLSize=QQQ}}16Q64r^v72Q80')
 objc_register_class(mt_fixture_device_class);objc_register_class(mt_fixture_texture_class)
}
fn mt_device(api MTApi)u64{if api.native{return unsafe{MTDevice(C.dlsym(voidptr(api.metal),c'MTLCreateSystemDefaultDevice'))()}};return objc_allocate(mt_fixture_device_class)}
fn mt_reader(api MTApi,view u64,texture u64){for _ in 0..64{assert mt_retain(api,view)==view;assert mt_query(api,'_CVMetalTextureGetTexture',view,'cv')==texture;assert mt_property(api,texture,c'width')>0;mt_drop(api,view)}}
fn mt_vm_mapped(pointer u64)bool{
 $if macos{
  mut address:=pointer;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(16);mut object:=u32(0)
  result:=C.mach_vm_region(C.mach_task_self(),unsafe{voidptr(&address)},unsafe{voidptr(&size)},C.VM_REGION_BASIC_INFO_64,unsafe{voidptr(&info[0])},unsafe{voidptr(&count)},unsafe{voidptr(&object)})
  if object!=0{assert C.mach_port_deallocate(C.mach_task_self(),object)==0}
  return result==0&&address==pointer&&size>0
 }
 return false
}
fn mt_cases(api MTApi){
 cache_create:=unsafe{MTCache(voidptr(mt_symbol(api,'_CVMetalTextureCacheCreate','cv')))};create:=unsafe{MTCreate(voidptr(mt_symbol(api,'_CVPixelBufferCreate','cv')))};make_view:=unsafe{MTView(voidptr(mt_symbol(api,'_CVMetalTextureCacheCreateTextureFromImage','cv')))}
 mut bad:=u64(0xfeed);assert cache_create(0,0,0,0,&bad)==-6661&&bad==0xfeed;assert make_view(0,0,0,0,81,8,4,0,&bad)==-6661&&bad==0xfeed;assert mt_query(api,'_CVMetalTextureGetTexture',0,'cv')==0
 for mode in 0..3{for format in [u32(0x42475241),0x34323076,0x34323066]!{
  device:=mt_device(api);assert device!=0;mut cache:=u64(0);assert cache_create(0,0,device,0,&cache)==0&&cache!=0;mt_drop(api,device)
  attrs:=mt_attributes(api,mode);mut buffer:=u64(0);assert create(0,7,3,format,attrs,&buffer)==0;mt_drop(api,attrs)
  surface:=mt_query(api,'_CVPixelBufferGetIOSurface',buffer,'cv');assert surface!=0&&mt_retain(api,surface)==surface
  assert mt_query(api,'_IOSurfaceGetWidth',surface,'surface')==7&&mt_query(api,'_IOSurfaceGetHeight',surface,'surface')==3
  assert mt_query(api,'_IOSurfaceGetPlaneCount',surface,'surface')==if format==0x42475241{u64(0)}else{u64(2)}
  assert mt_query(api,'_IOSurfaceGetBytesPerRow',surface,'surface')==mt_query(api,'_CVPixelBufferGetBytesPerRow',buffer,'cv')
  mut views:=[2]u64{};mut textures:=[2]u64{};count:=if format==0x42475241{1}else{2}
  for plane in 0..count{
   w:=if plane==0{u64(7)}else{u64(4)};h:=if plane==0{u64(3)}else{u64(2)};pixel:=if format==0x42475241{u64(4)}else if plane==0{u64(1)}else{u64(2)};metal_format:=if format==0x42475241{u64(81)}else if plane==0{u64(10)}else{u64(30)}
   mt_lock(api,buffer,false);base:=mt_plane(api,'_CVPixelBufferGetBaseAddressOfPlane',buffer,u64(plane),'cv');stride:=mt_plane(api,'_CVPixelBufferGetBytesPerRowOfPlane',buffer,u64(plane),'cv')
   assert base==mt_plane(api,'_IOSurfaceGetBaseAddressOfPlane',surface,u64(plane),'surface')&&stride==mt_plane(api,'_IOSurfaceGetBytesPerRowOfPlane',surface,u64(plane),'surface')
   assert mt_plane(api,'_IOSurfaceGetWidthOfPlane',surface,u64(plane),'surface')==w&&mt_plane(api,'_IOSurfaceGetHeightOfPlane',surface,u64(plane),'surface')==h&&mt_plane(api,'_IOSurfaceGetBytesPerElementOfPlane',surface,u64(plane),'surface')==pixel
   for y:=u64(0);y<h;y++{for x:=u64(0);x<w*pixel;x++{unsafe{*(&u8(base+y*stride+x))=u8((x+y*17)%251)}}}
   mt_lock(api,buffer,true)
   result:=make_view(0,cache,buffer,0,metal_format,w,h,u64(plane),unsafe{&views[plane]});assert result==0&&views[plane]!=0,'mode='+mode.str()+' format='+format.hex()+' plane='+plane.str()+' status='+result.str()
   texture:=mt_query(api,'_CVMetalTextureGetTexture',views[plane],'cv');textures[plane]=mt_retain(api,texture)
   assert mt_property(api,texture,c'width')==w&&mt_property(api,texture,c'height')==h&&mt_property(api,texture,c'pixelFormat')==metal_format&&mt_property(api,texture,c'textureType')==2
   mut bytes:=[256]u8{};unsafe{MTGet(voidptr(mt_send_address(api)))(texture,mt_selector(api,c'getBytes:bytesPerRow:fromRegion:mipmapLevel:'),u64(&bytes[0]),32,MTRegion{0,0,0,w,h,1},0)}
   for y:=u64(0);y<h;y++{for x:=u64(0);x<w*pixel;x++{assert bytes[int(y*32+x)]==u8((x+y*17)%251)}}
   for i in 0..bytes.len{bytes[i]=0x6b}
   unsafe{MTPut(voidptr(mt_send_address(api)))(texture,mt_selector(api,c'replaceRegion:mipmapLevel:withBytes:bytesPerRow:'),MTRegion{1,1,0,w-1,h-1,1},0,u64(&bytes[0]),32)}
   mt_lock(api,buffer,false);assert unsafe{*(&u8(base+stride+pixel))}==0x6b;mt_lock(api,buffer,true)
   mut ll:=[f32(-7),0,0,-7]!;mut lr:=ll;mut ur:=ll;mut ul:=ll
   unsafe{MTCoords(voidptr(mt_symbol(api,'_CVMetalTextureGetCleanTexCoords','cv')))(views[plane],&ll[1],&lr[1],&ur[1],&ul[1])}
   assert ll==[f32(-7),0,1,-7]!&&lr==[f32(-7),1,1,-7]!&&ur==[f32(-7),1,0,-7]!&&ul==[f32(-7),0,0,-7]!
   assert unsafe{MTFlip(voidptr(mt_symbol(api,'_CVMetalTextureIsFlipped','cv')))(views[plane])}==1
   if plane==0&&mode==0{mut readers:=[]thread{};for _ in 0..8{readers<<spawn mt_reader(api,views[plane],texture)};readers.wait();unsafe{readers.free()}}
  }
  mt_drop(api,buffer);unsafe{MTFlush(voidptr(mt_symbol(api,'_CVMetalTextureCacheFlush','cv')))(cache,0)};mt_drop(api,cache)
  for i in 0..count{assert mt_query(api,'_CVMetalTextureGetTexture',views[i],'cv')==textures[i];mt_drop(api,views[i]);assert mt_property(api,textures[i],c'width')>0}
  pointer:=mt_plane(api,'_IOSurfaceGetBaseAddressOfPlane',surface,0,'surface')
  if !api.native{child:=C.fork();assert child>=0;if child==0{unsafe{*(&u8(pointer))=0x5a};C._exit(0)};mut status:=i32(0);assert C.ios_metal_waitpid(child,unsafe{voidptr(&status)},0)==child&&status==0;assert unsafe{*(&u8(pointer))}==0x5a}
  if !api.native{$if macos{assert mt_vm_mapped(pointer & ~(u64(C.getpagesize())-1))}}
  for i in 0..count{mt_drop(api,textures[i])}
  mt_drop(api,surface)
  if !api.native{$if macos{assert !mt_vm_mapped(pointer & ~(u64(C.getpagesize())-1))}}
 }}
 for name in ['_kCVMetalTextureCacheMaximumTextureAgeKey','_kCVMetalTextureUsage','_kCVMetalTextureStorageMode']!{value:=mt_cell(api,name);expected:=match name{'_kCVMetalTextureCacheMaximumTextureAgeKey'{'MaximumMetalTextureAge'}'_kCVMetalTextureUsage'{'MetalTextureUsage'}else{'MetalTextureStorageMode'}};if api.native{mut b:=[128]u8{};assert unsafe{MTText(voidptr(mt_symbol(api,'_CFStringGetCString','cf')))(value,&char(&b[0]),128,0x08000100)};assert unsafe{(&char(&b[0])).vstring()}==expected}else{assert string_text(value)==expected}}
}
fn mt_private_failures(){
 device:=mt_device(MTApi{});mut cache:=u64(0);assert cv_metal_cache_create(0,0,device,0,&cache)==0;objc_release(device)
 mut cpu:=u64(0);assert cv_pixel_create(0,8,4,0x42475241,0,&cpu)==0;mut out:=u64(0xfeed);assert cv_metal_create_view(0,cache,cpu,0,81,8,4,0,&out)==-6660&&out==0;objc_release(cpu)
 attrs:=mt_attributes(MTApi{},0);mut image:=u64(0);assert cv_pixel_create(0,8,4,0x42475241,attrs,&image)==0;objc_release(attrs)
 for args in [[u64(0),4,0]!,[u64(9),4,0]!,[u64(8),5,0]!,[u64(8),4,99]!]!{out=0xfeed;assert cv_metal_create_view(0,cache,image,0,81,args[0],args[1],args[2],&out)==-6661&&out==0xfeed}
 out=0xfeed;assert cv_metal_create_view(0,cache,image,0,10,8,4,0,&out)==-6680&&out==0
 mt_fixture_reject=true;before:=ios_runtime.live;out=0xfeed;assert cv_metal_create_view(0,cache,image,0,81,8,4,0,&out)==-6684&&out==0&&ios_runtime.live==before;mt_fixture_reject=false
 zero:=mt_number(MTApi{},0);one:=mt_number(MTApi{},1)
 age:=mt_dict(MTApi{},[mt_cell(MTApi{},'_kCVMetalTextureCacheMaximumTextureAgeKey')],[zero]);options:=mt_dict(MTApi{},[mt_cell(MTApi{},'_kCVMetalTextureUsage'),mt_cell(MTApi{},'_kCVMetalTextureStorageMode')],[one,zero])
 mut configured:=u64(0);assert cv_metal_cache_create(0,age,obj_header(cache).fields[0],options,&configured)==0
 objc_release(zero);objc_release(one);objc_release(age);objc_release(options)
 out=0;assert cv_metal_create_view(0,configured,image,0,81,8,4,0,&out)==0;assert mt_property(MTApi{},cv_metal_get_texture(out),c'usage')==1
 objc_release(out);objc_release(configured)
 objc_release(image);objc_release(cache)
 create:=runtime_symbol('/System/Library/Frameworks/Metal.framework/Metal','_MTLCreateSystemDefaultDevice')or{panic(err)}
 assert unsafe{MTDevice(voidptr(create))()}==0
 if _:=runtime_symbol('/System/Library/Frameworks/Metal.framework/Metal','_OBJC_CLASS_$_MTLDevice'){assert false}
 for name in ['_OBJC_CLASS_$_MTLTextureDescriptor','_OBJC_METACLASS_$_MTLTextureDescriptor']!{assert (runtime_symbol('/System/Library/Frameworks/Metal.framework/Metal',name)or{panic(err)})!=0;for library in ['/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/UIKit.framework/UIKit','/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics','/usr/lib/libobjc.A.dylib','/usr/lib/libSystem.B.dylib']!{if _:=runtime_symbol(library,name){assert false}}}
}
fn test_metal_cache(){
 $if macos{api:=MTApi{true,u64(C.dlopen(c'/System/Library/Frameworks/CoreVideo.framework/CoreVideo',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2)),u64(C.dlopen(c'/usr/lib/libobjc.A.dylib',2)),u64(C.dlopen(c'/System/Library/Frameworks/Metal.framework/Metal',2)),u64(C.dlopen(c'/System/Library/Frameworks/IOSurface.framework/IOSurface',2))};mt_cases(api);println('IOS-METAL-CACHE-NATIVE: surface allocation from Metal/IOSurface hints,BGRA and YUV plane imports,live texture read/write,orientation,independent CF lifetimes and concurrent readers')}
 for _ in 0..2{objc_start();mt_fixture_start();devices:=mt_fixture_device_deaths;textures:=mt_fixture_texture_deaths;mt_cases(MTApi{});mt_private_failures();assert mt_fixture_device_deaths==devices+10&&mt_fixture_texture_deaths==textures+16;assert ios_runtime.live==0&&ios_runtime.objects.len==0;objc_stop();assert ios_runtime.corevideo_constants_arena==0&&ios_runtime.live==0}
 println('IOS-METAL-CACHE: supplied-device factory delegation,live shared BGRA/YUV textures,independent surface/texture lifetimes,final unmapping,format/size/backend failures,concurrent readers,two drained runtimes;GPU device and renderer remain unavailable')
}
