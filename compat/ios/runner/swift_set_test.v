// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
type SetInvoke = fn (u64, &u64, u64, u64, &u64)
type SetAccess = fn (u64, u64, u64) SwiftAssociatedMetadata
type SetConstruct = fn (i64, u64, u64) u64
type SetLookup = fn (u64, u64, u64) u64
type SetDrop = fn (u64)
type SetKeep = fn (u64) u64
type SetAssociate = fn (u64, u64, u64, u64, u64) SwiftAssociatedMetadata
type SetConformance = fn (u64, u64, u64, u64, u64) u64
type SetBox = fn (u64) SwiftArrayAllocation
type SetSign = fn (u64, u64) u64
struct SetApi {
	native bool
	core voidptr
	code u64
	element u64
	descriptor u64
	access SetAccess = swift_set_access
	construct SetConstruct = swift_set_minimum_capacity
	lookup SetLookup = swift_witness_table
	keep SetKeep = swift_bridge_retain
	drop SetDrop = swift_bridge_release
}
fn set_api(native bool, code u64, reference bool) SetApi {
	$if macos { if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2)
		return SetApi{native: true, core: core, code: code, element: u64(C.dlsym(core,if reference {c'$sSSN'} else {c'$sSiN'})), descriptor: u64(C.dlsym(core,c'$sShyxGSTsMc')),
			access: unsafe {SetAccess(C.dlsym(core,c'$sShMa'))}, construct: unsafe {SetConstruct(C.dlsym(core,c'$sSh15minimumCapacityShyxGSi_tcfC'))}, lookup: unsafe {SetLookup(C.dlsym(core,c'swift_getWitnessTable'))},
			keep: unsafe {SetKeep(C.dlsym(core,c'swift_bridgeObjectRetain'))}, drop: unsafe {SetDrop(C.dlsym(core,c'swift_bridgeObjectRelease'))}}
	} }
	return SetApi{code: code,element: if reference {swift_string_metadata()} else {swift_integer_metadata()},descriptor: runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sShyxGSTsMc') or {panic(err)}}
}
fn set_emit(code u64) {
	for i, op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f0,0xaa0103e9,0xaa0203f4,0xaa0303e8,0xaa0403f3,
		0xa9400520,0xa9410d22,0xf9401124,0xaa1f03f5,0xd63f0200,0xf9000260,0xf9000661,0xf9000a75,0xf9000e74,
		0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]! {write32(code + u64(i * 4),op)}
	// Collision-heavy caller conformance exercises real Hashable/Equatable
	// forwarding and reference ownership without depending on String hashing.
	write32(code + 128,0xd2800000);write32(code + 132,0xd65f03c0)
	write32(code + 144,0xd2801000);write32(code + 148,0xd65f03c0) // Hash 128: two initially empty bitmap words.
	write32(code + 160,0x58000050);write32(code + 164,0xd61f0200);unsafe {*(&u64(code + 168)) = u64(voidptr(set_equal))}
	write32(code + 192,0xdac10020);write32(code + 196,0xd65f03c0)
	for i, op in [u32(0xa9bf7bfd),0xaa1403e1,0x580000d0,0xd63f0200,0xaa0103f5,0xa8c17bfd,0xd65f03c0]! {write32(code + 256 + u64(i * 4),op)}
	unsafe {*(&u64(code + 288)) = u64(voidptr(set_predicate))}
	for i, op in [u32(0xa9bf7bfd),0xaa1403e1,0xaa0803e2,0x580000b0,0xd63f0200,0xaa0003f5,0xa8c17bfd,0xd65f03c0]! {write32(code + 320 + u64(i * 4),op)}
	unsafe {*(&u64(code + 352)) = u64(voidptr(set_transform))}
	// Private unique conformance identities. These fixtures never ask native
	// conformance discovery to find them; cache keys still require a descriptor.
	write32(code + 512,0);write32(code + 524,0);write32(code + 544,0);write32(code + 556,0)
}
fn set_equal(left u64, right u64, metadata u64, _table u64) bool {
	return if read64(read64(metadata - 8) + 64) == 16 {read64(left + 8) == read64(right + 8)} else {read64(left) == read64(right)}
}
fn set_call(api SetApi, entry u64, args [5]u64, receiver u64, output u64) [4]u64 {
	capture := set_call_throwing(api,entry,args,receiver,output);assert capture[2]==0;return capture
}
fn set_call_throwing(api SetApi, entry u64, args [5]u64, receiver u64, output u64) [4]u64 {
	mut capture := [u64(0),0,0,0]!;call := unsafe {SetInvoke(voidptr(api.code))}
	call(entry & 0x0000ffffffffffff,unsafe {&args[0]},receiver,output,unsafe {&capture[0]})
	assert capture[3] == receiver;return capture
}
struct SetCallback {
	api SetApi
	reference bool
	expected []u64
	error u64
	throws bool
mut:
	calls int
}
fn set_callback_check(input u64, mut state SetCallback) int {
	index := state.calls;assert index<state.expected.len && set_value_id(input,state.reference)==state.expected[index]
	if state.reference {assert set_object_refs(state.api,state.expected[index])==3}
	state.calls++;return index
}
fn set_predicate(input u64, context u64) SwiftSequenceResult {
	mut state:=unsafe {&SetCallback(context)};index:=set_callback_check(input,mut state)
	if state.throws {set_object_keep(state.api,state.error);return SwiftSequenceResult{error:state.error}}
	return SwiftSequenceResult{array:if index==1 {u64(1)}else{u64(0)}}
}
fn set_transform(input u64, context u64, output u64) u64 {
	mut state:=unsafe {&SetCallback(context)};index:=set_callback_check(input,mut state)
	if state.throws {set_object_keep(state.api,state.error);return state.error}
	unsafe {*(&u64(output))=if index & 1 == 0 {u64(0)}else{u64(index * 3)};*(&u8(output + 8))=if index & 1 == 0 {u8(1)}else{u8(0)}};return 0
}
fn set_iterator(api SetApi, table u64, metadata u64) [2]u64 {
	$if macos {if api.native {
		associate := unsafe {SetAssociate(C.dlsym(api.core,c'swift_getAssociatedTypeWitness'))};conf := unsafe {SetConformance(C.dlsym(api.core,c'swift_getAssociatedConformanceWitness'))};tl := u64(C.dlsym(api.core,c'$sSTTL'))
		iterator := associate(0,table,metadata,tl,u64(C.dlsym(api.core,c'$s8IteratorSTTl'))).metadata
		return [iterator,conf(table,metadata,iterator,tl,u64(C.dlsym(api.core,c'$sST8IteratorST_StTn')))]!
	}}
	return [read64(table + 24),read64(table + 8)]!
}
fn set_destroy(value u64, metadata u64) {destroy := unsafe {SwiftSequenceDestroy(voidptr(read64(read64(metadata - 8) + 8) & 0x0000ffffffffffff))};destroy(value,metadata)}
fn set_object(api SetApi) u64 {$if macos {if api.native {return u64(C.CFStringCreateMutable(unsafe {nil},0))}};return owned_string('Set owned Element')}
fn set_object_keep(api SetApi, owner u64) {$if macos {if api.native {C.CFRetain(voidptr(owner));return}};objc_retain(owner)}
fn set_object_drop(api SetApi, owner u64) {$if macos {if api.native {C.CFRelease(voidptr(owner));return}};objc_release(owner)}
fn set_object_refs(api SetApi, owner u64) i64 {$if macos {if api.native {return C.CFGetRetainCount(voidptr(owner))}};return obj_header(owner).refs}
fn set_value(api SetApi, destination u64, reference bool, value u64) {if reference {set_object_keep(api,value);unsafe {*(&u64(destination)) = 0;*(&u64(destination + 8)) = value | 0x5000000000000000}} else {unsafe {*(&u64(destination)) = value}}}
fn set_value_id(value u64, reference bool) u64 {return if reference {read64(value + 8) & 0x0000ffffffffffff} else {read64(value)}}
fn set_vwt(api SetApi, metadata u64, receiver u64) {
	vwt := read64(metadata - 8);size := read64(vwt + 64);assert size in [u64(8),40]!
	mut a := [8]u64{};mut b := [8]u64{};pa := u64(unsafe {&a[0]});pb := u64(unsafe {&b[0]})
	copy_value := unsafe {SwiftSequenceCopy(voidptr(read64(vwt + 16) & 0x0000ffffffffffff))};assign := unsafe {SwiftSequenceCopy(voidptr(read64(vwt + 24) & 0x0000ffffffffffff))};take := unsafe {SwiftSequenceCopy(voidptr(read64(vwt + 32) & 0x0000ffffffffffff))};assign_take := unsafe {SwiftSequenceCopy(voidptr(read64(vwt + 40) & 0x0000ffffffffffff))}
	copy_value(pa,receiver,metadata);copy_value(pb,receiver,metadata);assign(pa,pb,metadata);set_destroy(pb,metadata);take(pb,pa,metadata);copy_value(pa,receiver,metadata);assign_take(pa,pb,metadata);set_destroy(pa,metadata)
	get := unsafe {SwiftSequenceTag(voidptr(read64(vwt + 48) & 0x0000ffffffffffff))};store := unsafe {SwiftArraySequenceStore(voidptr(read64(vwt + 56) & 0x0000ffffffffffff))}
	for cases in [u32(1),126,127,65535,0x7fffffff,0xffffffff]! {for tag in [u32(1),cases]! {C.memset(voidptr(pa),0,64);store(pa,tag,cases,metadata);assert get(pa,cases,metadata)==tag};copy_value(pa,receiver,metadata);store(pa,0,cases,metadata);assert get(pa,cases,metadata)==0;set_destroy(pa,metadata)}
	if size > 24 {
		mut box := SwiftArrayAllocation{};mut release := SetDrop(swift_release)
		$if macos {if api.native {alloc := unsafe {SetBox(C.dlsym(api.core,c'swift_allocBox'))};box=alloc(metadata);release=unsafe {SetDrop(C.dlsym(api.core,c'swift_release'))}}}
		if !api.native {base := swift_set_base_checked(metadata,true) or {panic(err)};owner:=swift_heap_allocate(base + 576,56,7);box=SwiftArrayAllocation{owner:owner,bytes:owner + 16}}
		copy_value(box.bytes,receiver,metadata);a[0]=box.owner
		buffer_copy := unsafe {SwiftSequenceCopy(voidptr(read64(vwt) & 0x0000ffffffffffff))};assert buffer_copy(pb,pa,metadata)==box.bytes && b[0]==box.owner;release(a[0]);release(b[0])
	}
}
fn set_case(api SetApi, reference bool, count u64, guard u64, sparse bool) {
	mut eq := [api.code + 544,api.code + 160]!;mut hash := [api.code + if sparse {u64(576)}else{u64(512)},u64(unsafe {&eq[0]}),api.code + 128,api.code + 128,api.code + if sparse {u64(144)}else{u64(128)}]!;hp := u64(unsafe {&hash[0]})
	$if macos {if api.native {sign:=unsafe {SetSign(voidptr(api.code + 192))};eq[1]=sign(eq[1],(u64(unsafe {&eq[1]})) | (u64(38891) << 48));for slot,discriminator in {2:u64(619),3:15753,4:50202} {hash[slot]=sign(hash[slot],(hp + u64(slot * 8)) | (discriminator << 48))}}}
	metadata := api.access(0,api.element,hp).metadata;table := api.lookup(api.descriptor,metadata,0);iterator := set_iterator(api,table,metadata)
	assert read64(metadata + 16)==api.element && read64(metadata + 24)==hp && read64(read64(iterator[0] - 8) + 64)==40
	start := if sparse {u64(128)}else{u64(0)}
	owner := api.construct(i64(count + start),api.element,hp);mut receiver := owner;self := u64(unsafe {&receiver});stride := read64(read64(api.element - 8) + 72)
	mut objects := []u64{cap: int(count)}
	for i in u64(0) .. count {value := if reference {set_object(api)} else {u64(1000) + i};objects << value;bucket:=start + i;set_value(api,read64(owner + 48) + bucket * stride,reference,value);p:=owner + 56 + bucket / 64 * 8;unsafe {*(&u64(p)) = read64(p) | (u64(1) << (bucket & 63))}}
	if count != 0 {unsafe {*(&u64(owner + 16)) = count}}
	set_vwt(api,metadata,self)
	assert set_call(api,read64(table + 40),[metadata,table,0,0,0]!,self,guard)[0]==count
	mut member := [u64(0),0]!;mp:=u64(unsafe {&member[0]})
	for i in u64(0) .. count {if reference {member[0]=0;member[1]=objects[int(i)] | 0x5000000000000000}else{member[0]=objects[int(i)]};assert set_call(api,read64(table + 48),[mp,metadata,table,0,0]!,self,guard)[0]==1}
	member=[u64(0),0]!;assert set_call(api,read64(table + 48),[mp,metadata,table,0,0]!,self,guard)[0]==0
	mut result := [u64(0),0,0,0,0,0,0,0]!;output:=u64(unsafe {&result[0]});api.keep(owner);set_call(api,read64(table + 32),[metadata,table,0,0,0]!,self,output)
	assert result[0]==owner && result[1]==owner + 56 && result[3]==0;set_vwt(api,iterator[0],output)
	mut item := [u64(0),0,0]!;ip:=u64(unsafe {&item[0]});get:=unsafe {SwiftSequenceTag(voidptr(read64(read64(api.element - 8) + 48) & 0x0000ffffffffffff))}
	for value in objects {set_call(api,read64(iterator[1] + 16),[iterator[0],iterator[1],0,0,0]!,output,ip);assert get(ip,1,api.element)==0 && set_value_id(ip,reference)==value;set_destroy(ip,api.element)}
	for _ in 0 .. 3 {set_call(api,read64(iterator[1] + 16),[iterator[0],iterator[1],0,0,0]!,output,ip);assert get(ip,1,api.element)==1};set_destroy(output,iterator[0])
	// All six Sequence methods: contiguous copy consumes; copyContents returns
	// an exhausted owned iterator; noncontiguous storage never calls its body.
	api.keep(owner);array:=set_call(api,read64(table + 56),[metadata,table,0,0,0]!,self,guard)[0]
	assert read64(array + 16)==count
	for i,value in objects {assert set_value_id(array + 32 + u64(i) * stride,reference)==value};api.drop(array)
	bytes:=u64(C.calloc(usize(count + 1),usize(stride)));assert bytes!=0
	api.keep(owner);written:=set_call(api,read64(table + 64),[output,bytes,count,metadata,table]!,self,guard)[0];assert written==count
	for i,value in objects {assert set_value_id(bytes + u64(i) * stride,reference)==value;set_destroy(bytes + u64(i) * stride,api.element)}
	set_call(api,read64(iterator[1] + 16),[iterator[0],iterator[1],0,0,0]!,output,ip);assert get(ip,1,api.element)==1;set_destroy(output,iterator[0]);C.free(voidptr(bytes))
	result[0]=0x1234;set_call(api,read64(table + 72),[guard,guard,api.element,metadata,table]!,self,output);assert get(output,1,api.element)==1
	set_helpers(api,metadata,table,self,reference,objects,guard)
	if !api.native {
		assert api.lookup(read64(iterator[1]),iterator[0],guard)==iterator[1]
		mut copied:=[10]u64{};control:=api.descriptor + 16;ctor:=unsafe {SetLookup(voidptr(u64(i64(control + 4) + i64(i32(read32(control + 4))))))};ctor(u64(unsafe {&copied[0]}),metadata,guard);for i in 0 .. 10 {assert copied[i]==read64(table + u64(i * 8))}
		if _:=swift_set_table_checked(guard,false){assert false}
		mut invalid:=[owner | 0x8000000000000000,u64(0),0,0,0]!;if _:=swift_set_view_checked(metadata,u64(unsafe {&invalid[0]}),false){assert false}
		invalid[0]=owner;invalid[1]=guard;if _:=swift_set_next_checked(iterator[0],ip,u64(unsafe {&invalid[0]})){assert false}
	}
	api.drop(owner)
	if reference {for object in objects {assert set_object_refs(api,object)==1;set_object_drop(api,object)}}
}
fn set_helpers(api SetApi, metadata u64, table u64, receiver u64, reference bool, objects []u64, guard u64) {
	error_owner:=set_object(api)
	for compact in [false,true]! {for throws in [false,true]! {
		mut state:=SetCallback{api:api,reference:reference,expected:objects,error:error_owner,throws:throws}
		mut entry:=u64(0);mut closure:=api.code + if compact {u64(320)}else{u64(256)};mut int_type:=u64(0)
		$if macos {if api.native {entry=u64(C.dlsym(api.core,if compact {c'$sSTsE10compactMapySayqd__Gqd__Sg7ElementQzKXEKlF'}else{c'$sSTsE5first5where7ElementQzSgSbADKXE_tKF'}));sign:=unsafe {SetSign(voidptr(api.code + 192))};closure=sign(closure,if compact {u64(55683)}else{u64(8404)});int_type=u64(C.dlsym(api.core,c'$sSiN'))}}
		if !api.native {entry=swift_sequence_arena() + if compact {u64(0)}else{u64(256)};int_type=swift_integer_metadata()}
		mut output:=[u64(0x7171717171717171),0x7171717171717171,0x7171717171717171,0x7171717171717171]!
		p:=u64(unsafe {&output[0]});args:=if compact {[closure,u64(unsafe {&state}),metadata,int_type,table]!}else{[closure,u64(unsafe {&state}),metadata,table,u64(0)]!}
		capture:=set_call_throwing(api,entry,args,receiver,if compact {guard}else{p})
		if throws && objects.len!=0 {assert capture[2]==error_owner && state.calls==1 && output.all(it==0x7171717171717171);set_object_drop(api,error_owner)}
		else {
			assert capture[2]==0
			if compact {assert state.calls==objects.len && read64(capture[0] + 16)==u64(objects.len / 2),'native=${api.native} reference=${reference} count=${objects.len} calls=${state.calls} result=${read64(capture[0] + 16)}';for i in 0 .. objects.len / 2 {assert read64(capture[0] + 32 + u64(i * 8))==u64((i * 2 + 1) * 3)};api.drop(capture[0])}
			else {get:=unsafe {SwiftSequenceTag(voidptr(read64(read64(api.element - 8) + 48) & 0x0000ffffffffffff))};assert get(p,1,api.element)==if objects.len>1 {u32(0)}else{u32(1)};assert state.calls==if objects.len>1 {2}else{objects.len};if objects.len>1 {assert set_value_id(p,reference)==objects[1];set_destroy(p,api.element)}}
		}
	}}
	assert set_object_refs(api,error_owner)==1;set_object_drop(api,error_owner)
}
fn set_worker(element u64, hash u64) u64 {return swift_set_access(0,element,hash).metadata}
fn set_integer_hash_case(api SetApi, guard u64) {
	mut hash:=u64(0)
	$if macos {if api.native {hash=u64(C.dlsym(api.core,c'$sSiSHsWP'))}}
	if !api.native {hash=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sSiSHsWP') or {panic(err)}}
	metadata:=api.access(0,api.element,hash).metadata;table:=api.lookup(api.descriptor,metadata,0)
	owner:=api.construct(5,api.element,hash);mut self:=owner;receiver:=u64(unsafe {&self})
	values:=[-i64(0x7fffffffffffffff)-1,-1,0,1,i64(0x7fffffffffffffff)]!
	buckets:=u64(1) << unsafe {*(&u8(owner + 32))}
	for value in values {
		mut member:=u64(value);pointer:=u64(unsafe {&member})
		mut bucket:=set_call(api,read64(hash + 32),[read64(owner + 40),api.element,hash,0,0]!,pointer,guard)[0] & (buckets - 1)
		for read64(owner + 56) & (u64(1) << bucket)!=0 {bucket=(bucket + 1) & (buckets - 1)}
		unsafe {*(&u64(read64(owner + 48) + bucket * 8))=member;*(&u64(owner + 56))=read64(owner + 56) | (u64(1) << bucket);*(&u64(owner + 16))=read64(owner + 16) + 1}
	}
	for value in values {mut member:=u64(value);assert set_call(api,read64(table + 48),[u64(unsafe {&member}),metadata,table,0,0]!,receiver,guard)[0]==1}
	mut missing:=u64(42);assert set_call(api,read64(table + 48),[u64(unsafe {&missing}),metadata,table,0,0]!,receiver,guard)[0]==0
	api.drop(owner)
}
fn test_swift_set() {
	page:=usize(C.getpagesize());allocation:=C.mmap(unsafe {nil},page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0);assert allocation!=voidptr(-1);code:=u64(allocation);set_emit(code);C.__builtin___clear_cache(allocation,voidptr(code + 560));assert C.mprotect(allocation,page,C.PROT_READ | C.PROT_EXEC)==0
	protected:=C.mmap(unsafe {nil},page,C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0);assert protected!=voidptr(-1);guard:=u64(protected)
	$if macos {for reference in [false,true]! {api:=set_api(true,code,reference);for count in [u64(0),1,5,33,70]! {set_case(api,reference,count,guard,false)};set_case(api,reference,70,guard,true)};set_integer_hash_case(set_api(true,code,false),guard);println('IOS-SWIFT-SET-NATIVE: native storage, collision probing, nine Sequence requirements, 40-byte iterator/126 spare payload cases and shared boxes; twelve cases')}
	for _ in 0 .. 2 {
		objc_start();api:=set_api(false,code,false);int_hash:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sSiSHsWP') or {panic(err)}
		mut workers:=[]thread u64{};for _ in 0 .. 4 {workers << spawn set_worker(api.element,int_hash)};types:=workers.wait();for metadata in types {assert metadata==types[0]}
		set_integer_hash_case(api,guard)
		for reference in [false,true]! {typed:=set_api(false,code,reference);for count in [u64(0),1,5,33,70]! {set_case(typed,reference,count,guard,false)};set_case(typed,reference,70,guard,true)}
		assert ios_runtime.swift_heap.len==0 && ios_runtime.swift_arrays.len==0 && ios_runtime.swift_strings.len==0
		arena:=ios_runtime.swift_set_arena;bases:=ios_runtime.swift_set_metadata.keys();objc_stop();assert C.mprotect(voidptr(arena),page,C.PROT_READ)!=0;for base in bases {assert C.mprotect(voidptr(base),page,C.PROT_READ)!=0}
	}
	assert C.munmap(protected,page)==0 && C.munmap(allocation,page)==0
	println('IOS-SWIFT-SET: complete canonical Set Sequence/Iterator tables, native bitmap buckets across word boundaries, Hashable collisions, owned reference elements, copy/take/boxed witnesses, empty immortals, concurrent specialization and two drained/unmapped lifetimes')
}
