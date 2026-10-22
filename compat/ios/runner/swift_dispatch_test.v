// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv
$if macos {
	#include <mach/mach.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32
type DispatchFlagsAccess = fn (u64) SwiftAssociatedMetadata
type DispatchFlagsProbe = fn (u64, u64, &u64)
type DispatchFlagsCopy = fn (u64, u64, u64) u64
type DispatchFlagsDestroy = fn (u64, u64)
type DispatchFlagsGetTag = fn (u64, u32, u64) u32
type DispatchFlagsStoreTag = fn (u64, u32, u32, u64)
type DispatchFlagsLookup = fn (u64, u64, u64, u64, u64) u64
type DispatchCaseLoad = fn (u64, u64, u64, &u64)
type DispatchCaseInject = fn (u64, u32, u64)
type DispatchCaseTag = fn (u64, u64) u32

const dispatch_inherit_case_symbol = '_$sSo17OS_dispatch_queueC8DispatchE20AutoreleaseFrequencyO7inherityA2EmFWC'
const dispatch_autorelease_symbol = '_$sSo17OS_dispatch_queueC8DispatchE20AutoreleaseFrequencyOMa'

fn dispatch_case_load(entry u64, probe DispatchCaseLoad, protected u64) {
	mut output := [u32(0xcafe), 0xdeadbeef, 0xbeef]!
	mut observations := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	destination := u64(unsafe { &output[1] })
	probe(entry, destination, protected, unsafe { &observations[1] })
	assert output == [u32(0xcafe), 0, 0xbeef]!
	assert observations == [u64(0xcafe), entry, destination, protected, 0x5021, 0xbeef]!
}

fn dispatch_case_worker(entry u64, probe DispatchCaseLoad, protected u64) {
	for _ in 0 .. 128 { dispatch_case_load(entry, probe, protected) }
}

fn dispatch_case_spans(entry u64, probe DispatchCaseLoad) {
	assert entry != 0 && entry % 4 == 0 && read32(entry) == 0
	page := usize(C.getpagesize())
	source := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	destination := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert source != u64(-1) && destination != u64(-1)
	assert C.mprotect(voidptr(destination + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	for source_end in [false, true]! {
		assert C.mprotect(voidptr(source + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
		input := source + u64(page) + if source_end { u64(page) - 4 } else { u64(0) }
		write32(input, read32(entry))
		assert C.mprotect(voidptr(source + u64(page)), page, C.PROT_READ) == 0
		dispatch_case_load(input, probe, source)
		for output_end in [false, true]! {
			output := destination + u64(page) + if output_end { u64(page) - 4 } else { u64(0) }
			write32(output, 0xdeadbeef)
			mut observations := [4]u64{}
			probe(input, output, source, unsafe { &observations[0] })
			assert read32(output) == 0 && observations == [input, output, source, u64(0x5021)]!
		}
	}
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn dispatch_case_worker(entry, probe, source) }
	workers.wait()
	assert C.munmap(voidptr(source), page * 3) == 0 && C.munmap(voidptr(destination), page * 3) == 0
}

fn dispatch_flags_relative(p u64) u64 { d:=i32(read32(p)); return if d==0 {u64(0)} else {u64(i64(p)+d)} }
fn dispatch_flags_name(p u64) string { return unsafe {(&char(p)).vstring()} }

fn dispatch_flags_protection(address u64, length u64, executable bool) {
	$if macos {
		mut start:=address; mut size:=u64(0); mut info:=[16]i32{}
		mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64); mut object:=u32(0)
		task:=C.mach_task_self()
		assert C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe {&info[0]},&count,&object)==0
		assert start<=address && address+length<=start+size
		assert info[0]==(C.PROT_READ|if executable {C.PROT_EXEC} else {0})
		if object!=0 {assert C.mach_port_deallocate(task,object)==0}
	} $else {
		mut found:=false
		for line in (os.read_file('/proc/self/maps') or {panic(err)}).split_into_lines() {
			fields:=line.fields();if fields.len<2 {continue}; range:=fields[0].split('-');if range.len!=2 {continue}
			start:=strconv.parse_uint(range[0],16,64) or {panic(err)};end:=strconv.parse_uint(range[1],16,64) or {panic(err)}
			if address>=start && address<end {assert address+length<=end && fields[1]==if executable {'r-xp'} else {'r--p'};found=true;break}
		}
		assert found
	}
}

fn dispatch_flags_layout(entry u64, descriptor u64, probe DispatchFlagsProbe, native bool, attributes bool) u64 {
	access:=unsafe {DispatchFlagsAccess(voidptr(entry))}; metadata:=access(0).metadata
	assert metadata!=0 && read64(metadata)==0x200 && read64(metadata+8)==descriptor && read64(metadata+16)==0
	witness:=read64(metadata-8)
	assert read64(witness+64)==8 && read64(witness+72)==8 && read32(witness+80)==0x02000007 && read32(witness+84)==0
	assert read32(descriptor)&0xffff==0x51 && read32(descriptor+20)==1 && read32(descriptor+24)==2
	assert dispatch_flags_name(dispatch_flags_relative(descriptor+8))==if attributes {'Attributes'} else {'DispatchWorkItemFlags'}
	mut parent:=dispatch_flags_relative(descriptor+4)
	if attributes {
		assert read32(parent)==0x41
		assert dispatch_flags_name(dispatch_flags_relative(parent+8))=='So17OS_dispatch_queueC'
		parent=dispatch_flags_relative(parent+4)
	}
	assert read32(parent)==0 && read32(parent+4)==0
	assert dispatch_flags_name(dispatch_flags_relative(parent+8))=='Dispatch'
	if !native {
		assert dispatch_flags_relative(descriptor+16)==0
		dispatch_flags_protection(entry,24,true); dispatch_flags_protection(metadata-8,if attributes {u64(160)} else {u64(240)},false)
	}
	for accessor in [entry,dispatch_flags_relative(descriptor+12)]! {
		for request in [u64(0),0x3f,0xff,0x100,0x13f,0x1ff,~u64(0)]! {
			mut words:=[u64(0x1234),0,0,0,0,0x5678]!
			probe(request,accessor,unsafe {&words[1]})
			assert words==[u64(0x1234),metadata,0,0x5020,0x5021,0x5678]!
		}
	}
	return metadata
}

fn dispatch_flags_values(metadata u64) {
	witness:=read64(metadata-8); page:=usize(C.getpagesize())
	base:=u64(C.mmap(unsafe {nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)); assert base!=u64(-1)
	guard:=base+u64(page); source:=guard-8
	unsafe {*(&u64(source))=0xfedcba9876543210}
	assert C.mprotect(voidptr(base),page,C.PROT_READ)==0 && C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
	for slot in [u64(0),2,3,4,5]! {
		transfer:=unsafe {DispatchFlagsCopy(voidptr(read64(witness+slot*8)))}
		mut words:=[u64(0x1234),0,0x5678]!
		assert transfer(u64(unsafe {&words[1]}),source,guard)==u64(unsafe {&words[1]})
		assert words==[u64(0x1234),0xfedcba9876543210,0x5678]!
		for bits in [u64(0),1,2,4,6,0x80000000,0xffffffff,0x100000000,0x8000000000000000,~u64(0)]! {
			mut value:=bits
			assert transfer(u64(unsafe {&words[1]}),u64(unsafe {&value}),metadata)==u64(unsafe {&words[1]})
			assert words==[u64(0x1234),bits,0x5678]! && value==bits
			assert transfer(u64(unsafe {&words[1]}),u64(unsafe {&words[1]}),metadata)==u64(unsafe {&words[1]})
			assert words==[u64(0x1234),bits,0x5678]!
		}
	}
	destroy:=unsafe {DispatchFlagsDestroy(voidptr(read64(witness+8)))}
	destroy(guard,guard); destroy(source,guard) // No payload/metadata reads or writes.
	get_tag:=unsafe {DispatchFlagsGetTag(voidptr(read64(witness+48)))}
	store_tag:=unsafe {DispatchFlagsStoreTag(voidptr(read64(witness+56)))}
	assert get_tag(guard,0,guard)==0; store_tag(guard,0,0,guard)
	assert get_tag(source,0,guard)==0 // Exact eight-byte span; no tag byte exists.
	for cases in [u32(0),1,17,0x7fffffff,0x80000000,0xffffffff]! {
		for tag in [u32(0),1,17,0x7fffffff,0xfffffffe,0xffffffff]! {
			payload_seed:=u64(0xdeadbeef87654321); tag_seed:=u64(0x88776655443322aa)
			mut words:=[u64(0x1234),payload_seed,tag_seed,0x5678]!
			value:=u64(unsafe {&words[1]}); store_tag(value,tag,cases,guard)
			assert words[0]==0x1234 && words[3]==0x5678
			assert words[1]==if tag==0 {payload_seed} else {u64(tag-1)}
			assert words[2]==if cases==0 {tag_seed} else {(tag_seed & ~u64(255)) | if tag==0 {u64(0)} else {u64(1)}}
			assert get_tag(value,cases,guard)==if cases==0 {u32(0)} else {tag}
		}
	}
	mut raw:=[u64(0xffffffff),0xff]!
	assert get_tag(u64(unsafe {&raw[0]}),1,guard)==0 // Native UInt32 wrapping increment.
	assert C.munmap(voidptr(base),page*2)==0
}

fn dispatch_flags_symbolic(lookup DispatchFlagsLookup, descriptor u64, metadata u64) {
	page:=usize(C.getpagesize()); base:=u64(C.mmap(unsafe {nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)); assert base!=u64(-1)
	name:=base+32; slot:=base+64
	unsafe {*(&u8(name))=2; *(&u64(slot))=descriptor}
	delta:=u32(i32(i64(slot)-i64(name+1)))
	for i in u64(0)..4 {unsafe {*(&u8(name+1+i))=u8(delta>>(i*8))}}
	assert C.mprotect(voidptr(base),page,C.PROT_READ)==0
	for request in [u64(0),0x3f,0xff,0x100,0x13f,0x1ff]! {
		for _ in 0..32 {assert lookup(request,name,5,0,0)==metadata}
	}
	assert C.munmap(voidptr(base),page)==0
}

fn dispatch_autorelease_padding(start u64, page u64, value u64, width u64) {
	for offset in u64(0) .. page {
		address := start + offset
		if address < value || address >= value + width { assert unsafe { *(&u8(address)) } == 0xa5 }
	}
}

fn dispatch_autorelease_values(metadata u64) {
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	destroy := unsafe { DispatchFlagsDestroy(voidptr(read64(witness + 8) & 0x0000ffffffffffff)) }
	project := unsafe { DispatchFlagsDestroy(voidptr(read64(witness + 96) & 0x0000ffffffffffff)) }
	inject := unsafe { DispatchCaseInject(voidptr(read64(witness + 104) & 0x0000ffffffffffff)) }
	tag := unsafe { DispatchCaseTag(voidptr(read64(witness + 88) & 0x0000ffffffffffff)) }
	get_tag := unsafe { DispatchFlagsGetTag(voidptr(read64(witness + 48) & 0x0000ffffffffffff)) }
	store_tag := unsafe { DispatchFlagsStoreTag(voidptr(read64(witness + 56) & 0x0000ffffffffffff)) }
	// These witnesses must not read even value/metadata when there is no work.
	destroy(span, span)
	project(span, span)
	assert get_tag(span, 0, span) == 0
	store_tag(span, 0, 0, span)
	for source_end in [false, true]! {
		for destination_end in [false, true]! {
			source := span + u64(page) + if source_end { u64(page) - 1 } else { u64(0) }
			destination := span + u64(page * 3) + if destination_end { u64(page) - 1 } else { u64(0) }
			assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
			for which in u32(0) .. 256 {
				assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
				unsafe { *(&u8(source)) = u8(which) }
				assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
				assert tag(source, span) == which
				destroy(source, span)
				project(source, span)
				for slot in [u64(0), 16, 24, 32, 40]! {
					transfer := unsafe { DispatchFlagsCopy(voidptr(read64(witness + slot) & 0x0000ffffffffffff)) }
					C.memset(voidptr(span + u64(page * 3)), 0xa5, page)
					assert transfer(destination, source, span) == destination
					assert transfer(destination, destination, span) == destination
					assert unsafe { *(&u8(source)) } == u8(which)
					assert unsafe { *(&u8(destination)) } == u8(which)
					dispatch_autorelease_padding(span + u64(page * 3), u64(page), destination, 1)
				}
			}
			for which in [u32(0), 1, 7, 2, 3, 255, 256, 0xffffffff]! {
				C.memset(voidptr(span + u64(page * 3)), 0xa5, page)
				inject(destination, which, span)
				assert tag(destination, span) == u32(u8(which))
				dispatch_autorelease_padding(span + u64(page * 3), u64(page), destination, 1)
			}
		}
	}
	// Native byte-width boundaries are conservative. The extreme UInt32 counts
	// wrap their count+2 calculation and may truncate a stored empty-case tag.
	for pair in [[u32(0), 0]!, [u32(1), 0]!, [u32(3), 0]!, [u32(252), 0]!,
		[u32(253), 0]!, [u32(254), 1]!, [u32(255), 1]!, [u32(256), 1]!,
		[u32(65277), 1]!, [u32(65278), 2]!, [u32(65533), 2]!, [u32(65534), 2]!,
		[u32(16776957), 2]!, [u32(16776958), 4]!, [u32(16777213), 4]!,
		[u32(16777214), 4]!, [u32(0x7fffffff), 4]!, [u32(0xfffffffd), 4]!,
		[u32(0xfffffffe), 1]!, [u32(0xffffffff), 1]!]! {
		cases := pair[0]
		width := u64(pair[1])
		for which in [u32(0), 1, 3, 252, 253, 254, 255, 256, 509, 510,
			65277, 65278, 65533, 65534, 16776957, 16776958, 16777213, 16777214,
			0x7fffffff, 0xfffffffd, 0xfffffffe, 0xffffffff]! {
			if which > cases { continue }
			for at_end in [false, true]! {
				value := span + u64(page * 3) + if at_end { u64(page) - 1 - width } else { u64(0) }
				C.memset(voidptr(span + u64(page * 3)), 0xa5, page)
				unsafe { *(&u8(value)) = 7 }
				store_tag(value, which, cases, span)
				payload := if which == 0 { u8(7) } else if which <= 253 { u8(which + 2) } else { u8(which - 254) }
				assert unsafe { *(&u8(value)) } == payload
				bits := if which <= 253 { u32(0) } else { ((which - 254) >> 8) + 1 }
				mut stored := u32(0)
				for i in u64(0) .. width {
					byte := unsafe { *(&u8(value + 1 + i)) }
					assert byte == u8(bits >> (i * 8))
					stored |= u32(byte) << (i * 8)
				}
				expected := if cases == 0 { u32(0) } else if stored != 0 {
					((stored - 1) << 8) + u32(payload) + 254
				} else if payload < 3 { u32(0) } else { u32(payload) - 2 }
				assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
				assert get_tag(value, cases, span) == expected
				dispatch_autorelease_padding(span + u64(page * 3), u64(page), value, 1 + width)
				assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
			}
		}
	}
	assert C.munmap(voidptr(span), page * 5) == 0
}

fn dispatch_autorelease_layout(entry u64, probe DispatchFlagsProbe, native bool) u64 {
	metadata := unsafe { DispatchFlagsAccess(voidptr(entry))(0) }.metadata
	descriptor := read64(metadata + 8); witness := read64(metadata - 8)
	assert read64(metadata) == 0x201
	assert read64(witness + 64) == 1 && read64(witness + 72) == 1
	assert read32(witness + 80) == 0x02200000 && read32(witness + 84) == 253
	assert read32(descriptor) == 0x52 && read32(descriptor + 20) == 0 && read32(descriptor + 24) == 3
	assert dispatch_flags_name(dispatch_flags_relative(descriptor + 8)) == 'AutoreleaseFrequency'
	parent := dispatch_flags_relative(descriptor + 4)
	assert read32(parent) == 0x41
	assert dispatch_flags_name(dispatch_flags_relative(parent + 8)) == 'So17OS_dispatch_queueC'
	module_descriptor := dispatch_flags_relative(parent + 4)
	assert read32(module_descriptor) == 0 && read32(module_descriptor + 4) == 0
	assert dispatch_flags_name(dispatch_flags_relative(module_descriptor + 8)) == 'Dispatch'
	if !native {
		assert dispatch_flags_relative(descriptor + 16) == 0
		dispatch_flags_protection(entry, 24, true)
		dispatch_flags_protection(metadata - 8, 196, false)
	}
	for accessor in [entry, dispatch_flags_relative(descriptor + 12)]! {
		for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff, ~u64(0)]! {
			mut words := [u64(0x1234), 0, 0, 0, 0, 0x5678]!
			probe(request, accessor, unsafe { &words[1] })
			assert words == [u64(0x1234), metadata, 0, 0x5020, 0x5021, 0x5678]!
		}
	}
	dispatch_autorelease_values(metadata)
	return metadata
}

fn dispatch_flags_worker(first_kind int) u64 {
	library:='/usr/lib/swift/libswiftDispatch.dylib'
	first:=['_$s8Dispatch0A13WorkItemFlagsVMa','_$s8Dispatch0A13WorkItemFlagsVMn','_$sSo17OS_dispatch_queueC8DispatchE10AttributesVMa','_$sSo17OS_dispatch_queueC8DispatchE10AttributesVMn',dispatch_inherit_case_symbol,dispatch_autorelease_symbol]![first_kind]
	initial:=runtime_symbol(library,first) or {panic(err)}; assert initial!=0
	mut entry:=u64(0)
	mut attributes_metadata:=u64(0)
	mut enum_metadata:=u64(0)
	for _ in 0..512 {
		entry=runtime_symbol(library,'_$s8Dispatch0A13WorkItemFlagsVMa') or {panic(err)}
		descriptor:=runtime_symbol(library,'_$s8Dispatch0A13WorkItemFlagsVMn') or {panic(err)}
		access:=unsafe {DispatchFlagsAccess(voidptr(entry))}; result:=access(0xff)
		assert result.state==0 && read64(result.metadata+8)==descriptor
		attributes_entry:=runtime_symbol(library,'_$sSo17OS_dispatch_queueC8DispatchE10AttributesVMa') or {panic(err)}
		attributes_descriptor:=runtime_symbol(library,'_$sSo17OS_dispatch_queueC8DispatchE10AttributesVMn') or {panic(err)}
		attributes:=unsafe {DispatchFlagsAccess(voidptr(attributes_entry))(0x13f)}
		assert attributes.state==0 && attributes.metadata!=result.metadata && read64(attributes.metadata+8)==attributes_descriptor
		inherit_case:=runtime_symbol(library,dispatch_inherit_case_symbol) or {panic(err)}
		assert inherit_case%4==0 && read32(inherit_case)==0
		enum_entry:=runtime_symbol(library,dispatch_autorelease_symbol) or {panic(err)}
		enum_result:=unsafe {DispatchFlagsAccess(voidptr(enum_entry))(0x1ff)}
		assert enum_result.state==0 && read64(enum_result.metadata)==0x201
		assert enum_result.metadata!=result.metadata && enum_result.metadata!=attributes.metadata
		if enum_metadata==0 {enum_metadata=enum_result.metadata} else {assert enum_result.metadata==enum_metadata}
		inject:=unsafe {DispatchCaseInject(voidptr(read64(read64(enum_metadata-8)+104)))}
		tag:=unsafe {DispatchCaseTag(voidptr(read64(read64(enum_metadata-8)+88)))}
		mut payload:=[u8(0xca),0xdd,0xfe]!
		inject(u64(unsafe {&payload[1]}),u32(first_kind%3),enum_metadata)
		assert payload==[u8(0xca),u8(first_kind%3),0xfe]! && tag(u64(unsafe {&payload[1]}),enum_metadata)==u32(first_kind%3)
		assert initial==[entry,descriptor,attributes_entry,attributes_descriptor,inherit_case,enum_entry]![first_kind]
		if attributes_metadata==0 {attributes_metadata=attributes.metadata} else {assert attributes.metadata==attributes_metadata}
	}
	return entry
}

fn dispatch_flags_reject_lifetime() {
	if _:=swift_dispatch_flags_arena_checked() {assert false,'retired Dispatch metadata recreated'}
	for symbol in ['_$sSo17OS_dispatch_queueC8DispatchE10AttributesVMa','_$sSo17OS_dispatch_queueC8DispatchE10AttributesVMn',dispatch_inherit_case_symbol,dispatch_autorelease_symbol]! {
		if _:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib',symbol) {assert false}
	}
}

fn test_swift_dispatch_flags_metadata() {
	page:=usize(C.getpagesize()); code:=u64(C.mmap(unsafe {nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)); assert code!=u64(-1)
	for i, word in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0203f3,0xaa0103f0,0xd28a0414,0xd28a0435,0xd63f0200,0xa9000660,0xa9015674,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! {write32(code+u64(i*4),word)}
	// Match Fortnite's UInt32 load; place source and destination against guards.
	for i, word in [u32(0xa9bf57f4),0xb9400004,0xb9000024,0xa9000460,0xaa0203f4,0xd28a0435,0xa9015474,0xa8c157f4,0xd65f03c0]! {write32(code+128+u64(i*4),word)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+164)); assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	probe:=unsafe {DispatchFlagsProbe(voidptr(code))}
	case_probe:=unsafe {DispatchCaseLoad(voidptr(code+128))}
	$if macos {
		lib:=C.dlopen(c'/usr/lib/swift/libswiftDispatch.dylib',2); core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2); assert lib!=unsafe {nil} && core!=unsafe {nil}
		entry:=u64(C.dlsym(lib,c'$s8Dispatch0A13WorkItemFlagsVMa')); descriptor:=u64(C.dlsym(lib,c'$s8Dispatch0A13WorkItemFlagsVMn')); assert entry!=0 && descriptor!=0
		metadata:=dispatch_flags_layout(entry,descriptor,probe,true,false); dispatch_flags_values(metadata)
		lookup:=unsafe {DispatchFlagsLookup(C.dlsym(core,c'swift_getTypeByMangledNameInContextInMetadataState'))}; dispatch_flags_symbolic(lookup,descriptor,metadata)
		attributes_entry:=u64(C.dlsym(lib,c'$sSo17OS_dispatch_queueC8DispatchE10AttributesVMa')); assert attributes_entry!=0
		attributes:=unsafe {DispatchFlagsAccess(voidptr(attributes_entry))(0)}.metadata
		attributes_descriptor:=u64(C.dlsym(lib,c'$sSo17OS_dispatch_queueC8DispatchE10AttributesVMn'))
		assert attributes_descriptor!=0 && read64(attributes+8)==attributes_descriptor
		assert dispatch_flags_layout(attributes_entry,attributes_descriptor,probe,true,true)==attributes
		assert attributes!=metadata && attributes_descriptor!=descriptor
		dispatch_flags_values(attributes); dispatch_flags_symbolic(lookup,attributes_descriptor,attributes)
		inherit_case:=u64(C.dlsym(lib,c'$sSo17OS_dispatch_queueC8DispatchE20AutoreleaseFrequencyO7inherityA2EmFWC'))
		assert inherit_case==u64(C.dlsym(lib,dispatch_inherit_case_symbol[1..].str))
		dispatch_case_spans(inherit_case,case_probe)
		enum_entry:=C.dlsym(lib,c'$sSo17OS_dispatch_queueC8DispatchE20AutoreleaseFrequencyOMa'); assert enum_entry!=unsafe {nil}
		enum_metadata:=dispatch_autorelease_layout(u64(enum_entry),probe,true)
		dispatch_flags_symbolic(lookup,read64(enum_metadata+8),enum_metadata)
		enum_result:=unsafe {DispatchFlagsAccess(enum_entry)(0)}; assert enum_result.metadata==enum_metadata && enum_result.state==0
		enum_witness:=read64(enum_result.metadata-8)
		assert read64(enum_witness+64)==1 && read64(enum_witness+72)==1
		inject:=unsafe {DispatchCaseInject(voidptr(read64(enum_witness+104)))}
		tag:=unsafe {DispatchCaseTag(voidptr(read64(enum_witness+88)))}
		mut payload:=[u8(0xca),0xdd,0xfe]!
		inject(u64(unsafe {&payload[1]}),read32(inherit_case),enum_result.metadata)
		assert payload==[u8(0xca),0,0xfe]! && tag(u64(unsafe {&payload[1]}),enum_result.metadata)==0
		println('IOS-DISPATCH-FLAGS-NATIVE: Flags and Queue.Attributes Ma/Mn export identity, complete pointer/state accessor ABI, UInt64 POD8 witnesses/flags, distinct Dispatch nominal identities and nested extension context, rawValue offset, every metadata request, x20/x21 and result guards, exact copy/take/self-assignment, no-op destruction, protected eight-byte payloads/unused metadata, single-payload tag branches/UInt32 wrapping, indirect symbolic lookup; AutoreleaseFrequency Ma, three-case POD1 metadata/descriptor, all byte representations, guarded exact-byte witnesses, single-payload width boundaries/UInt32 wrapping and canonical UInt32 inherit discriminator')
	}
	dispatch_flags_reject_lifetime()
	for _ in 0..2 {
		objc_start()
		for unknown in ['_$s8Dispatch0A13WorkItemFlagsVN','_$s8Dispatch0A3QoSVN','_$sSo17OS_dispatch_queueC8DispatchE10AttributesVN','_$sSo17OS_dispatch_queueC8DispatchE20AutoreleaseFrequencyOMn','_$sSo17OS_dispatch_queueC8DispatchE20AutoreleaseFrequencyO8workItemyA2EmFWC','_$sSo17OS_dispatch_queueC8DispatchE20AutoreleaseFrequencyO5neveryA2EmFWC']! {
			if _:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib',unknown) {assert false}
		}
		assert ios_runtime.swift_dispatch_flags_arena==0
		mut workers:=[]thread u64{}
		for i in 0..8 {workers<<spawn dispatch_flags_worker(i%6)}
		entries:=workers.wait(); entry:=entries[0]; for candidate in entries {assert candidate==entry}
		descriptor:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib','_$s8Dispatch0A13WorkItemFlagsVMn') or {panic(err)}
		metadata:=dispatch_flags_layout(entry,descriptor,probe,false,false); dispatch_flags_values(metadata)
		lookup:=unsafe {DispatchFlagsLookup(voidptr(swift_mangled_state_lookup))}; dispatch_flags_symbolic(lookup,descriptor,metadata)
		assert metadata!=swift_integer_metadata() && descriptor!=read64(swift_integer_metadata()+8)
		attributes_entry:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib','_$sSo17OS_dispatch_queueC8DispatchE10AttributesVMa') or {panic(err)}
		attributes:=unsafe {DispatchFlagsAccess(voidptr(attributes_entry))(0)}.metadata
		attributes_descriptor:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib','_$sSo17OS_dispatch_queueC8DispatchE10AttributesVMn') or {panic(err)}
		assert read64(attributes+8)==attributes_descriptor
		assert dispatch_flags_layout(attributes_entry,attributes_descriptor,probe,false,true)==attributes
		assert attributes!=metadata && attributes!=swift_integer_metadata() && attributes_descriptor!=descriptor
		qos_entry:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib','_$s8Dispatch0A3QoSVMa') or {panic(err)}
		assert attributes!=unsafe {DispatchFlagsAccess(voidptr(qos_entry))(0)}.metadata
		dispatch_flags_values(attributes); dispatch_flags_symbolic(lookup,attributes_descriptor,attributes)
		inherit_case:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib',dispatch_inherit_case_symbol) or {panic(err)}
		dispatch_flags_protection(inherit_case,4,false)
		dispatch_case_spans(inherit_case,case_probe)
		enum_entry:=runtime_symbol('/usr/lib/swift/libswiftDispatch.dylib',dispatch_autorelease_symbol) or {panic(err)}
		enum_metadata:=dispatch_autorelease_layout(enum_entry,probe,false)
		assert enum_metadata!=metadata && enum_metadata!=attributes && enum_metadata!=unsafe {DispatchFlagsAccess(voidptr(qos_entry))(0)}.metadata
		assert dispatch_flags_relative(read64(enum_metadata+8)+4)==dispatch_flags_relative(attributes_descriptor+4)
		dispatch_flags_symbolic(lookup,read64(enum_metadata+8),enum_metadata)
		if _:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$s8Dispatch0A13WorkItemFlagsVMa') {assert false}
		if _:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sSo17OS_dispatch_queueC8DispatchE10AttributesVMa') {assert false}
		if _:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$sSo17OS_dispatch_queueC8DispatchE10AttributesVMn') {assert false}
		if _:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib',dispatch_inherit_case_symbol) {assert false}
		if _:=runtime_symbol('/usr/lib/swift/libswiftCore.dylib',dispatch_autorelease_symbol) {assert false}
		assert ios_runtime.swift_heap.len==0 && ios_runtime.swift_buffers.len==0 && ios_runtime.swift_arrays.len==0 && ios_runtime.live==0
		base:=ios_runtime.swift_dispatch_flags_arena
		$if !macos {mut residency:=[u8(0),0]!; assert C.mincore(voidptr(base),page*2,unsafe {&residency[0]})==0}
		objc_stop()
		assert ios_runtime.swift_dispatch_flags_arena==0 && ios_runtime.swift_dispatch_flags_retired
		$if macos {assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}
		$else {mut residency:=[u8(0),0]!; assert C.mincore(voidptr(base),page*2,unsafe {&residency[0]})==-1}
		dispatch_flags_reject_lifetime(); assert ios_runtime.swift_dispatch_flags_arena==0
	}
	assert C.munmap(voidptr(code),page)==0
	println('IOS-DISPATCH-FLAGS: exact Dispatch-only Flags and Queue.Attributes Ma/Mn exports, distinct complete POD8 nominal metadata and nested extension context, existing ownership-free witnesses and exact tag store, sealed adjacent accessor/data pages, canonical eight-worker accessor/descriptor/constant-first publication, shared symbolic metadata-state lookup; AutoreleaseFrequency Ma, three-case POD1 metadata/descriptor, all byte representations, guarded exact-byte witnesses, single-payload width boundaries/UInt32 wrapping and read-only aligned UInt32 inherit discriminator; no heap/ARC ownership, rejected unsupported exports/lifetimes and two unmapped runtime teardowns')
}
