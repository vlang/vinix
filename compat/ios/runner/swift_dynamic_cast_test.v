// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#include <objc/runtime.h>
}
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.objc_allocateClassPair(voidptr,&char,usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.objc_disposeClassPair(voidptr)
fn C.class_createInstance(voidptr,usize) voidptr
fn C.sel_registerName(&char) voidptr
type DynamicProbe = fn (u64,u64,u64,u64,u64,u64,&u64)
type DynamicSign = fn (u64,u64) u64
type DynamicCall = fn (u64,u64,u64,u64,u64) bool
type DynamicCString = fn (&char) SwiftStringWords
type DynamicDrop = fn (u64)
type DynamicKeep = fn (u64) u64
type DynamicMetadata = fn (u64) u64
type DynamicCount = fn (u64,u64) u64

struct DynamicApi {
	native bool
	entry u64
	code u64
	integer u64
	byte_type u64
	string_type u64
	any_type u64
	base u64
	leaf u64
	other u64
	base_type u64
	leaf_type u64
	other_type u64
	keep DynamicKeep = objc_retain
	drop DynamicDrop = objc_release
	send u64
}
fn dynamic_emit(code u64) {
	for i,word in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0603f3,0xaa0503f0,0xd28a0414,0xd28a0435,0xd63f0200,0xa9005260,0xf9000a75,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! {write32(code+u64(i)*4,word)}
	write32(code+64,0xdac10020);write32(code+68,0xd65f03c0)
	write32(code+80,0xdac10820);write32(code+84,0xd65f03c0)
}
fn dynamic_api(native bool,code u64) DynamicApi {
	$if macos {if native {
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);objc:=C.dlopen(c'/usr/lib/libobjc.A.dylib',2)
		base:=u64(C.objc_allocateClassPair(C.objc_getClass(c'NSObject'),c'VinixNativeDynamicBase',0));assert base!=0;C.objc_registerClassPair(voidptr(base))
		leaf:=u64(C.objc_allocateClassPair(voidptr(base),c'VinixNativeDynamicLeaf',0));assert leaf!=0;C.objc_registerClassPair(voidptr(leaf))
		other:=u64(C.objc_allocateClassPair(C.objc_getClass(c'NSObject'),c'VinixNativeDynamicOther',0));assert other!=0;C.objc_registerClassPair(voidptr(other))
		metadata:=unsafe {DynamicMetadata(C.dlsym(core,c'swift_getObjCClassMetadata'))}
		return DynamicApi{native:true,code:code,entry:u64(C.dlsym(core,c'swift_dynamicCast')),integer:u64(C.dlsym(core,c'$sSiN')),byte_type:u64(C.dlsym(core,c'$ss5UInt8VN')),string_type:u64(C.dlsym(core,c'$sSSN')),any_type:u64(C.dlsym(core,c'$sypN'))+8,
			base:base,leaf:leaf,other:other,base_type:metadata(base),leaf_type:metadata(leaf),other_type:metadata(other),keep:unsafe {DynamicKeep(C.dlsym(objc,c'objc_retain'))},drop:unsafe {DynamicDrop(C.dlsym(objc,c'objc_release'))},send:u64(C.dlsym(objc,c'objc_msgSend'))}
	}}
	base:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixDynamicBase',0);objc_register_class(base)
	leaf:=objc_allocate_class(base,c'VinixDynamicLeaf',0);objc_register_class(leaf)
	other:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixDynamicOther',0);objc_register_class(other)
	return DynamicApi{code:code,entry:runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_dynamicCast') or {panic(err)},integer:swift_integer_metadata(),byte_type:runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$ss5UInt8VN') or {panic(err)},string_type:swift_string_metadata(),any_type:swift_any_full_metadata()+8,
		base:base,leaf:leaf,other:other,base_type:swift_objc_metadata(base),leaf_type:swift_objc_metadata(leaf),other_type:swift_objc_metadata(other)}
}
fn dynamic_call(api DynamicApi,destination u64,source u64,from u64,to u64,flags u64) bool {
	mut registers:=[3]u64{};call:=unsafe {DynamicProbe(voidptr(api.code))}
	call(destination,source,from,to,flags,api.entry,unsafe {&registers[0]})
	assert registers[0]<=1&&registers[1]==0x5020&&registers[2]==0x5021;return registers[0]!=0
}
fn dynamic_refs(api DynamicApi,owner u64,string_owner bool) u64 {
	if string_owner {return (read64(owner+8)>>33)+1}
	$if macos {if api.native {count:=unsafe {DynamicCount(voidptr(api.send))};return count(owner,u64(C.sel_registerName(c'retainCount')))}}
	return u64(obj_header(owner).refs)
}
fn dynamic_object(api DynamicApi,cls u64) u64 {
	$if macos {if api.native {return u64(C.class_createInstance(voidptr(cls),0))}}
	return objc_allocate(cls)
}
fn dynamic_string(api DynamicApi) SwiftStringWords {
	text:='owned long String for Swift dynamic casts é 🎮'
	$if macos {if api.native {core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);create:=unsafe {DynamicCString(C.dlsym(core,c'$sSS7cStringSSSPys4Int8VG_tcfC'))};return create(text.str)}}
	mut words:=swift_interpolation_init(80,0);swift_string_append_bytes(u64(unsafe {&words}),u64(text.str),u64(text.len));return words
}
fn dynamic_string_drop(api DynamicApi,owner u64) {
	$if macos {if api.native {core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);drop:=unsafe {DynamicDrop(C.dlsym(core,c'swift_bridgeObjectRelease'))};drop(owner);return}}
	swift_bridge_release(owner)
}
fn dynamic_owned_cases(api DynamicApi) {
	for mode in 0..5 {for flags in u64(0)..8 {
		fails:=mode==3||mode==4;if fails&&flags&1!=0 {continue}
		words:=dynamic_string(api);owner:=words.second&swift_address_mask
		mut source:=[words.first,words.second,u64(0x1234),api.string_type]!
		mut destination:=[u64(0xaaaaaaaaaaaaaaaa),0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa]!
		from:=if mode==2||mode==4 {api.any_type}else{api.string_type};to:=if mode==1 {api.any_type}else if fails {api.integer}else{api.string_type}
		assert dynamic_refs(api,owner,true)==1
		assert dynamic_call(api,u64(unsafe {&destination[0]}),u64(unsafe {&source[0]}),from,to,flags)==!fails
		assert source==[words.first,words.second,u64(0x1234),api.string_type]!
		if fails {
			assert destination==[u64(0xaaaaaaaaaaaaaaaa),0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa]!
			if flags&4==0 {assert dynamic_refs(api,owner,true)==1;dynamic_string_drop(api,source[1])}
		} else {
			assert destination[0]==words.first&&destination[1]==words.second&&destination[2]==0xaaaaaaaaaaaaaaaa
			assert destination[3]==if to==api.any_type {api.string_type}else{u64(0xaaaaaaaaaaaaaaaa)}
			assert dynamic_refs(api,owner,true)==if flags&2==0 {u64(2)}else{u64(1)}
			dynamic_string_drop(api,destination[1]);if flags&2==0 {dynamic_string_drop(api,source[1])}
		}
	}}
	for mode in 0..6 {for flags in u64(0)..8 {
		fails:=mode==4||mode==5;if fails&&flags&1!=0 {continue}
		owner:=dynamic_object(api,if mode==5 {api.base}else{api.leaf})
		mut source:=[owner,u64(0x2345),0x3456,api.base_type]!
		mut destination:=[u64(0xaaaaaaaaaaaaaaaa),0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa]!
		from:=if mode==3 {api.any_type}else if mode==0 {api.leaf_type}else{api.base_type}
		if mode==3 {source[3]=api.base_type}
		to:=if mode==2 {api.any_type}else if mode==4 {api.other_type}else if mode==0 {api.base_type}else{api.leaf_type}
		assert dynamic_call(api,u64(unsafe {&destination[0]}),u64(unsafe {&source[0]}),from,to,flags)==!fails
		if fails {
			assert destination==[u64(0xaaaaaaaaaaaaaaaa),0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa]!
			if flags&4==0 {assert dynamic_refs(api,owner,false)==1;api.drop(owner)}
		} else {
			assert destination[0]==owner&&destination[1]==0xaaaaaaaaaaaaaaaa&&destination[2]==0xaaaaaaaaaaaaaaaa
			assert destination[3]==if to==api.any_type {api.base_type}else{u64(0xaaaaaaaaaaaaaaaa)}
			assert dynamic_refs(api,owner,false)==if flags&2==0 {u64(2)}else{u64(1)}
			api.drop(destination[0]);if flags&2==0 {api.drop(source[0])}
		}
	}}
}
fn dynamic_inline_cases(api DynamicApi) {
	for flags in u64(0)..8 {
		for mode in 0..6 {
			if mode==5&&flags&1!=0 {continue}
			mut source:=[u64(42),0x2345,0x3456,api.integer]!
			mut destination:=[u64(0xaaaaaaaaaaaaaaaa),0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa]!
			from:=if mode==2||mode==3||mode==5 {api.any_type}else if mode==4 {api.byte_type}else{api.integer}
			to:=if mode==1||mode==3 {api.any_type}else if mode==4||mode==5 {api.byte_type}else{api.integer}
			assert dynamic_call(api,u64(unsafe {&destination[0]}),u64(unsafe {&source[0]}),from,to,flags)==(mode!=5)
			if mode==5 {assert destination==[u64(0xaaaaaaaaaaaaaaaa),0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa,0xaaaaaaaaaaaaaaaa]!;continue}
			assert destination[0]==if mode==4 {u64(0xaaaaaaaaaaaaaa2a)}else{u64(42)}
			if mode==3&&flags&2!=0 {assert destination==source}
			else {assert destination[1]==0xaaaaaaaaaaaaaaaa&&destination[2]==0xaaaaaaaaaaaaaaaa;assert destination[3]==if to==api.any_type {api.integer}else{u64(0xaaaaaaaaaaaaaaaa)}}
		}
	}
}
struct DynamicTrace { size u64 metadata u64 published bool reenter bool mut: copied int taken int destroyed int }
fn dynamic_resolver() {assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_swift_dynamicCast') or {panic(err)}!=0}
fn dynamic_trace_copy(destination u64,source u64,metadata u64) u64 {
	mut state:=unsafe {&DynamicTrace(read64(metadata+16))};state.copied++
	if state.published {assert read64(destination+24)==metadata}
	C.memcpy(voidptr(destination),voidptr(source),usize(state.size))
	if state.reenter {worker:=spawn dynamic_resolver();worker.wait()};return destination
}
fn dynamic_trace_take(destination u64,source u64,metadata u64) u64 {
	mut state:=unsafe {&DynamicTrace(read64(metadata+16))};state.taken++
	if state.published {assert read64(destination+24)==metadata}
	C.memcpy(voidptr(destination),voidptr(source),usize(state.size));return destination
}
fn dynamic_trace_destroy(_source u64,metadata u64) {mut state:=unsafe {&DynamicTrace(read64(metadata+16))};state.destroyed++}
fn dynamic_trace_cases(api DynamicApi,base u64) {
	witness:=base+64;metadata:=base+8
	for size in [u64(0),1,3,16,24,32]! {
		mut state:=DynamicTrace{size:size,metadata:metadata,reenter:!api.native}
		unsafe {*(&u64(base))=witness;*(&u64(metadata))=0x200;*(&u64(metadata+8))=read64(api.string_type+8);*(&u64(metadata+16))=u64(&state)
			*(&u64(witness+8))=u64(voidptr(dynamic_trace_destroy));*(&u64(witness+16))=u64(voidptr(dynamic_trace_copy));*(&u64(witness+32))=u64(voidptr(dynamic_trace_take));*(&u64(witness+64))=size;*(&u64(witness+72))=if size==0 {u64(1)}else{(size+7)&~u64(7)};*(&u32(witness+80))=0x110000|if size==0 {u32(0)}else{u32(7)}|if size>24 {u32(0x20000)}else{u32(0)}}
		$if macos {if api.native {
			sign_code:=unsafe {DynamicSign(voidptr(api.code+64))};sign_data:=unsafe {DynamicSign(voidptr(api.code+80))}
			for offset in [u64(8),16,32]! {unsafe {*(&u64(witness+offset))=sign_code(read64(witness+offset),(witness+offset)|(u64(1272)<<48))}}
			unsafe {*(&u64(base))=sign_data(witness,base|(u64(11839)<<48))}
		}}
		for mode in 0..3 {if mode!=0&&size>24 {continue};for flags in u64(0)..8 {
			state=DynamicTrace{size:size,metadata:metadata,reenter:!api.native,published:mode==1}
			mut source_words:=[8]u64{};mut destination_words:=[8]u64{}
			source:=unsafe {&u8(&source_words[0])};destination:=unsafe {&u8(&destination_words[0])}
			for i in 0..64 {unsafe {source[i]=u8(i+1);destination[i]=0x5a}}
			unsafe {*(&u64(&source[24]))=metadata}
			from:=if mode==2 {api.any_type}else{metadata};to:=if mode==1 {api.any_type}else{metadata}
			assert dynamic_call(api,u64(unsafe {&destination[0]}),u64(unsafe {&source[0]}),from,to,flags)
			assert state.copied==if flags&2==0 {1}else{0};assert state.taken==if flags&2!=0 {1}else{0};assert state.destroyed==0
			assert C.memcmp(unsafe {&destination[0]},unsafe {&source[0]},usize(size))==0
			for i in int(size)..64 {if mode==1&&i>=24&&i<32 {continue};assert unsafe {destination[i]}==0x5a}
		}}
	}
}
fn dynamic_rejections(api DynamicApi,guard u64) {
	mut source:=[u64(13),0,0,api.integer]!;mut destination:=[u64(0xaaaa),0xaaaa,0xaaaa,0xaaaa]!
	dst:=u64(unsafe {&destination[0]});src:=u64(unsafe {&source[0]})
	for flags in [u64(8),16,0x8000000000000000]! {if _:=swift_dynamic_cast_checked(guard,guard,guard,guard,flags){assert false}}
	for mode in 0..2 {if _:=swift_dynamic_cast_checked(dst,src,if mode==0 {u64(0)}else{api.integer},if mode==1 {u64(1)}else{api.integer},0){assert false}}
	if _:=swift_dynamic_cast_checked(src,src,api.integer,api.integer,2){assert false}
	if _:=swift_dynamic_cast_checked(dst,src,api.integer,api.byte_type,5){assert false}
	assert destination==[u64(0xaaaa),0xaaaa,0xaaaa,0xaaaa]!
	words:=swift_string_literal(c'short',5,true);unsafe {*(&SwiftStringWords(src))=words}
	if _:=swift_dynamic_cast_checked(dst,src,api.string_type,api.base_type,4){assert false}
	box:=swift_any_box_allocate();unsafe {*(&SwiftStringWords(box+16))=words;*(&u64(box+40))=api.string_type;*(&u64(src))=box;*(&u64(src+24))=api.any_type}
	if _:=swift_dynamic_cast_checked(dst,src,api.any_type,api.string_type,6){assert false}
	assert read64(box+8)==3;swift_release(box)
	ios_runtime.swift_concurrency_retired=true;if _:=swift_dynamic_cast_checked(guard,guard,guard,guard,0){assert false};ios_runtime.swift_concurrency_retired=false
}
fn test_swift_dynamic_cast() {
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe {nil},page*3,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
	dynamic_emit(code);C.__builtin___clear_cache(voidptr(code),voidptr(code+88));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	data:=code+u64(page);guard:=data+u64(page);assert C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
	$if macos {api:=dynamic_api(true,code);dynamic_inline_cases(api);dynamic_owned_cases(api);dynamic_trace_cases(api,data);for cls in [api.leaf,api.base,api.other]! {C.objc_disposeClassPair(voidptr(cls))};println('IOS-DYNAMIC-CAST-NATIVE: flags0..7, String and ObjC copy/take/failure ownership, Int/UInt8 and inline Any wrap/unwrap/identity padding, class up/down/failing casts, unchanged failed destination/source bytes, exact witness traces for sizes0/1/3/16/24/32, Any metadata publication and x20/x21')}
	for _ in 0..2 {
		objc_start();api:=dynamic_api(false,code);dynamic_inline_cases(api);dynamic_owned_cases(api);dynamic_trace_cases(api,data);dynamic_rejections(api,guard)
		if _:=runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib','_swift_dynamicCast'){assert false}
		if _:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','__swift_dynamicCast'){assert false}
		assert ios_runtime.live==0&&ios_runtime.objects.len==0&&ios_runtime.swift_heap.len==0;objc_stop();assert ios_runtime.live==0
	}
	assert C.munmap(voidptr(code),page*3)==0
	println('IOS-DYNAMIC-CAST: exact Core-only cast export, native ownership flags and inline Any/class paths, callback/publication/padding ABI, unsupported bridging/boxed Any/overlap/flags reject without consumption, static forced failure, reentrant unlocked witness lookup and two drained lifetimes')
}
