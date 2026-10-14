// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <objc/runtime.h>
	#include <mach/mach.h>
}
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.mincore(voidptr,usize,&u8) i32
fn C.mach_task_self() u32
fn C.vm_region_64(u32,&u64,&u64,i32,&i32,&u32,&u32) i32
fn C.mach_port_deallocate(u32,u32) i32
type LoggerAccess = fn (u64) SwiftAssociatedMetadata
type LoggerGetterProbe = fn (u64,u64,u64,&u64)
type LoggerInitProbe = fn (u64,&u64,u64,u64,&u64)
type LoggerLiteral = fn (&u8,i64,bool) SwiftStringWords
type LoggerCreate = fn (&char,&char) u64
type LoggerSend = fn (u64,u64) u64
type LoggerRelease = fn (u64)
type LoggerCopy = fn (u64,u64,u64) u64
type LoggerDestroy = fn (u64,u64)
type LoggerGetTag = fn (u64,u32,u64) u32
type LoggerStoreTag = fn (u64,u32,u32,u64)
type LoggerInterpolation = fn (i64,i64) SwiftStringWords
type LoggerRetain = fn (u64) u64
struct LoggerApi {
	native bool
	access u64
	getter u64
	initializer u64
	descriptor u64
	@[required]
	literal LoggerLiteral
	@[required]
	create LoggerCreate
	@[required]
	release LoggerRelease
	@[required]
	interpolate LoggerInterpolation
	@[required]
	bridge_retain LoggerRetain
	@[required]
	bridge_release LoggerRelease
}
fn logger_api(native bool) LoggerApi {
	mut entry := [4]u64{}
	for i,name in ['_$s2os6LoggerVMa','_$s2os6LoggerV9logObjectSo03OS_a1_C0Cvg','_$s2os6LoggerV9subsystem8categoryACSS_SStcfC','_$s2os6LoggerVMn']! {
		if native { entry[i] = u64(C.dlsym(C.dlopen(c'/usr/lib/swift/libswiftos.dylib',2),name[1..].str)) }
		else { entry[i] = runtime_symbol('/usr/lib/swift/libswiftos.dylib',name) or { panic(err) } }
		assert entry[i] != 0
	}
	$if macos { if native {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2)
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib',2)
		assert core != unsafe { nil } && objc != unsafe { nil }
		return LoggerApi{native:true,access:entry[0],getter:entry[1],initializer:entry[2],descriptor:entry[3],
			literal:unsafe { LoggerLiteral(C.dlsym(core,c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC')) },
			create:unsafe { LoggerCreate(C.dlsym(voidptr(-2),c'os_log_create')) },
			release:unsafe { LoggerRelease(C.dlsym(objc,c'objc_release')) },
			interpolate:unsafe { LoggerInterpolation(C.dlsym(core,c'$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC')) },
			bridge_retain:unsafe { LoggerRetain(C.dlsym(core,c'swift_bridgeObjectRetain')) },
			bridge_release:unsafe { LoggerRelease(C.dlsym(core,c'swift_bridgeObjectRelease')) } }
	} }
	return LoggerApi{access:entry[0],getter:entry[1],initializer:entry[2],descriptor:entry[3],literal:swift_string_literal,create:darwin_os_log_create,release:objc_release,
		interpolate:swift_interpolation_init,bridge_retain:swift_bridge_retain,bridge_release:swift_bridge_release}
}
fn logger_ascii(text string) bool { for byte in text { if byte >= 128 { return false } }; return true }
fn logger_send(owner u64,selector &char) u64 {
	return unsafe { LoggerSend(C.dlsym(voidptr(-2),c'objc_msgSend'))(owner,u64(C.sel_registerName(selector))) }
}
fn logger_refs(api LoggerApi,owner u64) u64 {
	$if macos { if api.native { return logger_send(owner,c'retainCount') } }
	return u64(obj_header(owner).refs)
}
fn logger_owner(api LoggerApi) u64 {
	$if macos { if api.native { return logger_send(u64(C.objc_getClass(c'NSObject')),c'new') } }
	return objc_new(ios_runtime.names['NSObject'])
}
fn logger_unmapped(arena u64,page usize) {
	$if macos {
		// Darwin mincore succeeds with an unmapped-page bit in its vector.
		// Query the next actual VM region rather than expecting Linux errno.
		mut start := arena; mut size := u64(0); mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64); mut object := u32(0)
		status := C.vm_region_64(C.mach_task_self(),&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe { &info[0] },&count,&object)
		assert status != 0 || start >= arena + u64(page * 2)
		if object != 0 { assert C.mach_port_deallocate(C.mach_task_self(),object) == 0 }
	} $else {
		mut resident := u8(0); assert C.mincore(voidptr(arena),page,&resident) == -1
	}
}
fn logger_get(api LoggerApi,probe LoggerGetterProbe,source u64,expected u64) {
	mut result := [u64(0xcafe),0,0,0,0,0xbeef]!
	probe(api.getter,source,0x5021,unsafe { &result[1] })
	assert result[0] == 0xcafe && result[1] == expected && result[3] == source && result[4] == 0x5021 && result[5] == 0xbeef
	assert read64(source) == expected
}
fn logger_initialize(api LoggerApi,probe LoggerInitProbe,subsystem string,category string,output u64,guard u64) u64 {
	a := api.literal(subsystem.str,subsystem.len,logger_ascii(subsystem))
	b := api.literal(category.str,category.len,logger_ascii(category))
	mut arguments := [a.first,a.second,b.first,b.second]!
	mut result := [u64(0xcafe),0,0,0xbeef]!
	probe(api.initializer,unsafe { &arguments[0] },output,guard,unsafe { &result[1] })
	assert result == [u64(0xcafe),guard,0x5021,0xbeef]!
	assert arguments == [a.first,a.second,b.first,b.second]!
	owner := read64(output)
	assert owner == api.create(subsystem.str,category.str)
	return owner
}
fn logger_values(api LoggerApi,metadata u64,source u64,owner u64) {
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	assert read64(witness + 64) == 8 && read64(witness + 72) == 8
	assert read32(witness + 80) & 0x007fffff == 0x10007 && read32(witness + 84) == 0x7fffffff
	mut destination := [u64(0xcafe),0,0xbeef]!
	dst := u64(unsafe { &destination[1] })
	destroy := unsafe { LoggerDestroy(voidptr(read64(witness + 8) & 0x0000ffffffffffff)) }
	for slot in [0,2]! {
		transfer := unsafe { LoggerCopy(voidptr(read64(witness + u64(slot * 8)) & 0x0000ffffffffffff)) }
		assert transfer(dst,source,metadata) == dst && destination[1] == owner && logger_refs(api,owner) == 2
		destroy(dst,metadata); assert logger_refs(api,owner) == 1 && destination[1] == owner
	}
	assign := unsafe { LoggerCopy(voidptr(read64(witness + 24) & 0x0000ffffffffffff)) }
	// Swift's installed compact-layout assignment destroys destination before
	// copying source; use distinct initialized storage as generated callers do.
	unsafe { *(&u64(dst)) = logger_owner(api) }
	assert assign(dst,source,metadata) == dst && destination[1] == owner && logger_refs(api,owner) == 2
	destroy(dst,metadata); assert logger_refs(api,owner) == 1
	for slot in [4,5]! {
		transfer := unsafe { LoggerCopy(voidptr(read64(witness + u64(slot * 8)) & 0x0000ffffffffffff)) }
		unsafe { *(&u64(dst)) = 0 }
		assert transfer(dst,source,metadata) == dst && destination[1] == owner && logger_refs(api,owner) == 1
		// Take leaves the source uninitialized, with its bits unchanged. Restore
		// ownership to source without destroying either of the duplicate bits.
		assert read64(source) == owner
	}
	assert destination[0] == 0xcafe && destination[2] == 0xbeef
}
fn logger_enums(metadata u64,guard u64) {
	witness := read64(metadata - 8) & 0x0000ffffffffffff
	get_tag := unsafe { LoggerGetTag(voidptr(read64(witness + 48) & 0x0000ffffffffffff)) }
	store_tag := unsafe { LoggerStoreTag(voidptr(read64(witness + 56) & 0x0000ffffffffffff)) }
	assert get_tag(guard,0,guard) == 0
	store_tag(guard,0,0,guard)
	for cases in [u32(0),1,255,0x7fffffff,0x80000000,0xffffffff]! { for tag in [u32(0),1,255,0x7fffffff,0x80000000,0xffffffff]! {
		if tag > cases { continue }
		length := if cases > 0x7fffffff { 9 } else { 8 }
		value := guard - u64(length)
		C.memset(voidptr(value),0xa5,usize(length)); store_tag(value,tag,cases,metadata)
		assert get_tag(value,cases,metadata) == tag
		mut payload := u64(0); C.memcpy(unsafe { &payload },voidptr(value),8)
		assert payload == if tag == 0 { u64(0xa5a5a5a5a5a5a5a5) } else if tag <= 0x7fffffff { u64(tag - 1) } else { u64(tag - 0x80000000) }
		if length == 9 { assert unsafe { *(&u8(value + 8)) } == if tag > 0x7fffffff { u8(1) } else { u8(0) } }
	} }
}
fn logger_worker(api LoggerApi,probe LoggerGetterProbe,owner u64) u64 {
	mut own := api
	if !api.native { own = logger_api(false); assert own.access == api.access && own.getter == api.getter && own.initializer == api.initializer }
	mut source := owner
	for _ in 0 .. 1000 { logger_get(own,probe,u64(unsafe { &source }),owner); api.release(owner) }
	return own.access
}
fn logger_suite(api LoggerApi,getter LoggerGetterProbe,initialize LoggerInitProbe) u64 {
	accessor := unsafe { LoggerAccess(voidptr(api.access)) }
	metadata := accessor(0).metadata
	for request in [u64(0),0xff,0x100,0x1ff,u64(-1)]! { assert accessor(request) == SwiftAssociatedMetadata{metadata:metadata} }
	assert read64(metadata) == 0x200 && read64(metadata + 8) == api.descriptor && read32(metadata + 16) == 0
	assert read32(api.descriptor) & 0xffff == 0x51 && read32(api.descriptor + 20) == 1 && read32(api.descriptor + 24) == 2
	page := u64(C.getpagesize())
	region := u64(C.mmap(unsafe { nil },usize(page * 2),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0))
	assert region != u64(-1) && C.mprotect(voidptr(region + page),usize(page),C.PROT_NONE) == 0
	guard := region + page; source := guard - 8
	owner := logger_owner(api)
	unsafe { *(&u64(source)) = owner }
	assert logger_refs(api,owner) == 1
	logger_get(api,getter,source,owner); assert logger_refs(api,owner) == 2; api.release(owner)
	logger_values(api,metadata,source,owner)
	mut workers := []thread u64{}
	for _ in 0 .. 8 { workers << spawn logger_worker(api,getter,owner) }
	for result in workers.wait() { assert result == api.access }
	assert logger_refs(api,owner) == 1; api.release(owner)
	unsafe { *(&u64(source)) = 0 }; logger_get(api,getter,source,0)
	for labels in [['','']!,['epic','fortnite']!,['org.vinix.fortnite.logger','MarketplaceKitWrapper']!,['логгер','ошибка']!,['a\x00ignored','category\x00ignored']!]! {
		log := logger_initialize(api,initialize,labels[0],labels[1],source,guard)
		logger_get(api,getter,source,log); api.release(log); api.release(log)
	}
	logger_enums(metadata,guard)
	for alias in [false,true]! {
		a := api.interpolate(40,0); b := if alias { a } else { api.interpolate(40,0) }
		if alias { api.bridge_retain(a.second) }
		bits_a := read64((a.second & swift_address_mask) + 8)
		bits_b := read64((b.second & swift_address_mask) + 8)
		api.bridge_retain(a.second); api.bridge_retain(b.second)
		mut arguments := [a.first,a.second,b.first,b.second]!
		mut contexts := [u64(0),0]!
		initialize(api.initializer,unsafe { &arguments[0] },source,guard,unsafe { &contexts[0] })
		assert contexts == [guard,u64(0x5021)]!
		assert read64((a.second & swift_address_mask) + 8) == bits_a && read64((b.second & swift_address_mask) + 8) == bits_b
		assert read64(source) == api.create(c'',c'')
		api.release(read64(source)); api.bridge_release(a.second); api.bridge_release(b.second)
	}
	assert C.munmap(voidptr(region),usize(page * 2)) == 0
	return metadata
}
fn test_swift_logger() {
	$if !arm64 { return }
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)); assert code != u64(-1)
	// Ordinary probe arguments -> Swift borrowed Self x20; record x0/x1,
	// x20/x21 after return and restore all caller callee-saved registers.
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xf90013f5,0xaa0003f0,0xaa0103f4,0xaa0203f5,0xaa0303f3,0xd63f0200,0xa9000660,0xa9015674,0xf94013f5,0xa94153f3,0xa8c37bfd,0xd65f03c0]! { write32(code + u64(i * 4),op) }
	// entry, four argument words, result, Self, context outputs.
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f0,0xaa0403f3,0xaa0303f4,0xd28a0435,0xaa0203e8,0xaa0103e9,0xa9400520,0xa9410d22,0xd63f0200,0xa9005674,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]! { write32(code + 128 + u64(i * 4),op) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code + 196)); assert C.mprotect(voidptr(code),page,C.PROT_READ | C.PROT_EXEC) == 0
	getter := unsafe { LoggerGetterProbe(voidptr(code)) }; initialize := unsafe { LoggerInitProbe(voidptr(code + 128)) }
	$if macos {
		logger_suite(logger_api(true),getter,initialize)
		println('IOS-LOGGER-NATIVE: complete one-reference metadata, exact eight-byte borrowed Self and retained result, x8 initializer with preserved contexts, inline/large/Unicode/NUL labels, copy/take/assign/destroy ownership, optional payloads through UINT32_MAX and 8000 concurrent getter calls')
	}
	if _ := swift_logger_arena() { assert false }
	for _ in 0 .. 2 {
		objc_start(); system_data_start() or { panic(err) }
		api := logger_api(false); metadata := logger_suite(api,getter,initialize)
		assert swift_mangled_nominal(api.descriptor) or { panic(err) } == metadata
		// Initializer consumes both distinct owned Strings and shared aliases.
		for alias in [false,true]! {
			a := swift_interpolation_init(40,0); b := if alias { a } else { swift_interpolation_init(40,0) }
			if alias { swift_bridge_retain(a.second) }
			mut output := [u64(0xcafe),0,0xbeef]!
			swift_logger_initialize_checked(a.first,a.second,b.first,b.second,u64(unsafe { &output[1] })) or { panic(err) }
			assert output[0] == 0xcafe && output[2] == 0xbeef && os_log_is_handle(output[1]) && ios_runtime.swift_strings.len == 0
		}
		guard := u64(C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)); assert guard != u64(-1)
		mut value := guard; if _ := swift_logger_object_checked(u64(unsafe { &value })) { assert false }
		if _ := swift_logger_object_checked(0) { assert false }
		if _ := swift_logger_initialize_checked(0,0,0,0,guard) { assert false }
		// A large label fails before its protected bytes or output are touched.
		if _ := swift_logger_initialize_checked(0x1000000000000100,0x8000000000000000 | (guard - 32),0,0xe000000000000000,guard) { assert false }
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0
		storage := swift_array_allocate(2,metadata); unsafe { *(&u64(storage.owner + 16)) = 2; *(&u64(storage.bytes)) = darwin_os_log_create(c'epic',c'fortnite'); *(&u64(storage.bytes + 8)) = read64(storage.bytes) }
		swift_release(storage.owner); assert ios_runtime.swift_arrays.len == 0
		for symbol in ['_$s2os6LoggerV5debugyyAA12OSLogMessageVF','_$s2os6LoggerVACycfC','_$s2os6LoggerV5error']! { if _ := runtime_symbol('/usr/lib/swift/libswiftos.dylib',symbol) { assert false } }
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib','_$s2os6LoggerVMa') { assert false }
		arena := ios_runtime.swift_logger_arena
		// Observe retirement immediately, before subsequent teardown work.
		C.ios_objc_initialize_lock(); swift_logger_stop(); C.ios_objc_initialize_unlock()
		logger_unmapped(arena,page)
		if _ := swift_logger_arena() { assert false }; if _ := swift_logger_object_checked(guard) { assert false }
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.swift_logger_arena == 0
		system_data_stop(); assert system_data == unsafe { nil }; assert C.munmap(voidptr(guard),page) == 0
	}
	assert C.munmap(voidptr(code),page) == 0
	println('IOS-LOGGER: matching getter/initializer/metadata ABI, registered handle and ObjC ARC, consumed owned String aliases, bounded fail-before-consume labels and foreign referents, symbolic metadata and typed Array destruction, eight workers and two unmapped/drained runtime lifetimes')
}
