// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import plist

$if macos {
	#include <CoreFoundation/CFPreferences.h>
	fn C.CFPreferencesAppSynchronize(voidptr) u8
	fn C.CFPreferencesSetAppValue(voidptr, voidptr, voidptr)
	fn C.CFPreferencesCopyAppValue(voidptr, voidptr) voidptr
	fn C.CFEqual(voidptr, voidptr) bool
}

type PrefsSync = fn (u64) u8
type PrefsSend = fn (u64, u64, u64, u64) u64
type PrefsProbe = fn (u64, u64, u64, &u64)

fn prefs_send(object u64, selector &char, first u64, second u64) u64 {
	return unsafe { PrefsSend(voidptr(C.ios_objc_builtin))(object, objc_selector(selector), first, second) }
}

fn prefs_emit(code u64) {
	// x0 is the sole argument; x1..x8 contain a protected page address.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0303f3, 0xaa0003f0,
		0xaa0103e0, 0xaa0203e1, 0xaa0203e2, 0xaa0203e3, 0xaa0203e4, 0xaa0203e5,
		0xaa0203e6, 0xaa0203e7, 0xaa0203e8, 0xaa0203f4, 0xd2824695, 0xd63f0200,
		0xa9000660, 0xa9015674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
}

fn prefs_raw(entry u64, domain u64, code u64, guard u64) u64 {
	mut capture := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
	unsafe { PrefsProbe(voidptr(code))(entry, domain, guard, &capture[1]) }
	assert capture[0] == 0xcafe && capture[3] == guard && capture[4] == 0x1234 && capture[5] == 0xbeef
	return capture[1]
}

fn prefs_native_sync(domain u64) u8 {
	$if macos { return C.CFPreferencesAppSynchronize(voidptr(domain)) }
	return 0
}

fn prefs_native_profile(root string, code u64, guard u64) {
	$if macos {
		pool := C.objc_autoreleasePoolPush()
		defer { C.objc_autoreleasePoolPop(pool) }
		path := root + '/native-isolated-domain'
		defer { unsafe { path.free() } }
		domain := C.CFStringCreateWithCString(unsafe { nil }, unsafe { &char(path.str) }, 0x08000100)
		key := C.CFStringCreateWithCString(unsafe { nil }, c'vinix-isolated-key', 0x08000100)
		value := C.CFStringCreateWithCString(unsafe { nil }, c'&<✅🚀>', 0x08000100)
		defer { C.CFRelease(value); C.CFRelease(key); C.CFRelease(domain) }
		entry := u64(unsafe { voidptr(prefs_native_sync) })
		assert prefs_raw(entry, u64(domain), code, guard) == 1
		C.CFPreferencesSetAppValue(key, value, domain)
		assert prefs_raw(entry, u64(domain), code, guard) == 1
		copied := C.CFPreferencesCopyAppValue(key, domain)
		assert copied != unsafe { nil } && C.CFEqual(copied, value)
		C.CFRelease(copied)
		C.CFPreferencesSetAppValue(key, unsafe { nil }, domain)
		assert prefs_raw(entry, u64(domain), code, guard) == 1
		assert C.CFPreferencesCopyAppValue(key, domain) == unsafe { nil }
		println('NATIVE-CF-PREFERENCES-SYNC: isolated empty/staged/removal values and guarded one-argument unsigned-byte ABI compared')
	}
}

fn prefs_read(path string) plist.Value {
	bytes := os.read_bytes(path) or { panic(err) }
	defer { unsafe { bytes.free() } }
	return plist.parse(bytes) or { panic(err) }
}

fn prefs_worker(sync PrefsSync, domain u64, key u64, number u64) {
	for _ in 0 .. 32 {
		assert sync(domain) == 1
		defaults := prefs_send(ios_runtime.names['NSUserDefaults'], c'standardUserDefaults', 0, 0)
		prefs_send(defaults, c'setInteger:forKey:', number, key)
		assert sync(domain) == 1 && prefs_send(defaults, c'integerForKey:', key, 0) == number
	}
}

fn prefs_failures(sync PrefsSync, domain u64, defaults u64, path string) {
	// A failed rename must preserve the target and remove the temporary file.
	os.rm(path) or { panic(err) }
	os.mkdir(path) or { panic(err) }
	assert sync(domain) == 0 && prefs_send(defaults, c'synchronize', 0, 0) == 0
	assert os.is_dir(path) && !os.exists(path + '.tmp')
	os.rmdir(path) or { panic(err) }
	assert sync(domain) == 1
	before := os.read_bytes(path) or { panic(err) }
	defer { unsafe { before.free() } }
	temporary := path + '.tmp'
	defer { unsafe { temporary.free() } }
	os.mkdir(temporary) or { panic(err) }
	// Keep the obstruction nonempty so cleanup cannot remove it.
	obstruction := temporary + '/keep'
	defer { unsafe { obstruction.free() } }
	os.write_file(obstruction, 'fixture') or { panic(err) }
	assert sync(domain) == 0 && os.read_bytes(path) or { panic(err) } == before
	os.rm(obstruction) or { panic(err) }; os.rmdir(temporary) or { panic(err) }
	assert sync(domain) == 1
}

fn test_cf_preferences_sync() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, 3, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page * 2) == 0 }
	prefs_emit(u64(code)); C.__builtin___clear_cache(code, voidptr(u64(code) + 92))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	guard := u64(code) + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	assert cf_preferences_app_synchronize(0) == 0
	old_documents := os.getenv('VINIX_IOS_DOCUMENTS')
	defer { os.setenv('VINIX_IOS_DOCUMENTS', old_documents, true); unsafe { old_documents.free() } }
	root := os.join_path(os.temp_dir(), 'vinix-cf-preferences-' + os.getpid().str())
	assert !os.exists(root)
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or { panic(err) }; unsafe { root.free() } }
	bundle := root + '/DifferentFilename.app'
	info_path := bundle + '/Info.plist'
	os.mkdir(bundle) or { panic(err) }
	os.write_file(info_path, '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.vinix.CFPreferencesFixture</string></dict></plist>') or { panic(err) }
	defer { unsafe { info_path.free(); bundle.free() } }
	documents := root + '/Documents'
	path := documents + '/Library/Preferences/com.vinix.CFPreferencesFixture.plist'
	defer { unsafe { documents.free(); path.free() } }
	lib := '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
	for iteration in 0 .. 2 {
		prefs_native_profile(root, u64(code), guard)
		objc_start()
		ios_runtime.bundle = bundle
		os.setenv('VINIX_IOS_DOCUMENTS', documents, true)
		entry := runtime_symbol(lib, '_CFPreferencesAppSynchronize') or { panic(err) }
		sync := unsafe { PrefsSync(voidptr(entry)) }
		current := read64(runtime_symbol(lib, '_kCFPreferencesCurrentApplication') or { panic(err) })
		domain := owned_string('com.vinix.CFPreferencesFixture')
		alias := owned_string('kCFPreferencesCurrentApplication')
		if iteration == 0 {
			// Cold write failures return false, with a recoverable cached store.
			os.write_file(documents, 'blocked document root') or { panic(err) }
			assert prefs_raw(entry, current, u64(code), guard) == 0
			os.rm(documents) or { panic(err) }
		}
		assert prefs_raw(entry, alias, u64(code), guard) == 1
		defaults := prefs_send(ios_runtime.names['NSUserDefaults'], c'standardUserDefaults', 0, 0)
		assert defaults == ios_runtime.defaults && string_text(obj_header(defaults).fields[3]) == 'com.vinix.CFPreferencesFixture'
		key := owned_string('text'); value := owned_string('&<✅🚀>')
		number_key := owned_string('number'); registration_key := owned_string('registered')
		pool := objc_pool_push()
		if iteration == 0 {
			prefs_send(defaults, c'setObject:forKey:', value, key)
			prefs_send(defaults, c'setInteger:forKey:', u64(i64(-42)), number_key)
		} else {
			assert string_text(prefs_send(defaults, c'stringForKey:', key, 0)) == '&<✅🚀>'
			assert i64(prefs_send(defaults, c'integerForKey:', number_key, 0)) == -42
		}
		registration := objc_allocate(ios_runtime.names['NSMutableDictionary'])
		dictionary_put(registration, registration_key, value)
		prefs_send(defaults, c'registerDefaults:', registration, 0); objc_release(registration)
		assert prefs_send(defaults, c'objectForKey:', registration_key, 0) == value
		assert sync(domain) == 1 && sync(current) == 1
		stored := prefs_read(path)
		assert stored.kind == .dictionary && stored.fields['text'].text == '&<✅🚀>' && stored.fields['number'].integer == -42
		assert 'registered' !in stored.fields
		stored.free()
		objc_pool_pop(pool)
		for text in ['com.vinix.CFPreferencesFixture', 'kCFPreferencesCurrentApplication']! {
			// Mach-O constant-string layout, registered without an ObjHeader.
			mut record := [ios_runtime.names['NSString'], u64(0x7c8), u64(text.str), u64(text.len)]!
			address := u64(unsafe { &record[0] })
			ios_runtime.constants[address] = true
			assert address !in ios_runtime.objects && prefs_raw(entry, address, u64(code), guard) == 1
			ios_runtime.constants.delete(address)
		}
		baseline := ios_runtime.live
		for _ in 0 .. 80 { assert sync(domain) == 1 }
		assert ios_runtime.live == baseline && obj_header(domain).refs == 1 && obj_header(defaults).refs == 1
		for text in ['com.another.application', 'kCFPreferencesAnyApplication', '../escape', '']! {
			other := owned_string(text); assert prefs_raw(entry, other, u64(code), guard) == 0; objc_release(other)
		}
		for invalid in [u64(0), guard, defaults, ios_runtime.names['NSString']]! { assert sync(invalid) == 0 }
		prefs_failures(sync, current, defaults, path)
		mut workers := []thread{}
		mut keys := [8]u64{}
		for i in 0 .. 8 {
			text := 'worker-' + i.str(); keys[i] = owned_string(text); unsafe { text.free() }
			workers << spawn prefs_worker(sync, if i % 2 == 0 { domain } else { current }, keys[i], u64(i + 100))
		}
		workers.wait(); unsafe { workers.free() }
		concurrent := prefs_read(path)
		for i, worker_key in keys { assert concurrent.fields[string_text(worker_key)].integer == i + 100; objc_release(worker_key) }
		concurrent.free()
		if iteration == 1 {
			prefs_send(defaults, c'removeObjectForKey:', key, 0)
			assert sync(current) == 1
			removed := prefs_read(path); assert 'text' !in removed.fields; removed.free()
		}
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libSystem.B.dylib']! {
			if _ := runtime_symbol(library, '_CFPreferencesAppSynchronize') { assert false }
		}
		mut weak := u64(0); objc_store_weak(unsafe { &weak }, defaults)
		for object in [domain, alias, key, value, number_key, registration_key]! { objc_release(object) }
		objc_stop()
		assert weak == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0
		assert sync(current) == 0
	}
	println('IOS-CF-PREFERENCES-SYNC: current/bundle allocated and image-constant domains share standard defaults, atomic persistent plist and registration exclusion, cold/write/rename failure recovery, guarded byte Boolean ABI, concurrent writes, reload across two drained runtimes and explicit unsupported domains')
}
