// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFURL.h>
	#include <CoreFoundation/CFData.h>
	#include <CoreFoundation/CFDictionary.h>
	#include <objc/runtime.h>
	#include <mach/mach.h>
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.CFURLCreateFromFileSystemRepresentation(voidptr, &u8, i64, bool) voidptr
fn C.CFURLCreateWithBytes(voidptr, &u8, i64, u32, voidptr) voidptr
fn C.CFDataCreate(voidptr, voidptr, i64) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFDictionaryGetValue(voidptr, voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.link(&char, &char) i32
fn C.umask(u32) u32
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

type DataWriteProbe = fn (u64, u64, u64, u64, u64, u64, u64)
type DataWriteConstructURL = fn (u64, u64, u64)
type DataWriteConstructData = fn (u64) SwiftDataWords
type DataWriteAccess = fn (u64) SwiftAssociatedMetadata
type DataWriteDestroy = fn (u64, u64)
type DataWriteRelease = fn (u64)
type DataWriteErrorBridge = fn (u64) u64
type DataWriteSend = fn (u64, u64) u64

struct DataWriteApi {
	native           bool
	entry            u64
	code             u64
	data_metadata    u64
	url_metadata     u64
	url_constructor  u64
	private_metadata u64
	private_table    u64
	data_constructor DataWriteConstructData
	data_destroy     DataWriteDestroy
	url_destroy      DataWriteDestroy
	error_release    DataWriteRelease
	error_bridge     DataWriteErrorBridge
	object_release   DataWriteRelease
}

fn data_write_native_send(object u64, selector &char) u64 {
	$if macos {
		return unsafe { DataWriteSend(C.dlsym(C.dlopen(c'/usr/lib/libobjc.A.dylib', 2), c'objc_msgSend'))(object, u64(C.sel_registerName(selector))) }
	} $else { panic('native file write messaging requires macOS') }
}

fn data_write_witness(owner u64) u64 {
	assert read64(owner + 8) == 3 // Borrowed implementation, including reentry.
	assert swift_foundation_symbol('_$s10Foundation3URLVMa') or { panic(err) } != 0
	return objc_retain(read64(owner + 16))
}

fn data_write_url_destroy(owner u64) {
	objc_release(read64(owner + 16))
	swift_heap_deallocate(owner, 32, 15)
}

fn data_write_drop_url(value u64, _metadata u64) { swift_release(read64(value)) }

fn data_write_api(native bool, code u64, metadata u64, table u64) DataWriteApi {
	name := '_$s10Foundation4DataV5write2to7optionsyAA3URLV_So20NSDataWritingOptionsVtKF'
	if native {
		lib := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		data_response := unsafe { DataWriteAccess(C.dlsym(lib, c'$s10Foundation4DataVMa'))(0) }
		url_response := unsafe { DataWriteAccess(C.dlsym(lib, c'$s10Foundation3URLVMa'))(0) }
		data_metadata := data_response.metadata
		url_metadata := url_response.metadata
		entry := u64(C.dlsym(lib, name[1..].str))
		assert entry != 0 && entry == u64(C.dlsym(C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', 2), name[1..].str))
		return DataWriteApi{
			native:           true
			entry:            entry
			code:             code
			data_metadata:    data_metadata
			url_metadata:     url_metadata
			url_constructor:  u64(C.dlsym(lib, c'$s10Foundation3URLV36_unconditionallyBridgeFromObjectiveCyACSo5NSURLCSgFZ'))
			data_constructor: unsafe { DataWriteConstructData(C.dlsym(lib, c'$s10Foundation4DataV11referencingACSo6NSDataCh_tcfC')) }
			data_destroy:     unsafe { DataWriteDestroy(voidptr(read64((read64(data_metadata - 8) & u64(0x0000ffffffffffff)) + 8) & u64(0x0000ffffffffffff))) }
			url_destroy:      unsafe { DataWriteDestroy(voidptr(read64((read64(url_metadata - 8) & u64(0x0000ffffffffffff)) + 8) & u64(0x0000ffffffffffff))) }
			error_release:    unsafe { DataWriteRelease(C.dlsym(core, c'swift_errorRelease')) }
			error_bridge:     unsafe { DataWriteErrorBridge(C.dlsym(lib, c'$s10Foundation22_convertErrorToNSErrorySo0E0Cs0C0_pF')) }
			object_release:   unsafe { DataWriteRelease(C.dlsym(objc, c'objc_release')) }
		}
	}
	entry := runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', name) or { panic(err) }
	assert entry == runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', name) or { panic(err) }
	return DataWriteApi{
		entry:            entry
		code:             code
		private_metadata: metadata
		private_table:    table
		data_constructor: swift_data_reference
		data_destroy:     swift_data_reference_destroy
		url_destroy:      data_write_drop_url
		error_release:    swift_unknown_release
		error_bridge:     swift_error_to_nserror
		object_release:   objc_release
	}
}

fn (api DataWriteApi) url(path string, http bool) SwiftURLWords {
	mut object := u64(0)
	$if macos {
		if api.native {
			object = if http {
				u64(C.CFURLCreateWithBytes(unsafe { nil }, path.str, i64(path.len), 0x08000100, unsafe { nil }))
			} else {
				u64(C.CFURLCreateFromFileSystemRepresentation(unsafe { nil }, path.str, i64(path.len), false))
			}
			mut result := SwiftURLWords{}
			unsafe { DataWriteConstructURL(voidptr(api.code + 128))(api.url_constructor, object, u64(&result)) }
			C.CFRelease(voidptr(object))
			return result
		}
	}
	if http {
		object = objc_allocate(ios_runtime.names['NSURL'])
		text := owned_string(path)
		assert http_url_initialize(object, text)
		objc_release(text)
	} else {
		object = ui_file_url(path)
	}
	owner := swift_heap_allocate(api.private_metadata, 32, 15)
	unsafe { *(&u64(owner + 16)) = object }
	return SwiftURLWords{ owner: owner, table: api.private_table }
}

fn (api DataWriteApi) data(bytes []u8) SwiftDataWords {
	mut object := u64(0)
	$if macos {
		if api.native { object = u64(C.CFDataCreate(unsafe { nil }, bytes.data, i64(bytes.len))) }
	}
	if !api.native { object = cf_data_create(0, u64(bytes.data), i64(bytes.len)) }
	value := api.data_constructor(object)
	api.object_release(object)
	return value
}

fn (api DataWriteApi) call(value SwiftURLWords, data SwiftDataWords, options u64, guard u64) u64 {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1) && C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	address := span + u64(page * 2) - 16
	unsafe { *(&SwiftURLWords(address)) = value }
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	mut result := [u64(0), 0, 0, 0xcafe, 0xbeef]!
	owner := data.second & u64(0x3fffffffffffffff)
	bits := if data.second >> 62 == 1 { read64(owner + 8) } else { u64(0) }
	unsafe { DataWriteProbe(voidptr(api.code))(api.entry, address, options, data.first, data.second, u64(&result[0]), guard) }
	assert result[0] == 0x5020 && result[2] == 0x5022 && result[3] == 0xcafe && result[4] == 0xbeef
	assert read64(address) == value.owner && read64(address + 8) == value.table
	if data.second >> 62 == 1 {
		assert read64(owner + 8) == bits
	}
	assert C.munmap(voidptr(span), page * 3) == 0
	return result[1]
}

fn (api DataWriteApi) get(info u64, key string) u64 {
	$if macos {
		if api.native {
			object := C.CFStringCreateWithBytes(unsafe { nil }, key.str, i64(key.len), 0x08000100, false)
			result := u64(C.CFDictionaryGetValue(voidptr(info), object))
			C.CFRelease(object)
			return result
		}
	}
	header := obj_header(info)
	for i, item in header.keys { if string_text(item) == key { return header.items[i] } }
	return 0
}

fn (api DataWriteApi) text(object u64) string {
	if !api.native { return string_text(object) }
	pointer := data_write_native_send(object, c'UTF8String')
	return unsafe { cstring_to_vstring(&char(pointer)) }
}

fn (api DataWriteApi) error_fields(object u64) (string, i64, u64) {
	if api.native {
		return api.text(data_write_native_send(object, c'domain')), i64(data_write_native_send(object, c'code')), data_write_native_send(object, c'userInfo')
	}
	record := unsafe { &AbiNSError(object) }
	return string_text(record.domain), record.code, record.user_info
}

fn (api DataWriteApi) check_error(error_object u64, expected i64, posix i64, path string, atomically bool) {
	assert error_object != 0
	object := api.error_bridge(error_object)
	domain, code, info := api.error_fields(object)
	assert domain == 'NSCocoaErrorDomain' && code == expected
	if posix != 0 {
		underlying := api.get(info, 'NSUnderlyingError')
		assert underlying != 0
		under_domain, under_code, _ := api.error_fields(underlying)
		assert under_domain == 'NSPOSIXErrorDomain' && under_code == posix
		assert api.text(api.get(info, 'NSFilePath')) == path && api.get(info, 'NSURL') != 0
		if atomically && posix == 2 {
			assert api.get(info, 'NSUserStringVariant') != 0
		}
	} else {
		assert api.get(info, 'NSUnderlyingError') == 0 && api.get(info, 'NSURL') == 0
	}
	if !api.native {
		assert obj_header(object).refs == 2
	}
	api.object_release(object)
	if !api.native {
		assert obj_header(error_object).refs == 1
	}
	api.error_release(error_object)
}

fn data_write_case(api DataWriteApi, root string, guard u64, options u64, count int) {
	bytes := []u8{len: count, init: u8(index * 37 + 5)}
	defer { unsafe { bytes.free() } }
	mut data := api.data(bytes)
	defer { api.data_destroy(u64(unsafe { &data }), api.data_metadata) }
	path := root + '/new'
	defer { unsafe { path.free() } }
	mut url := api.url(path, false)
	defer { api.url_destroy(u64(unsafe { &url }), api.url_metadata) }
	assert api.call(url, data, options, guard) == 0
	actual := os.read_bytes(path) or { panic(err) }
	assert actual == bytes
	unsafe { actual.free() }
	if options == 2 {
		api.check_error(api.call(url, data, options, guard), 516, 17, path, false)
	} else {
		assert C.chmod(path.str, 0o640) == 0
		before := os.stat(path) or { panic(err) }
		empty := SwiftDataWords{ second: u64(0xc000000000000000) }
		assert api.call(url, empty, options, guard) == 0 && os.file_size(path) == 0
		after := os.stat(path) or { panic(err) }
		assert after.mode & 0o777 == 0o640 && (before.inode == after.inode) == (options == 0)
	}
	os.rm(path) or { panic(err) }
}

fn data_write_suite(api DataWriteApi, root string, guard u64) {
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or { panic(err) } }
	for options in [u64(0), 1, 2]! {
		for count in [0, 1, 7, 14, 15, 16, 4096, 65536, 16777216]! {
			data_write_case(api, root, guard, options, count)
		}
		for label in ['missing/child', 'directory', 'notdir/child', 'http']! {
			path := if label == 'http' {
				'https://example.test/fortnite'
			} else {
				root + '/' + label
			}
			if label == 'directory' { os.mkdir_all(path) or { panic(err) } }
			if label == 'notdir/child' {
				os.write_file(root + '/notdir', 'previous') or { panic(err) }
			}
			mut url := api.url(path, label == 'http')
			data := SwiftDataWords{ second: u64(0xc000000000000000) }
			expected := if label == 'http' {
				i64(518)
			} else if label == 'missing/child' {
				i64(4)
			} else if label == 'directory' && options == 2 {
				i64(516)
			} else {
				i64(512)
			}
			posix := if label == 'http' {
				i64(0)
			} else if label == 'missing/child' {
				i64(2)
			} else if label == 'notdir/child' {
				i64(20)
			} else if options == 2 {
				i64(17)
			} else {
				i64(21)
			}
			for _ in 0 .. 4 {
				api.check_error(api.call(url, data, options, guard), expected, posix, path, options == 1)
			}
			api.url_destroy(u64(unsafe { &url }), api.url_metadata)
			if label == 'directory' { os.rmdir(path) or { panic(err) } }
			if label == 'notdir/child' { os.rm(root + '/notdir') or { panic(err) } }
			if label != 'http' { unsafe { path.free() } }
		}
	}
	data_write_links(api, root, guard)
	data_write_slices(api, root, guard)
	path := root + '/concurrent'
	mut workers := []thread{}
	for i in 0 .. 8 { workers << spawn data_write_worker(api, path, guard, i) }
	workers.wait()
	actual := os.read_bytes(path) or { panic(err) }
	assert actual.len == 4096
	for byte in actual {
		assert byte == actual[0]
	}
	unsafe {
		actual.free()
		workers.free()
	}
	os.rm(path) or { panic(err) }
	unsafe { path.free() }
	assert os.ls(root) or { panic(err) } == []string{}
}

fn data_write_links(api DataWriteApi, root string, guard u64) {
	old_mask := C.umask(0o022)
	defer { C.umask(old_mask) }
	for options in [u64(0), 1, 2]! {
		for symlink in [false, true]! {
			target := root + '/target'
			path := root + '/link'
			os.write_file(target, 'previous') or { panic(err) }
			assert C.chmod(target.str, 0o640) == 0
			if symlink {
				os.symlink(target, path) or { panic(err) }
			} else {
				assert C.link(target.str, path.str) == 0
			}
			mut url := api.url(path, false)
			bytes := [u8(5), 9, 0, 255]!
			mut data := api.data(bytes[..])
			result := api.call(url, data, options, guard)
			if options == 2 {
				api.check_error(result, 516, 17, path, false)
			} else {
				assert result == 0 && os.is_link(path) == (symlink && options == 0)
				readback := os.read_bytes(path) or { panic(err) }
				assert readback == bytes[..]
				unsafe { readback.free() }
				if options == 1 {
					assert os.read_file(target) or { panic(err) } == 'previous'
					// Native link replacement attributes differ on APFS and
					// HFS+. Test bytes/identity here; ordinary file modes above.
				} else {
					assert os.file_size(target) == 4
				}
			}
			api.data_destroy(u64(unsafe { &data }), api.data_metadata)
			api.url_destroy(u64(unsafe { &url }), api.url_metadata)
			os.rm(path) or { panic(err) }
			os.rm(target) or { panic(err) }
			unsafe {
				path.free()
				target.free()
			}
		}
	}
}

fn data_write_slices(api DataWriteApi, root string, guard u64) {
	bytes := []u8{len: 4096, init: u8(index * 19 + 7)}
	mut data := api.data(bytes)
	path := root + '/slice'
	mut url := api.url(path, false)
	for range in [[u32(0), 0]!, [u32(7), 21]!, [u32(4095), 4096]!, [u32(4096), 4096]!]! {
		slice := SwiftDataWords{ first: u64(range[0]) | (u64(range[1]) << 32), second: data.second }
		assert api.call(url, slice, 1, guard) == 0
		readback := os.read_bytes(path) or { panic(err) }
		assert readback == bytes[int(range[0])..int(range[1])]
		unsafe { readback.free() }
	}
	api.url_destroy(u64(unsafe { &url }), api.url_metadata)
	api.data_destroy(u64(unsafe { &data }), api.data_metadata)
	os.rm(path) or { panic(err) }
	unsafe {
		bytes.free()
		path.free()
	}
}

fn data_write_worker(api DataWriteApi, path string, guard u64, index int) {
	pool := if api.native { u64(0) } else { objc_pool_push() }
	fill := u8(index + 1)
	bytes := []u8{len: 4096, init: fill}
	mut data := api.data(bytes)
	mut url := api.url(path, false)
	for _ in 0 .. 8 {
		assert api.call(url, data, 1, guard) == 0
	}
	api.url_destroy(u64(unsafe { &url }), api.url_metadata)
	api.data_destroy(u64(unsafe { &data }), api.data_metadata)
	unsafe { bytes.free() }
	if !api.native { objc_pool_pop(pool) }
}

fn data_write_mapping(address u64, mapped bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address + 8 <= start + size && info[0] == C.PROT_READ | C.PROT_EXEC
		} else {
			assert status != 0 || start > address
		}
		if object != 0 {
			assert C.mach_port_deallocate(task, object) == 0
		}
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			fields := line.fields()
			if fields.len < 2 { continue }
			range := fields[0].split('-')
			start := strconv.parse_uint(range[0], 16, 64) or { panic(err) }
			end := strconv.parse_uint(range[1], 16, 64) or { panic(err) }
			if address >= start && address < end {
				found = true
				assert fields[1].starts_with('r-x')
			}
		}
		assert found == mapped
	}
}

fn data_write_reject(guard u64, options u64, first u64, second u64, expected string) {
	if _ := swift_data_write_checked(guard, options, first, second) {
		assert false
	} else {
		assert err.msg().contains(expected), err.msg()
	}
}

fn test_swift_data_write() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && C.mprotect(voidptr(code + u64(page)), page, C.PROT_NONE) == 0
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0503f3, 0xaa0603e8,
		0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0xaa0403e3, 0xd28a0414, 0xd2800015, 0xd28a0456, 0xd63f0200,
		0xa9005674, 0xf9000a76, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	for i, op in [u32(0xaa0003f0), 0xaa0103e0, 0xaa0203e8, 0xd61f0200]! {
		write32(code + 128 + u64(i * 4), op)
	}
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200]! {
		write32(code + 192 + u64(i * 4), op)
		write32(code + 256 + u64(i * 4), op)
	}
	unsafe {
		*(&u64(code + 208)) = u64(voidptr(data_write_witness))
		*(&u64(code + 272)) = u64(voidptr(data_write_url_destroy))
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 280))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := code + u64(page)
	root := os.temp_dir() + '/vinix-swift-data-write-' + os.getpid().str()
	$if macos {
		data_write_suite(data_write_api(true, code, 0, 0), root, guard)
		println('IOS-SWIFT-DATA-WRITE-NATIVE: measured atomic/direct/exclusive file writes, empty/inline/snapshot bytes, replacement inode and permissions, throwing x21 and Cocoa/POSIX errors')
	}
	data_write_reject(guard, 0, 0, 0, 'outside runtime lifetime')
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		words := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		tables := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert words != u64(-1) && tables != u64(-1) && C.mprotect(voidptr(tables + u64(page)), page, C.PROT_NONE) == 0
		metadata := words + 24
		table := tables + u64(page) - 8 - 432
		unsafe {
			*(&u64(metadata - 16)) = code + 256
			*(&u64(metadata + 32)) = 2
			*(&u64(metadata + 40)) = 2
			*(&u64(metadata + 48)) = 0xf00000020
			*(&u64(metadata + 64)) = words + 128
			*(&u64(table + 432)) = code + 192
		}
		assert C.mprotect(voidptr(words), page, C.PROT_READ) == 0 && C.mprotect(voidptr(tables), page, C.PROT_READ) == 0
		for options in [u64(3), 4, 0x10000000, u64(-1)]! {
			data_write_reject(guard, options, 0, 0, 'writing options')
		}
		data_write_reject(guard, 0, 0, u64(15) << 48, 'inline')
		data_write_reject(guard, 0, u64(1) << 32, guard | u64(0x4000000000000000), 'registered')
		data_write_reject(guard, 0, 0, u64(0x8000000000000000), 'large-range')
		api := data_write_api(false, code, metadata, table)
		data_write_suite(api, root, guard)
		arena := ios_runtime.swift_foundation_arena
		assert ios_runtime.swift_heap.len == 0
		data_write_mapping(arena + 1024, true)
		objc_pool_pop(pool)
		assert ios_runtime.live == 0
		objc_stop()
		data_write_mapping(arena + 1024, false)
		assert ios_runtime.swift_foundation_arena == 0 && ios_runtime.live == 0
		assert C.munmap(voidptr(words), page) == 0 && C.munmap(voidptr(tables), page * 2) == 0
		data_write_reject(guard, 0, 0, 0, 'outside runtime lifetime')
	}
	assert C.munmap(voidptr(code), page * 2) == 0
	unsafe { root.free() }
	println('IOS-SWIFT-DATA-WRITE: native-sized empty/inline/snapshot writes up to 16 MiB, atomic replacement, exclusive create, borrowed guarded URL and Data, owned throwing NSError, filesystem error cleanup and two drained/unmapped runtime lifetimes')
}
