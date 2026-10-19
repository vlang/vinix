// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
type TMProbe = fn(u64,u64,u64,u64,u64,&u64)
type TMAllocate = fn(u64,u64,u64)u64
type TMDeallocate = fn(u64,u64,u64)
type TMRelease = fn(u64)
type TMRetain = fn(u64)u64
type TMSign = fn(u64,u64)u64
type TMBox = fn(u64)SwiftArrayAllocation
type TMAccess = fn(u64)SwiftAssociatedMetadata
struct TMApi { native bool metadata u64 probe TMProbe allocate TMAllocate deallocate TMDeallocate release TMRelease }
struct TMOwner { api TMApi scene u64 index int mut: calls int }
struct TMScene { api TMApi source u64 destination u64 mut: observations [6]u64 calls int }
fn tm_api(native bool,code u64)TMApi{
	mut entries:=[4]u64{};mut metadata:=u64(0)
	if native{core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);library:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);metadata=u64(C.dlsym(library,c'$s7SwiftUI4TextVN'));for i,name in [c'swift_allocObject',c'swift_deallocClassInstance',c'swift_release',c'swift_allocBox']!{entries[i]=u64(C.dlsym(core,name))}}
	else{metadata=swiftui_text_metadata();entries=[u64(unsafe{voidptr(swift_heap_allocate)}),u64(unsafe{voidptr(swift_heap_deallocate)}),u64(unsafe{voidptr(swift_release)}),u64(0)]!}
	assert metadata!=0;return TMApi{native,metadata,unsafe{TMProbe(voidptr(code))},unsafe{TMAllocate(voidptr(entries[0]))},unsafe{TMDeallocate(voidptr(entries[1]))},unsafe{TMRelease(voidptr(entries[2]))}}
}
fn (a TMApi) raw(slot u64,x u64,y u64,z u64,d u64)u64{mut r:=[u64(0xcafe),0,0,0,0,0xbeef]!;w:=read64(a.metadata-8)&0x0000ffffffffffff;entry:=read64(w+slot*8)&0x0000ffffffffffff;a.probe(entry,x,y,z,d,unsafe{&r[1]});assert r[0]==0xcafe&&r[3]==0x5020&&r[4]==0x5021&&r[5]==0xbeef;return r[1]}
fn (a TMApi) call(slot u64,x u64,y u64,z u64)u64{return a.raw(slot,x,y,z,0)}
fn (a TMApi) value(slot u64,d u64,s u64)u64{return a.call(slot,d,s,a.metadata)}
fn tm_owner_destroy(owner u64){
	mut state:=unsafe{&TMOwner(read64(owner+16))};assert state.calls==0;state.calls++
	if state.scene!=0{mut scene:=unsafe{&TMScene(state.scene)};assert scene.calls==state.index;scene.calls++
		mut bits:=u64(0);for i in 0..4{if (i==2&&unsafe{*(&u8(scene.source+16))}==unsafe{*(&u8(scene.destination+16))})||(i!=2&&read64(scene.source+u64(i*8))==read64(scene.destination+u64(i*8))){bits|=u64(1)<<u64(i)}}
		tag:=unsafe{*(&u8(scene.source+16))};payload:=read64(scene.source+if tag==0{u64(8)}else{u64(0)})
		scene.observations[state.index*3]=bits;scene.observations[state.index*3+1]=1+(read64(payload+8)>>33);scene.observations[state.index*3+2]=1+(read64(read64(scene.source+24)+8)>>33)
		if !state.api.native{worker:=spawn tm_reader();worker.wait()}
	}
	state.api.deallocate(owner,32,15)
}
fn tm_owner(a TMApi,m u64,state u64)u64{owner:=a.allocate(m,32,15);unsafe{*(&u64(owner+16))=state};return owner}
fn tm_ownership(a TMApi,m u64,source_tag u64,old_tag u64,slot u64)[6]u64{
	mut states:=[2]TMOwner{};mut previous:=[2]TMOwner{};mut source:=[u64(0xc01),0,0xa5a5a5a5a5a5a500|source_tag,0]!;mut dest:=[u64(0xd01),0,0xb5b5b5b5b5b5b500|old_tag,0]!
	page:=usize(C.getpagesize());region:=u64(C.mmap(unsafe{nil},page*4,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert region!=u64(-1)
	s:=region+u64(page)-32;d:=region+u64(page*3)-40;assert C.mprotect(voidptr(region+u64(page)),page,C.PROT_NONE)==0&&C.mprotect(voidptr(region+u64(page*3)),page,C.PROT_NONE)==0
	mut scene:=TMScene{api:a,source:s,destination:d}
	for i in 0..2{states[i]=TMOwner{api:a};p:=tm_owner(a,m,u64(unsafe{&states[i]}));source[if i==1{3}else if source_tag==0{1}else{0}]=p}
	if slot==3||slot==5{for i in 0..2{previous[i]=TMOwner{api:a,scene:u64(unsafe{&scene}),index:i};p:=tm_owner(a,m,u64(unsafe{&previous[i]}));dest[if i==1{3}else if old_tag==0{1}else{0}]=p}}
	saved:=source
	C.memcpy(voidptr(s),unsafe{&source[0]},32);C.memcpy(voidptr(d),unsafe{&dest[0]},32);unsafe{*(&u64(d+32))=0xbeef};assert C.mprotect(voidptr(region),page,C.PROT_READ)==0
	if slot==4||slot==5{for i in 0..2{p:=source[if i==1{3}else if source_tag==0{1}else{0}];if a.native{core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);retain:=unsafe{TMRetain(C.dlsym(core,c'swift_retain'))};retain(p)}else{swift_retain(p)}}}
	assert a.value(slot,d,s)==d&&C.memcmp(voidptr(s),unsafe{&saved[0]},32)==0&&read64(d+32)==0xbeef
	C.memcpy(unsafe{&dest[0]},voidptr(d),32)
	assert dest[0]==source[0]&&dest[1]==source[1]&&dest[3]==source[3]&&u8(dest[2])==u8(source[2])
	assert dest[2]>>8==if slot==4{source[2]>>8}else{u64(0xb5b5b5b5b5b5b5)}
	for i in 0..2{p:=source[if i==1{3}else if source_tag==0{1}else{0}];assert read64(p+8)==0x200000003}
	if slot==3||slot==5{assert previous[0].calls==1&&previous[1].calls==1&&scene.calls==2}
	a.call(1,d,a.metadata,0);for i in 0..2{p:=source[if i==1{3}else if source_tag==0{1}else{0}];assert read64(p+8)==3}
	a.call(1,s,a.metadata,0);assert states[0].calls==1&&states[1].calls==1
	assert C.munmap(voidptr(region),page*4)==0
	return scene.observations
}
fn tm_code(code u64){
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f0,0xaa0503f3,0xaa0103e0,0xaa0203e1,0xaa0303e2,0xaa0403e3,0xd28a0414,0xd28a0435,0xd63f0200,0xa9000660,0xa9015674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	write32(code+128,0xaa1403e0);write32(code+132,0x58000070);write32(code+136,0xd61f0200);unsafe{*(&u64(code+144))=u64(voidptr(tm_owner_destroy))};write32(code+160,0xdac10020);write32(code+164,0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code),voidptr(code+168))
}
fn tm_box(a TMApi,m u64){
	mut box:=SwiftArrayAllocation{}
	if a.native{core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);box=unsafe{TMBox(C.dlsym(core,c'swift_allocBox'))(a.metadata)}}else{owner:=swiftui_text_box_allocate();box=SwiftArrayAllocation{owner:owner,bytes:owner+16}}
	mut states:=[2]TMOwner{};C.memset(voidptr(box.bytes),0,32)
	for i,offset in [u64(8),24]!{states[i]=TMOwner{api:a};unsafe{*(&u64(box.bytes+offset))=tm_owner(a,m,u64(&states[i]))}}
	mut source:=[box.owner,u64(0xa5),0xa5]!;mut dest:=[u64(0xb5),0xb5,0xb5]!
	assert a.value(0,u64(unsafe{&dest[0]}),u64(unsafe{&source[0]}))==box.bytes&&dest==[box.owner,u64(0xb5),0xb5]!&&read64(box.owner+8)==0x200000003
	a.release(dest[0]);assert read64(box.owner+8)==3
	if !a.native{
		mut any_source:=[box.owner,u64(0xa5),0xa5,a.metadata]!;mut any_dest:=[u64(0xb5),0xb5,0xb5,0xb5]!
		swift_any_copy_checked(u64(unsafe{&any_dest[0]}),u64(unsafe{&any_source[0]})) or {panic(err)};assert any_dest==[box.owner,u64(0xb5),0xb5,a.metadata]!
		swift_any_destroy_checked(u64(unsafe{&any_dest[0]})) or {panic(err)};assert read64(box.owner+8)==3
		mut forged:=[u64(8),0,0]!;if _:=swiftui_text_buffer_copy_checked(u64(unsafe{&dest[0]}),u64(unsafe{&forged[0]}),a.metadata){assert false};assert dest==[box.owner,u64(0xb5),0xb5]!
	}
	a.release(box.owner);assert states[0].calls==1&&states[1].calls==1
}
fn tm_real_values(){
	mut words:=swift_interpolation_init(128,0);content:='owned Text metadata UTF-8 payload é 🎮';swift_string_append_bytes(u64(unsafe{&words}),u64(content.str),u64(content.len));owner:=words.second&swift_address_mask
	array:=swift_array_allocate(1,swift_string_metadata());swift_bridge_retain(words.second);unsafe{*(&SwiftStringWords(array.bytes))=words}
	mut source:=[words.first,words.second,u64(0),array.owner]!;mut dest:=[4]u64{}
	swiftui_text_value_copy(u64(unsafe{&dest[0]}),u64(unsafe{&source[0]}),0);assert read64(owner+8)==0x400000003&&read64(array.owner+8)==0x200000003
	swiftui_text_value_destroy(u64(unsafe{&dest[0]}),0);assert read64(owner+8)==0x200000003&&read64(array.owner+8)==3
	swiftui_text_value_destroy(u64(unsafe{&source[0]}),0);assert owner !in ios_runtime.swift_buffers&&array.owner !in ios_runtime.swift_arrays
}
fn tm_suite(a TMApi,code u64){
	w:=read64(a.metadata-8)&0x0000ffffffffffff;assert read64(w+64)==32&&read64(w+72)==32&&read32(w+80)==0x02030007&&read32(w+84)==0x7fffffff&&read32(a.metadata+16)==0&&read32(a.metadata+20)==24
	page:=usize(C.getpagesize());words:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert words!=u64(-1);m:=words+24;mut d:=code+128
	$if macos{if a.native{d=unsafe{TMSign(voidptr(code+160))(d,(m-16)|(u64(0xbbbf)<<48))}}}
	unsafe{*(&u64(m-16))=d;*(&u64(m+32))=2;*(&u64(m+40))=2;*(&u64(m+48))=0xf00000020;*(&u64(m+64))=words+128};assert C.mprotect(voidptr(words),page,C.PROT_READ)==0
	for source_tag in [u64(0),1]!{for old_tag in [u64(0),1]!{for slot in [u64(2),3,4,5]!{observed:=tm_ownership(a,m,source_tag,old_tag,slot);if slot==3||slot==5{assert observed==[u64(7),2,if slot==3{u64(1)}else{u64(2)},15,2,2]!;println('TEXT-ASSIGN native='+a.native.str()+' source='+source_tag.str()+' old='+old_tag.str()+' slot='+slot.str()+' observations='+observed.str())}}}}
	tm_box(a,m)
	region:=u64(C.mmap(unsafe{nil},page*3,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert region!=u64(-1);assert C.mprotect(voidptr(region),page,C.PROT_NONE)==0&&C.mprotect(voidptr(region+u64(page*2)),page,C.PROT_NONE)==0
	for count in [u32(0),1,255,0x7fffffff,0x80000000,0xffffffff]!{for tag in [u32(0),1,255,0x7fffffff,0x80000000,0xffffffff]!{if tag>count{continue};length:=if count>0x7fffffff{u64(33)}else{u64(32)};for p in [region+u64(page),region+u64(page*2)-length]!{
		C.memset(voidptr(p),0xa5,usize(length));a.raw(7,p,u64(tag),u64(count),a.metadata);assert a.call(6,p,u64(count),a.metadata)==tag
		for i in u64(0)..length{expected:=if i==32{if tag>0x7fffffff{u8(1)}else{u8(0)}}else if tag>0x7fffffff{if i<4{u8((tag-u32(0x80000000))>>(i*8))}else{u8(0)}}else if tag!=0&&i>=24{u8(u64(tag-1)>>((i-24)*8))}else{u8(0xa5)};assert unsafe{*(&u8(p+i))}==expected}
	}}}
	assert C.munmap(voidptr(region),page*3)==0
	assert C.munmap(voidptr(words),page)==0
}
fn tm_reader()u64{mut metadata:=u64(0);for _ in 0..128{candidate:=swiftui_text_metadata();if metadata==0{metadata=candidate}else{assert candidate==metadata};assert read64(candidate)==0x200};return metadata}
fn test_swiftui_text_metadata(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1);tm_code(code);assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos{tm_suite(tm_api(true,code),code);println('NATIVE-SWIFTUI-TEXT-METADATA: measured native storage ownership, copy/take padding, reentrant assignment observations and 32-byte layout')}
	for _ in 0..2{objc_start();mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn tm_reader()};mut metadata:=u64(0);for worker in workers{result:=worker.wait();if metadata==0{metadata=result}else{assert metadata==result}};unsafe{workers.free()};assert runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI4TextVN') or {panic(err)}==metadata;tm_suite(tm_api(false,code),code);tm_real_values();assert ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0;objc_stop();assert ios_runtime.swiftui_text_view_arena==0&&ios_runtime.swiftui_text_view_retired}
	assert C.munmap(voidptr(code),page)==0
	println('IOS-SWIFTUI-TEXT-METADATA: complete shared Text metadata, native 32-byte value witnesses, String/object storage and array ARC, copy/take padding, enum tags, eight cold readers and two drained lifetimes; SwiftUI Text construction, graph execution and rendering remain unsupported')
}
