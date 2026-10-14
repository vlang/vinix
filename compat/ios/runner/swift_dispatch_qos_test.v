// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
$if macos {
	#include <mach/mach.h>
}
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.mincore(voidptr,usize,&u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32,&u64,&u64,i32,&i32,&u32,&u32) i32
fn C.mach_port_deallocate(u32,u32) i32
type QoSAccess=fn (u64) SwiftAssociatedMetadata
type QoSAccessProbe=fn (u64,u64,&u64)
type QoSGetterProbe=fn (u64,u64,u64,&u64)
type QoSCopy=fn (u64,u64,u64) u64
type QoSDestroy=fn (u64,u64)
type QoSGetTag=fn (u64,u32,u64) u32
type QoSStoreTag=fn (u64,u32,u32,u64)
type QoSLookup=fn (u64,u64,u64,u64,u64) u64
fn qos_relative(p u64) u64 {d:=i32(read32(p));return if d==0 {u64(0)} else {u64(i64(p)+d)}}
fn qos_name(p u64) string {return unsafe {(&char(p)).vstring()}}
fn qos_protection(address u64,length u64,executable bool) {
	$if macos {
		mut start:=address;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object:=u32(0);task:=C.mach_task_self()
		assert C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe {&info[0]},&count,&object)==0
		assert start<=address&&address+length<=start+size&&info[0]==(C.PROT_READ|if executable {C.PROT_EXEC} else {0})
		if object!=0 {assert C.mach_port_deallocate(task,object)==0}
	} $else {
		mut found:=false
		for line in (os.read_file('/proc/self/maps') or {panic(err)}).split_into_lines() {
			fields:=line.fields();if fields.len<2 {continue};range:=fields[0].split('-');if range.len!=2 {continue}
			start:=strconv.parse_uint(range[0],16,64) or {panic(err)};end:=strconv.parse_uint(range[1],16,64) or {panic(err)}
			if address>=start&&address<end {assert address+length<=end&&fields[1]==if executable {'r-xp'} else {'r--p'};found=true;break}
		};assert found
	}
}
fn qos_layout(entry u64,descriptor u64,probe QoSAccessProbe,native bool) u64 {
	accessor:=unsafe {QoSAccess(voidptr(entry))};metadata:=accessor(0).metadata;witness:=read64(metadata-8)
	assert metadata!=0&&read64(metadata)==0x200&&read64(metadata+8)==descriptor
	assert read32(metadata+16)==0&&read32(metadata+20)==8
	assert read64(witness+64)==16&&read64(witness+72)==16&&read32(witness+80)==0x02000007&&read32(witness+84)==250
	assert read32(descriptor)&0xffff==0x51&&read32(descriptor+20)==2&&read32(descriptor+24)==2
	assert qos_name(qos_relative(descriptor+8))=='DispatchQoS'&&qos_name(qos_relative(qos_relative(descriptor+4)+8))=='Dispatch'
	if !native {assert qos_relative(descriptor+16)==0;qos_protection(entry,24,true);qos_protection(metadata-8,196,false)}
	for candidate in [entry,qos_relative(descriptor+12)]! {for request in [u64(0),0x3f,0xff,0x100,0x13f,0x1ff,~u64(0)]! {
		mut result:=[u64(0xcafe),0,0,0,0,0xbeef]!
		probe(request,candidate,unsafe {&result[1]});assert result==[u64(0xcafe),metadata,0,0x5020,0x5021,0xbeef]!
	}}
	return metadata
}
fn qos_getter(entry u64,probe QoSGetterProbe,guard u64) {
	for seed in [u64(0),0x1122334455667788,~u64(0)]! {
		mut value:=[u64(0xcafe),seed,seed,0xbeef]!;mut contexts:=[u64(0xcafe),0,0,0xbeef]!
		probe(entry,u64(unsafe {&value[1]}),guard,unsafe {&contexts[1]})
		assert value==[u64(0xcafe),(seed&~u64(255))|5,0,0xbeef]!
		assert contexts==[u64(0xcafe),guard,0x5021,0xbeef]!
	}
}
fn qos_values(metadata u64) {
	witness:=read64(metadata-8);page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe {nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1)
	guard:=base+u64(page);source:=guard-16;unsafe {*(&u64(source))=0x1122334455667705;*(&u64(source+8))=0xfedcba9876543210}
	assert C.mprotect(voidptr(base),page,C.PROT_READ)==0&&C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
	for slot in [u64(0),2,3,4,5]! {
		transfer:=unsafe {QoSCopy(voidptr(read64(witness+slot*8)))};mut destination:=[u64(0xcafe),0,0,0xbeef]!
		assert transfer(u64(unsafe {&destination[1]}),source,guard)==u64(unsafe {&destination[1]})&&destination==[u64(0xcafe),0x1122334455667705,0xfedcba9876543210,0xbeef]!
		assert transfer(u64(unsafe {&destination[1]}),u64(unsafe {&destination[1]}),guard)==u64(unsafe {&destination[1]})&&destination==[u64(0xcafe),0x1122334455667705,0xfedcba9876543210,0xbeef]!
		for reverse in [false,true]! {
			mut overlap:=[u64(0xcafe),0x11,0x22,0x33,0xbeef]!
			d:=u64(unsafe {&overlap[if reverse {1} else {2}]});s:=u64(unsafe {&overlap[if reverse {2} else {1}]})
			assert transfer(d,s,guard)==d&&overlap==if reverse {[u64(0xcafe),0x22,0x33,0x33,0xbeef]!} else {[u64(0xcafe),0x11,0x11,0x22,0xbeef]!}
		}
	}
	destroy:=unsafe {QoSDestroy(voidptr(read64(witness+8)))};destroy(guard,guard);destroy(source,guard)
	get_tag:=unsafe {QoSGetTag(voidptr(read64(witness+48)))};store_tag:=unsafe {QoSStoreTag(voidptr(read64(witness+56)))}
	assert get_tag(guard,0,guard)==0;store_tag(guard,0,0,guard)
	assert get_tag(source,250,guard)==0 // No access to byte16 for these populations.
	for raw in 0..256 {mut value:=[u64(raw)|0x1122334455667700,u64(0),0]!;assert get_tag(u64(unsafe {&value[0]}),250,guard)==if raw<6 {u32(0)} else {u32(raw-5)}}
	for cases in [u32(0),1,249,250,251,256,65536,0xffffffff]! {for tag in [u32(0),1,249,250,251,252,0xffffff04,0xfffffffe,0xffffffff]! {
		first:=u64(0x8877665544332205);second:=u64(0xfedcba9876543210);extra:=u64(0x11223344556677aa)
		mut value:=[u64(0xcafe),first,second,extra,0xbeef]!;p:=u64(unsafe {&value[1]});store_tag(p,tag,cases,guard)
		expected_first:=if tag>250 {u64(tag-251)} else if tag==0 {first} else {(first&~u64(255))|u64(u8(tag+5))}
		expected_second:=if tag>250 {u64(0)} else {second}
		expected_extra:=if cases>=251 {(extra&~u64(255))|if tag>250 {u64(1)} else {u64(0)}} else {extra}
		assert value==[u64(0xcafe),expected_first,expected_second,expected_extra,0xbeef]!
		assert get_tag(p,cases,guard)==if cases==0 {u32(0)} else if cases>=251&&expected_extra&255!=0 {u32(expected_first)+u32(251)} else if expected_first&255<6 {u32(0)} else {u32((expected_first&255)-5)}
	}}
	mut wrapping:=[u64(0xffffffff),0,1]!;assert get_tag(u64(unsafe {&wrapping[0]}),251,guard)==250
	assert C.munmap(voidptr(base),page*2)==0
}
fn qos_symbolic(lookup QoSLookup,descriptor u64,metadata u64) {
	page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe {nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1);name:=base+32;slot:=base+64
	unsafe {*(&u8(name))=2;*(&u64(slot))=descriptor};delta:=u32(i32(i64(slot)-i64(name+1)))
	for i in u64(0)..4 {unsafe {*(&u8(name+1+i))=u8(delta>>(i*8))}};assert C.mprotect(voidptr(base),page,C.PROT_READ)==0
	for request in [u64(0),0xff,0x100,0x1ff]! {for _ in 0..32 {assert lookup(request,name,5,0,0)==metadata}}
	assert C.munmap(voidptr(base),page)==0
}
fn qos_worker(kind int) u64 {
	library:='/usr/lib/swift/libswiftDispatch.dylib'
	first:=['_$s8Dispatch0A3QoSV11unspecifiedACvgZ','_$s8Dispatch0A3QoSVMa','_$s8Dispatch0A3QoSVMn','_$s8Dispatch0A13WorkItemFlagsVMa']![kind]
	runtime_symbol(library,first) or {panic(err)}
	mut entry:=u64(0)
	for _ in 0..256 {
		entry=runtime_symbol(library,'_$s8Dispatch0A3QoSVMa') or {panic(err)}
		descriptor:=runtime_symbol(library,'_$s8Dispatch0A3QoSVMn') or {panic(err)};accessor:=unsafe {QoSAccess(voidptr(entry))}
		assert read64(accessor(0xff).metadata+8)==descriptor
	}
	return entry
}
fn test_swift_dispatch_qos() {
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe {nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe {nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0203f3,0xaa0103f0,0xd28a0414,0xd28a0435,0xd63f0200,0xa9000660,0xa9015674,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! {write32(code+u64(i*4),op)}
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0303f3,0xaa0003f0,0xaa0103e8,0xaa0203f4,0xaa0203e0,0xaa0203e1,0xaa0203e3,0xd28a0435,0xd63f0200,0xa9005674,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! {write32(code+128+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+196));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	access_probe:=unsafe {QoSAccessProbe(voidptr(code))};getter_probe:=unsafe {QoSGetterProbe(voidptr(code+128))}
	$if macos {
		lib:=C.dlopen(c'/usr/lib/swift/libswiftDispatch.dylib',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert lib!=unsafe {nil}&&core!=unsafe {nil}
		entry:=u64(C.dlsym(lib,c'$s8Dispatch0A3QoSVMa'));descriptor:=u64(C.dlsym(lib,c'$s8Dispatch0A3QoSVMn'));getter:=u64(C.dlsym(lib,c'$s8Dispatch0A3QoSV11unspecifiedACvgZ'));assert entry!=0&&descriptor!=0&&getter!=0
		metadata:=qos_layout(entry,descriptor,access_probe,true);qos_getter(getter,getter_probe,guard);qos_values(metadata)
		lookup:=unsafe {QoSLookup(C.dlsym(core,c'swift_getTypeByMangledNameInContextInMetadataState'))};qos_symbolic(lookup,descriptor,metadata)
		println('IOS-DISPATCH-QOS-NATIVE: indirect unspecified tag5/priority0 with untouched padding, complete nominal POD16 metadata/field offsets/250 extra inhabitants, all copy/take/assignment/overlap witnesses, no-op destruction, both optional populations/UInt32 wrapping, protected unused inputs and x20/x21 preservation')
	}
	if _:=swift_dispatch_flags_arena_checked() {assert false}
	for _ in 0..2 {
		objc_start();for unknown in ['_$s8Dispatch0A3QoSVN','_$s8Dispatch0A3QoSVSQsMc','_$s8Dispatch0A3QoSV10backgroundACvgZ']! {if _:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib',unknown) {assert false}}
		assert ios_runtime.swift_dispatch_flags_arena==0;mut workers:=[]thread u64{}
		for i in 0..8 {workers<<spawn qos_worker(i%4)};entries:=workers.wait();entry:=entries[0];for candidate in entries {assert candidate==entry}
		descriptor:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib','_$s8Dispatch0A3QoSVMn') or {panic(err)};getter:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib','_$s8Dispatch0A3QoSV11unspecifiedACvgZ') or {panic(err)}
		metadata:=qos_layout(entry,descriptor,access_probe,false);qos_getter(getter,getter_probe,guard);qos_values(metadata);qos_protection(getter,32,true)
		lookup:=unsafe {QoSLookup(voidptr(swift_mangled_state_lookup))};qos_symbolic(lookup,descriptor,metadata)
		flags_entry:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib','_$s8Dispatch0A13WorkItemFlagsVMa') or {panic(err)};flags_access:=unsafe {QoSAccess(voidptr(flags_entry))}
		assert metadata!=flags_access(0).metadata&&metadata!=swift_integer_metadata()&&metadata!=swift_string_metadata()
		if _:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$s8Dispatch0A3QoSVMa') {assert false}
		allocation:=swift_array_allocate(2,metadata);unsafe {*(&u64(allocation.bytes))=5;*(&u64(allocation.bytes+8))=0;*(&u64(allocation.bytes+16))=2;*(&u64(allocation.bytes+24))=u64(-15)}
		assert ios_runtime.swift_arrays[allocation.owner].stride==16&&ios_runtime.swift_arrays[allocation.owner].destroy==0;swift_bridge_release(allocation.owner)
		assert ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		base:=ios_runtime.swift_dispatch_flags_arena;objc_stop();assert ios_runtime.swift_dispatch_flags_arena==0&&ios_runtime.swift_dispatch_flags_retired
		$if macos {assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1} $else {mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe {&residency[0]})==-1}
		if _:=swift_dispatch_flags_arena_checked() {assert false}
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0
	println('IOS-DISPATCH-QOS: exact Dispatch-only getter/Ma/Mn, complete distinct POD16 nominal identity and packed offsets, exact padding/extra-inhabitant witnesses, symbolic metadata reuse and typed Array ownership, shared sealed arena/eight-worker publication, rejected unsupported exports/lifetimes and two unmapped teardowns')
}
