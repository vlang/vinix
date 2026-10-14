// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.objc_allocateClassPair(voidptr,&char,usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr,voidptr,voidptr,&char) bool
fn C.mincore(voidptr,usize,&u8) i32
type NSObjectLookup = fn (u64,u64,u64) u64
type NSObjectMetadata = fn (u64) u64
type NSObjectSend = fn (u64,u64,u64,u64,u64) u64
type NSObjectHashWord = fn (i64,u64) i64
type NSObjectProbe = fn (u64,u64,u64,u64,u64,u64,&u64)
type NSObjectSign = fn (u64,u64) u64
struct NSObjectApi {
	native bool
	core voidptr
	overlay voidptr
	code u64
	root u64
	lookup NSObjectLookup = swift_witness_table
	metadata NSObjectMetadata = swift_objc_metadata
	word_hash NSObjectHashWord = swift_hasher_hash_word
	descriptors [2]u64
}
__global nsobject_hash_word u64
__global nsobject_equal_value bool
__global nsobject_hash_calls u64
__global nsobject_equal_calls u64
__global nsobject_equal_left u64
__global nsobject_equal_right u64
__global nsobject_reenter_metadata u64
fn nsobject_callback_worker(metadata u64) u64 { return swift_nsobject_table_checked(metadata,false) or {panic(err)} }
fn nsobject_hash_callback(_owner u64,_selector u64) u64 {
	nsobject_hash_calls++
	if nsobject_reenter_metadata != 0 { worker:=spawn nsobject_callback_worker(nsobject_reenter_metadata);assert worker.wait()!=0 }
	return nsobject_hash_word
}
fn nsobject_equal_callback(owner u64,_selector u64,other u64) bool {
	nsobject_equal_calls++;nsobject_equal_left=owner;nsobject_equal_right=other
	if nsobject_reenter_metadata != 0 { worker:=spawn nsobject_callback_worker(nsobject_reenter_metadata);assert worker.wait()!=0 }
	return nsobject_equal_value
}
fn nsobject_emit(code u64) {
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0603f3,0xaa0403f4,
		u32(0xd2800000 | (0x5121 << 5) | 21),0xaa0503f0,0xd63f0200,0xa9000660,0xa9015674,
		0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]! {write32(code + u64(i*4),op)}
	write32(code+128,0xdac10820);write32(code+132,0xd65f03c0)
}
fn nsobject_api(native bool,code u64) NSObjectApi {
	$if macos {if native {
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);overlay:=C.dlopen(c'/usr/lib/swift/libswiftObjectiveC.dylib',2);assert core!=unsafe {nil}&&overlay!=unsafe {nil}
		return NSObjectApi{native:true,core:core,overlay:overlay,code:code,root:u64(C.objc_getClass(c'NSObject')),
			lookup:unsafe {NSObjectLookup(C.dlsym(core,c'swift_getWitnessTable'))},metadata:unsafe {NSObjectMetadata(C.dlsym(core,c'swift_getObjCClassMetadata'))},
			word_hash:unsafe {NSObjectHashWord(C.dlsym(core,c'$ss6HasherV5_hash4seed_S2i_SutFZ'))},
			descriptors:[u64(C.dlsym(overlay,c'$sSo8NSObjectCSH10ObjectiveCMc')),u64(C.dlsym(overlay,c'$sSo8NSObjectCSQ10ObjectiveCMc'))]!}
	}}
	return NSObjectApi{code:code,root:ios_runtime.names['NSObject'],descriptors:[runtime_symbol('/usr/lib/swift/libswiftObjectiveC.dylib','_$sSo8NSObjectCSH10ObjectiveCMc') or {panic(err)},runtime_symbol('/usr/lib/swift/libswiftObjectiveC.dylib','_$sSo8NSObjectCSQ10ObjectiveCMc') or {panic(err)}]!}
}
fn (api NSObjectApi) message(owner u64,name &char,arg u64) u64 {
	$if macos {if api.native {entry:=C.dlsym(unsafe {voidptr(-2)},c'objc_msgSend');return unsafe {NSObjectSend(entry)(owner,u64(C.sel_registerName(name)),arg,0,0)}}}
	return unsafe {NSObjectSend(voidptr(C.ios_objc_builtin))(owner,u64(name),arg,0,0)}
}
fn (api NSObjectApi) refs(owner u64) u64 {return if api.native {api.message(owner,c'retainCount',0)} else {u64(obj_header(owner).refs)}}
fn (api NSObjectApi) cls(parent u64,name &char,methods bool) u64 {
	$if macos {if api.native {
		cls:=u64(C.objc_allocateClassPair(voidptr(parent),name,0));assert cls!=0
		if methods {assert C.class_addMethod(voidptr(cls),C.sel_registerName(c'hash'),unsafe {voidptr(nsobject_hash_callback)},c'Q16@0:8');assert C.class_addMethod(voidptr(cls),C.sel_registerName(c'isEqual:'),unsafe {voidptr(nsobject_equal_callback)},c'B24@0:8@16')}
		C.objc_registerClassPair(voidptr(cls));return cls
	}}
	cls:=objc_allocate_class(parent,name,0);assert cls!=0
	if methods {assert objc_add_method(cls,u64(c'hash'),u64(unsafe {voidptr(nsobject_hash_callback)}),c'Q16@0:8');assert objc_add_method(cls,u64(c'isEqual:'),u64(unsafe {voidptr(nsobject_equal_callback)}),c'B24@0:8@16')}
	objc_register_class(cls);return cls
}
fn (api NSObjectApi) table(metadata u64,equal bool) u64 {
	mut descriptor:=api.descriptors[if equal {1} else {0}]
	if api.native {descriptor=unsafe {NSObjectSign(voidptr(api.code+128))(descriptor,0xc6eb)}}
	return api.lookup(descriptor,metadata,0)&0x0000ffffffffffff
}
fn nsobject_call(api NSObjectApi,entry u64,a u64,b u64,c u64,d u64,receiver u64) u64 {
	mut result:=[u64(0x1234),0,0,0,0,0x5678]!
	unsafe {NSObjectProbe(voidptr(api.code))(a,b,c,d,receiver,entry&0x0000ffffffffffff,&result[1])}
	assert result[0]==0x1234&&result[5]==0x5678&&result[3]==receiver&&result[4]==0x5121
	return result[1]
}
fn nsobject_layout(api NSObjectApi,metadata u64,root_equal u64) u64 {
	hash:=api.table(metadata,false);equal:=api.table(metadata,true);assert hash!=0&&equal!=0&&hash!=equal
	assert api.table(metadata,false)==hash&&api.table(metadata,true)==equal
	assert read64(hash)&0x0000ffffffffffff==api.descriptors[0]&0x0000ffffffffffff
	assert read64(equal)&0x0000ffffffffffff==api.descriptors[1]&0x0000ffffffffffff
	assert read64(hash+8)&0x0000ffffffffffff==root_equal
	for i in 2..5 {assert read64(hash+u64(i*8))&0x0000ffffffffffff!=0}
	assert read64(equal+8)&0x0000ffffffffffff!=0
	if !api.native {
		for i,descriptor in api.descriptors {
			assert read32(descriptor+12)==0x20018&&read32(descriptor+16)==if i==0 {u32(0x10005)} else {u32(0x10002)}
			assert read64(u64(i64(descriptor+4)+i64(i32(read32(descriptor+4)))))==api.root
		}
	}
	return hash
}
fn nsobject_values(api NSObjectApi,metadata u64,hash u64,owner u64,other u64) {
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe {nil},usize(page*2),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1)
	assert C.mprotect(voidptr(base+page),usize(page),C.PROT_NONE)==0
	left:=base+page-8;right:=base+page-24;state:=base+page-112
	unsafe {*(&u64(left))=owner;*(&u64(right))=other;*(&u64(left-8))=0x1122;*(&u64(right-8))=0x3344}
	refs:=api.refs(owner);other_refs:=api.refs(other);equal:=read64(hash+8)&0x0000ffffffffffff
	for bits in [u64(0),1,0x7fffffffffffffff,0x8000000000000000,0xffffffffffffffff]! {
		nsobject_hash_word=bits;before:=nsobject_hash_calls
		assert nsobject_call(api,read64(hash+16),metadata,hash,0,0,left)==bits&&nsobject_hash_calls==before+1
		mut expected:=swift_hasher_raw_seed(0x1234,0x5678);swift_hasher_byte(mut expected,0x39)
		unsafe {*(&SwiftHasher(state))=expected;*(&u64(state-8))=0xa5;*(&u64(state+72))=0x5a}
		swift_hasher_word(mut expected,bits)
		nsobject_call(api,read64(hash+24),state,metadata,hash,0,left)
		assert C.memcmp(voidptr(state),unsafe {&expected},72)==0&&read64(state-8)==0xa5&&read64(state+72)==0x5a
		for seed in [i64(0),1,-1,i64(0x8000000000000000),i64(0x7fffffffffffffff)]! {
			assert i64(nsobject_call(api,read64(hash+32),u64(seed),metadata,hash,0,left))==api.word_hash(seed,bits)
		}
	}
	for expected in [false,true]! {
		nsobject_equal_value=expected;before:=nsobject_equal_calls
		assert (nsobject_call(api,read64(equal+8),left,right,metadata,equal,0)&1!=0)==expected
		assert nsobject_equal_calls==before+1&&nsobject_equal_left==owner&&nsobject_equal_right==other
		// Same-pointer equality still sends isEqual:, including false overrides.
		assert (nsobject_call(api,read64(equal+8),left,left,metadata,equal,0)&1!=0)==expected
	}
	assert read64(left-8)==0x1122&&read64(right-8)==0x3344&&read64(left)==owner&&read64(right)==other
	assert api.refs(owner)==refs&&api.refs(other)==other_refs
	unsafe {*(&u64(left))=0;*(&u64(right))=0}
	assert nsobject_call(api,read64(hash+16),metadata,hash,0,0,left)==0
	assert nsobject_call(api,read64(equal+8),left,right,metadata,equal,0)==0
	assert C.munmap(voidptr(base),usize(page*2))==0
}
fn nsobject_lookup_worker(metadata u64) u64 {return swift_nsobject_table_checked(metadata,false) or {panic(err)}}
fn nsobject_integration(api NSObjectApi,metadata u64,hash u64,owner u64,other u64) {
	array:=swift_array_allocate(3,metadata);mut source:=owner
	copy_ref:=unsafe {NSObjectLookup(voidptr(read64(read64(metadata-8)+16)))}
	for i,value in [owner,other,owner]! {source=value;copy_ref(array.bytes+u64(i*8),u64(unsafe {&source}),metadata)}
	assert api.refs(owner)==3&&api.refs(other)==2;swift_bridge_release(array.owner);assert api.refs(owner)==1&&api.refs(other)==1
	set:=swift_set_access(0,metadata,hash);assert read64(set.metadata+16)==metadata&&read64(set.metadata+24)==hash
	assert swift_set_minimum_capacity(0,metadata,hash)==ios_runtime.swift_empty_set
	page:=u64(C.getpagesize());base:=u64(C.mmap(unsafe {nil},usize(page*2),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1)
	assert C.mprotect(voidptr(base+page),usize(page),C.PROT_NONE)==0;protected:=base+page
	for i,descriptor in api.descriptors {
		length:=if i==0 {u64(40)} else {u64(16)};output:=protected-length
		unsafe {*(&u64(output-8))=0x55};entry:=u64(i64(descriptor+20)+i64(i32(read32(descriptor+20))))
		nsobject_call(api,entry,output,metadata,protected,0,0)
		assert read64(output-8)==0x55&&C.memcmp(voidptr(output),voidptr(api.table(metadata,i!=0)),usize(length))==0
	}
	for invalid in [u64(0),1,protected,swift_integer_metadata()]! {if _:=swift_nsobject_table_checked(invalid,false) {assert false};if _:=swift_nsobject_instantiate_checked(protected,invalid,false) {assert false}}
	mut value:=protected;before:=nsobject_hash_calls
	if _:=swift_nsobject_hash_checked(metadata,hash,u64(unsafe {&value})) {assert false}
	if _:=swift_nsobject_hash_checked(protected,protected,protected) {assert false}
	if _:=swift_nsobject_hash_into_checked(protected,protected,protected,protected) {assert false}
	if _:=swift_nsobject_equal_checked(protected,protected,protected,protected) {assert false}
	assert nsobject_hash_calls==before
	assert C.munmap(voidptr(base),usize(page*2))==0
}
fn nsobject_run(api NSObjectApi) {
	parent:=api.cls(api.root,c'VinixSwiftHashableBase',true);cls:=api.cls(parent,c'VinixSwiftHashableChild',false)
	owner:=api.message(cls,c'new',0);other:=api.message(cls,c'new',0);assert owner!=0&&other!=0&&api.refs(owner)==1&&api.refs(other)==1
	root_meta:=api.metadata(api.root);metadata:=api.metadata(cls);root_equal:=api.table(root_meta,true)
	root_hash:=nsobject_layout(api,root_meta,root_equal)
	if !api.native {mut workers:=[]thread u64{cap:8};for _ in 0..8 {workers<<spawn nsobject_lookup_worker(metadata)};tables:=workers.wait();for table in tables {assert table==tables[0]};unsafe {tables.free();workers.free()}}
	hash:=nsobject_layout(api,metadata,root_equal);assert hash!=root_hash
	nsobject_values(api,metadata,hash,owner,other)
	if !api.native {
		nsobject_reenter_metadata=metadata;nsobject_hash_word=0x1234;nsobject_equal_value=true
		mut value:=owner;assert swift_nsobject_hash_checked(metadata,hash,u64(unsafe {&value})) or {panic(err)}==0x1234
		assert swift_nsobject_equal_checked(u64(unsafe {&value}),u64(unsafe {&value}),metadata,read64(hash+8)) or {panic(err)}
		nsobject_reenter_metadata=0;nsobject_integration(api,metadata,hash,owner,other)
	}
	api.message(owner,c'release',0);api.message(other,c'release',0)
}
fn test_swift_nsobject_hashable() {
	page:=usize(C.getpagesize());code:=C.mmap(unsafe {nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert code!=voidptr(-1)
	nsobject_emit(u64(code));C.__builtin___clear_cache(code,voidptr(u64(code)+136));assert C.mprotect(code,page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos {nsobject_run(nsobject_api(true,u64(code)));println('IOS-NSOBJECT-HASHABLE-NATIVE: per-type generic tables with inherited NSObject Equatable identity, raw Objective-C hashValue, Hasher word combination and signed seeded hashes, nonreflexive isEqual overrides, nil messages, borrowed owners, guarded reference/state spans and preserved x20/x21')}
	for symbol in ['_$sSo8NSObjectCSH10ObjectiveCMc','_$sSo8NSObjectCSQ10ObjectiveCMc']! {assert runtime_symbol('/usr/lib/swift/libswiftObjectiveC.dylib',symbol)==none}
	for _ in 0..2 {
		objc_start();api:=nsobject_api(false,u64(code));nsobject_run(api)
		for symbol in ['_$sSo8NSObjectCSH10ObjectiveCMc','_$sSo8NSObjectCSQ10ObjectiveCMc']! {assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib',symbol)==none;assert runtime_symbol('/usr/lib/swift/libswiftObjectiveC.dylib',symbol[1..])==none}
		assert runtime_symbol('/usr/lib/swift/libswiftObjectiveC.dylib','_$sSo8NSObjectCs7CVarArg10ObjectiveCMc')==none
		assert ios_runtime.live==0&&ios_runtime.objects.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0
		mut pages:=[]u64{};for _,table in ios_runtime.swift_nsobject_hashable_tables {pages<<table};arena:=ios_runtime.swift_nsobject_hashable_arena
		objc_stop();assert ios_runtime.swift_nsobject_hashable_arena==0&&ios_runtime.swift_nsobject_hashable_tables.len==0&&ios_runtime.swift_nsobject_hashable_retired
		for offset in [u64(0),u64(page),u64(page*2)]! {pages<<arena+offset}
		for address in pages {$if macos {assert C.mprotect(voidptr(address),page,C.PROT_READ)==-1} $else {mut resident:=u8(0);assert C.mincore(voidptr(address),page,&resident)==-1}}
		if _:=swift_nsobject_table_checked(~u64(0),false) {assert false};if _:=swift_nsobject_borrow_checked(~u64(0),~u64(0),~u64(0),~u64(0),false) {assert false}
		assert runtime_symbol('/usr/lib/swift/libswiftObjectiveC.dylib','_$sSo8NSObjectCSH10ObjectiveCMc')==none;unsafe {pages.free()}
	}
	assert C.munmap(code,page)==0
	println('IOS-NSOBJECT-HASHABLE: scoped generic NSObject Equatable/Hashable descriptors, canonical sealed per-wrapper tables and inherited base equality, dynamic message overrides with unlocked reentry, protected borrowed values/state and explicit unsupported rejection, signed seeded hashing, typed Array ARC and Set metadata, eight initializers and two drained/unmapped cycles')
}
