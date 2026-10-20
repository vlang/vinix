// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type PMQuery = fn (u64, u64, bool, bool) ObjProtocolDescription
type PMGet = fn (&char) u64
type PMAdd = fn (u64, u64, &char, bool, bool)
type PMAdopt = fn (u64, u64)
type PMRegister = fn (u64)
type PMList = fn (u64, bool, bool, &u32) u64
type PMProbe = fn (&u64, u64, &u64)
struct PMApi { native bool entry u64 objc voidptr foundation voidptr }
struct PMEntry { node int slot int name string types string }
fn pm_entries(long string) [10]PMEntry {
	return [PMEntry{0,0,'pmFlags','v16@0:8'}, PMEntry{0,1,'pmFlags','q16@0:8'}, PMEntry{0,2,'pmFlags','@16@0:8'}, PMEntry{0,3,'pmFlags','d16@0:8'}, PMEntry{0,0,'pmOverride','@16@0:8'}, PMEntry{1,0,'pmOverride','q16@0:8'}, PMEntry{2,0,'pmInherited','d16@0:8'}, PMEntry{3,0,'pmInherited','q16@0:8'}, PMEntry{3,2,'pmLong:',long}, PMEntry{0,3,'pm_π:','v24@0:8@16'}]!
}
fn pm_api(native bool) PMApi {
	if native {
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib',2); foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation',2)
		assert objc != unsafe { nil } && foundation != unsafe { nil }
		entry := u64(C.dlsym(objc,c'protocol_getMethodDescription')); assert entry != 0
		return PMApi{true,entry,objc,foundation}
	}
	return PMApi{entry: runtime_symbol('/usr/lib/libobjc.A.dylib','_protocol_getMethodDescription') or { panic(err) }}
}
fn pm_sel(api PMApi, name string) u64 {
	return if api.native { unsafe { PMGet(C.dlsym(api.objc,c'sel_registerName'))(&char(name.str)) } } else { objc_selector(unsafe { &char(name.str) }) }
}
fn pm_get(api PMApi, name string) u64 {
	return if api.native { unsafe { PMGet(C.dlsym(api.objc,c'objc_getProtocol'))(&char(name.str)) } } else { objc_get_protocol(unsafe { &char(name.str) }) }
}
fn pm_query(api PMApi, protocol u64, selector u64, slot int) ObjProtocolDescription { return unsafe { PMQuery(voidptr(api.entry))(protocol,selector,slot < 2,slot % 2 == 0) } }
fn pm_name(format int, node int) string { return 'VinixPM${format}Node${node}' }
fn pm_native(api PMApi, format int, long string) [4]u64 {
	mut values := [4]u64{}
	for node in [3,1,2,0]! {
		name := pm_name(format,node)
		p := unsafe { PMGet(C.dlsym(api.objc,c'objc_allocateProtocol'))(&char(name.str)) }; assert p != 0
		unsafe { name.free() }; values[node] = p
		for method in pm_entries(long) { if method.node == node { unsafe { PMAdd(C.dlsym(api.objc,c'protocol_addMethodDescription'))(p,pm_sel(api,method.name),&char(method.types.str),method.slot < 2,method.slot % 2 == 0) } } }
		for parent in if node == 0 { [1,2]! } else { [3,-1]! } { if parent >= 0 && node != 3 { unsafe { PMAdopt(C.dlsym(api.objc,c'protocol_addProtocol'))(p,values[parent]) } } }
		unsafe { PMRegister(C.dlsym(api.objc,c'objc_registerProtocol'))(p) }
	}
	return values
}
fn pm_case(api PMApi, protocol u64, name string, slot int, expected string, probe PMProbe, guard u64) u64 {
	selector := pm_sel(api,name); result := pm_query(api,protocol,selector,slot)
	assert result.name == selector && result.types != 0 && unsafe { (&char(result.types)).vstring() } == expected
	input := [protocol,selector,u64(slot < 2),u64(slot % 2 == 0),guard,guard,guard,guard,guard,guard,guard,guard,guard]!
	mut output := [6]u64{}; probe(unsafe { &input[0] },api.entry,unsafe { &output[0] })
	assert output[0] == selector && output[1] == result.types && output[4] == guard && output[5] == guard
	return result.types
}
fn pm_shared(api PMApi, values [4]u64, long string, probe PMProbe, guard u64) {
	for method in pm_entries(long) { pm_case(api,values[method.node],method.name,method.slot,method.types,probe,guard) }
	pm_case(api,values[0],'pmOverride',0,'@16@0:8',probe,guard)
	pm_case(api,values[0],'pmInherited',0,'q16@0:8',probe,guard) // First parent's ancestor beats the second parent's own method.
	pm_case(api,values[0],'pmLong:',2,long,probe,guard)
	for pair in [[u64(0),pm_sel(api,'pmFlags')]!,[values[0],u64(0)]!,[values[0],pm_sel(api,'pmMissing')]!]! { for slot in 0 .. 4 { result := pm_query(api,pair[0],pair[1],slot); assert result.name == 0 && result.types == 0 } }
}
fn pm_metadata(base u64, size u64) ObjMetadata {
	return ObjMetadata{image: macho.Image{segments: [macho.Segment{name:'__DATA',address:0x1000,filesize:size,size:size,prot:3,sections:[macho.Section{name:'__objc_protolist',address:0x1000,size:32},macho.Section{name:'__objc_protorefs',address:0x1020,size:32}]}]},layout:macho.Layout{base:0x1000,size:size},base:base}
}
fn pm_emit(base u64, format int, long string) {
	for node in 0 .. 4 {
		descriptor := base + 128 + u64(node*96); name := pm_name(format,node); name_at := base + 5000 + u64(node*128)
		C.memcpy(voidptr(name_at),name.str,usize(name.len+1)); unsafe { name.free(); *(&u64(base+u64(node*8)))=descriptor; *(&u64(base+32+u64(node*8)))=descriptor; *(&u64(descriptor+8))=name_at }
		write32(descriptor+64,96)
		if node != 3 { list := base+600+u64(node*32); unsafe { *(&u64(descriptor+16))=list; *(&u64(list))=if node==0 { u64(2) } else { u64(1) }; *(&u64(list+8))=base+128+u64(if node==0 {96}else{288}); if node==0 { *(&u64(list+16))=base+320 } } }
		for slot in 0 .. 4 { list:=base+1024+u64(node*1024+slot*192);unsafe { *(&u64(descriptor+24+u64(slot*8)))=list };write32(list,if format==0 {u32(24)}else if format==1 {u32(0x8000000c)}else{u32(0xc000000c)}) }
	}
	for index, method in pm_entries(long) {
		list:=base+1024+u64(method.node*1024+method.slot*192); count:=read32(list+4); entry:=list+8+u64(count)*if format==0 {u64(24)}else{u64(12)}
		name:=base+8192+u64(index*128); types:=base+32768+u64(index*2048)
		C.memcpy(voidptr(name),method.name.str,usize(method.name.len+1));C.memcpy(voidptr(types),method.types.str,usize(method.types.len+1))
		if format==0 {unsafe { *(&u64(entry))=name;*(&u64(entry+8))=types;*(&u64(entry+16))=~u64(0) }}
		else { cell:=base+7168+u64(index*8);unsafe {*(&u64(cell))=name};write32(entry,u32(i32(i64(if format==1 {cell}else{name})-i64(entry))));write32(entry+4,u32(i32(i64(types)-i64(entry+4))));write32(entry+8,0x80000000) }
		write32(list+4,count+1)
	}
	if format==0 {
		list:=base+1024+3*192;mut count:=read32(list+4)
		for index,name in ['pmNullType','pmEmptyType']! {at:=base+10000+u64(index*64);C.memcpy(voidptr(at),name.str,usize(name.len+1));entry:=list+8+u64(count)*24;unsafe{*(&u64(entry))=at;*(&u64(entry+8))=if index==0{u64(0)}else{base+10128}};count++}
		write32(list+4,count)
	}
}
fn pm_null_types(api PMApi, protocol u64) {
	null_result:=pm_query(api,protocol,pm_sel(api,'pmNullType'),3);empty_result:=pm_query(api,protocol,pm_sel(api,'pmEmptyType'),3)
	assert null_result.name==pm_sel(api,'pmNullType')&&null_result.types==0
	assert empty_result.name==pm_sel(api,'pmEmptyType')&&empty_result.types!=0&&unsafe{*(&u8(empty_result.types))}==0
}
fn pm_reject(m ObjMetadata, protocol_name string) {
	before:=ios_runtime.protocols.len;aliases:=ios_runtime.protocol_aliases.len;selectors:=ios_runtime.selectors.len
	if _:=m.protocols_register(){assert false}
	assert ios_runtime.protocols.len==before&&ios_runtime.protocol_aliases.len==aliases&&ios_runtime.selectors.len==selectors&&objc_get_protocol(unsafe{&char(protocol_name.str)})==0
}
fn pm_malformed(m ObjMetadata, format int) {
	base:=m.base; name:=pm_name(format,0);defer{unsafe{name.free()}}
	list:=base+1024+3072+2*192; old_flags:=read32(list);old_count:=read32(list+4)
	write32(list,16);pm_reject(m,name);write32(list,old_flags)
	write32(list+4,4097);pm_reject(m,name);write32(list+4,old_count)
	field:=base+416+40;old_list:=read64(field);unsafe{*(&u64(field))=base+m.layout.size-4};pm_reject(m,name);unsafe{*(&u64(field))=old_list}
	entry:=list+8
	if format==0 {old:=read64(entry+8);unsafe{*(&u64(entry+8))=base+m.layout.size};pm_reject(m,name);unsafe{*(&u64(entry+8))=old}}
	else {old:=read32(entry+4);write32(entry+4,0x7fffffff);pm_reject(m,name);write32(entry+4,old)}
	// A late cyclic root also rejects before any earlier root is published.
	unsafe{*(&u64(base+416+16))=base+696;*(&u64(base+696))=1;*(&u64(base+704))=base+128};pm_reject(m,name);unsafe{*(&u64(base+416+16))=0}
}
fn pm_reader(api PMApi, protocol u64, selector u64, types u64) {
	for _ in 0 .. 512 { result:=pm_query(api,protocol,selector,0);assert result.name==selector&&result.types==types&&unsafe{(&char(result.types)).vstring()}=='q16@0:8' }
}
__global pm_teardown_protocol = u64(0)
__global pm_teardown_selector = u64(0)
__global pm_teardown_types = u64(0)
__global pm_teardown_count = 0
fn pm_teardown(object u64, selector u64) { result:=objc_protocol_method_description(pm_teardown_protocol,pm_teardown_selector,true,true);assert result.name==pm_teardown_selector&&result.types==pm_teardown_types;assert unsafe{(&char(result.types)).vstring()}=='q16@0:8';pm_teardown_count++ }
fn pm_builtins(native PMApi, api PMApi) {
	for text in ['NSObject','NSCopying','NSMutableCopying','NSCoding','NSSecureCoding','NSFastEnumeration']! {
		native_p:=pm_get(native,text);p:=pm_get(api,text);assert native_p!=0&&p!=0
		for slot in 0 .. 4 {mut count:=u32(0);list:=unsafe{PMList(C.dlsym(native.objc,c'protocol_copyMethodDescriptionList'))(native_p,slot<2,slot%2==0,&count)}
			info:=ios_runtime.protocols[p] or {panic('builtin')};assert info.descriptions[slot].len==int(count)
			for i in u32(0)..count {sel:=read64(list+u64(i)*16);types:=read64(list+u64(i)*16+8);name:=unsafe{(&char(sel)).vstring()};result:=pm_query(api,p,pm_sel(api,name),slot);assert result.name!=0&&result.types!=0&&unsafe{(&char(result.types)).vstring()}==unsafe{(&char(types)).vstring()}}
			C.free(voidptr(list))
		}
	}
	result:=pm_query(api,pm_get(api,'NSSecureCoding'),pm_sel(api,'initWithCoder:'),0);assert result.types!=0&&unsafe{(&char(result.types)).vstring()}=='@24@0:8@16'
}
fn pm_limits(base u64, size u64) {
	m:=pm_metadata(base,size);end:=base+size;list:=base+128
	write32(list,24);write32(list+4,1);unsafe{*(&u64(list+8))=end-1024;*(&u64(list+16))=end-65536}
	C.memset(voidptr(end-65536),`x`,65536);unsafe{*(&u8(end-1))=0}
	// Name and type end at the final readable byte; their limits differ.
	assert m.protocol_method_count(list) or {panic(err)}==1
	method:=m.protocol_method_at(list,0) or {panic(err)};assert method.name.len==1023&&method.types.len==65535
	unsafe{*(&u8(end-1))=`x`};if _:=m.protocol_method_at(list,0){assert false}
	unsafe{*(&u64(list+8))=base+1000};C.memcpy(voidptr(base+1000),c'pmLimit',8)
	if _:=m.protocol_method_at(list,0){assert false} // 65536 type bytes, no terminator.
	unsafe{*(&u8(end-1))=0;*(&u64(list+16))=0};method_null:=m.protocol_method_at(list,0) or {panic(err)};assert !method_null.has_types
	unsafe{*(&u64(list+16))=end-1};method_empty:=m.protocol_method_at(list,0) or {panic(err)};assert method_empty.has_types&&method_empty.types.len==0
	write32(end-8,24);write32(end-4,1);if _:=m.protocol_method_count(end-8){assert false}
}
fn test_protocol_method() {
	page:=usize(C.getpagesize());size:=u64(page)*32
	code:=u64(C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+100));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0&&C.mprotect(voidptr(code+u64(page)),page,C.PROT_NONE)==0
	probe:=unsafe{PMProbe(voidptr(code))};guard:=code+u64(page)
	padding:='x'.repeat(1600);long:='{'+padding+'=i}';unsafe{padding.free()}
	mut native:=PMApi{};mut native_values:=[3][4]u64{}
	$if macos {native=pm_api(true);for format in 0..3{native_values[format]=pm_native(native,format,long);pm_shared(native,native_values[format],long,probe,guard)};println('NATIVE-PROTOCOL-METHOD: four flag combinations, own/ordered recursive parent lookup, diamond precedence, Unicode/long encodings, nil/missing results and x0/x1 ABI compared')}
	for _ in 0..2 {
		objc_start();api:=pm_api(false);assert api.entry==u64(unsafe{voidptr(objc_protocol_method_description)})
		$if macos {pm_builtins(native,api)}
		for library in ['/usr/lib/libSystem.B.dylib','/usr/lib/libc++.1.dylib','/System/Library/Frameworks/Foundation.framework/Foundation']!{if _:=runtime_symbol(library,'_protocol_getMethodDescription'){assert false}}
		mut bases:=[4]u64{}
		for index in 0..4 {base:=u64(C.mmap(unsafe{nil},usize(size)+page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1);bases[index]=base;assert C.mprotect(voidptr(base+size),page,C.PROT_NONE)==0}
		pm_limits(bases[3],size)
		for format in 0..3 {
			base:=bases[format];pm_emit(base,format,long);m:=pm_metadata(base,size);pm_malformed(m,format);m.protocols_register() or {panic(err)}
			mut values:=[4]u64{};for node in 0..4{name:=pm_name(format,node);values[node]=pm_get(api,name);unsafe{name.free()};assert values[node]!=0&&read64(base+32+u64(node*8))==values[node]}
			pm_shared(api,values,long,probe,guard)
			if format==0 {pm_null_types(api,values[0])}
			selector:=pm_sel(api,'pmInherited');stable:=pm_case(api,values[0],'pmInherited',0,'q16@0:8',probe,guard)
			// Republishing an alias cannot replace a previously returned type.
			list:=base+1024+3072;types:=if format==0{read64(list+16)}else{u64(i64(list+12)+i64(i32(read32(list+12))))};unsafe{*(&u8(types))=`d`};m.protocols_register() or {panic(err)}
			C.memcpy(voidptr(base+800),voidptr(base+416),96);mut seen:=map[u64]u8{};m.protocol_validate(base+800,0,mut seen) or {panic(err)};assert m.protocol_publish(base+800) or {panic(err)}==values[3];unsafe{seen.free()}
			assert pm_query(api,base+128,selector,0).types==stable
			assert C.mprotect(voidptr(base),usize(size),C.PROT_NONE)==0
			pm_shared(api,values,long,probe,guard)
			if format==0 {pm_null_types(api,values[0])}
			mut readers:=[]thread{};for _ in 0..8{readers<<spawn pm_reader(api,values[0],selector,stable)};readers.wait();unsafe{readers.free()}
			for invalid in [u64(1),~u64(0),guard]!{result:=pm_query(api,invalid,selector,0);assert result.name==0&&result.types==0;missing:=pm_query(api,values[0],invalid,0);assert missing.name==0&&missing.types==0}
			pm_teardown_protocol=values[0];pm_teardown_selector=selector;pm_teardown_types=stable
		}
		// A malformed canonical graph cannot turn a miss into an infinite walk.
		mut leaf:=ios_runtime.protocols[pm_teardown_protocol] or {panic('leaf')};leaf.parents<<pm_teardown_protocol
		missing:=pm_query(api,pm_teardown_protocol,pm_sel(api,'pmMissing'),0);assert missing.name==0&&missing.types==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixPMTeardown',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(pm_teardown)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls));before:=pm_teardown_count
		objc_stop();assert pm_teardown_count==before+1&&ios_runtime.live==0&&ios_runtime.objects.len==0&&ios_runtime.protocols.len==0&&ios_runtime.protocol_aliases.len==0
		retired:=pm_query(api,pm_teardown_protocol,pm_teardown_selector,0);assert retired.name==0&&retired.types==0
		for base in bases{assert C.munmap(voidptr(base),usize(size)+page)==0}
	}
	$if macos {assert C.dlclose(native.foundation)==0&&C.dlclose(native.objc)==0}
	unsafe{long.free()};assert C.munmap(voidptr(code),page*2)==0
	println('IOS-PROTOCOL-METHOD: four method lists and built-in declarations, big/direct-relative/indirect-relative metadata, first declaration and ordered DFS inheritance, canonical aliases, copied types after protected source retirement, guarded limits and malformed atomic rejection, x0/x1 ABI with protected unused inputs, eight readers and two drained runtimes with teardown callbacks; no per-lookup allocation')
}
