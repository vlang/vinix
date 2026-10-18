// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type EnvGetter = fn () &&&char
type EnvRead = fn (&char) &char
type EnvSet = fn (&char, &char, i32) i32
type EnvRemove = fn (&char) i32

fn env_read_value(read EnvRead, name &char, expected &char) {
	actual := read(name)
	assert actual != unsafe { nil }
	assert unsafe { C.strcmp(actual, expected) } == 0
}

fn env_reader(get EnvGetter, read EnvRead, address u64) {
	for _ in 0 .. 1000 {
		darwin_set_errno(42)
		assert u64(get()) == address
		assert unsafe { *C.ios_errno_address() } == 42
		env_read_value(read, c'VINIX_CRT_ENV_ALPHA', c'one=two')
	}
}

fn env_child(native bool) {
	mut get := unsafe { EnvGetter(voidptr(libsystem_symbol('/usr/lib/libSystem.B.dylib', '__NSGetEnviron') or { panic(err) })) }
	read := unsafe { EnvRead(voidptr(libsystem_symbol('/usr/lib/libSystem.B.dylib', '_getenv') or { panic(err) })) }
	set := unsafe { EnvSet(voidptr(libsystem_symbol('/usr/lib/libSystem.B.dylib', '_setenv') or { panic(err) })) }
	remove := unsafe { EnvRemove(voidptr(libsystem_symbol('/usr/lib/libSystem.B.dylib', '_unsetenv') or { panic(err) })) }
	if native {
		$if macos {
			handle := C.dlopen(c'/usr/lib/libSystem.B.dylib', 2)
			assert handle != unsafe { nil }
			get = unsafe { EnvGetter(C.dlsym(handle, c'_NSGetEnviron')) }
		} $else {
			panic('native comparison requires macOS')
		}
	}
	assert image_runtime == unsafe { nil }
	cell := get()
	assert cell != unsafe { nil }
	assert u64(cell) == u64(unsafe { &C.environ })
	mut vector := [c'VINIX_CRT_ENV_ALPHA=one=two', c'VINIX_CRT_ENV_EMPTY=',
		c'VINIX_CRT_ENV_UTF8=Привет', unsafe { &char(nil) }]!
	vector_address := unsafe { &&char(&vector[0]) }
	// Only a child replaces environ: libc owns any vectors/strings it grows,
	// and the OS reclaims those allocations when the child exits.
	unsafe { *cell = vector_address }
	assert get() == cell && unsafe { *get() == vector_address }
	env_read_value(read, c'VINIX_CRT_ENV_ALPHA', c'one=two')
	env_read_value(read, c'VINIX_CRT_ENV_EMPTY', c'')
	env_read_value(read, c'VINIX_CRT_ENV_UTF8', c'Привет')
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn env_reader(get, read, u64(cell)) }
	workers.wait()
	for index in 0 .. 32 {
		name := 'VINIX_CRT_ENV_GROW_' + index.str()
		assert set(name.str, c'value', 1) == 0
		assert get() == cell
		env_read_value(read, name.str, c'value')
	}
	assert set(c'VINIX_CRT_ENV_ALPHA', c'ignored', 0) == 0
	env_read_value(read, c'VINIX_CRT_ENV_ALPHA', c'one=two')
	assert set(c'VINIX_CRT_ENV_ALPHA', c'replaced', 1) == 0
	env_read_value(read, c'VINIX_CRT_ENV_ALPHA', c'replaced')
	assert remove(c'VINIX_CRT_ENV_ALPHA') == 0
	assert read(c'VINIX_CRT_ENV_ALPHA') == unsafe { nil }
	unsafe { *cell = &&char(nil) }
	assert get() == cell && unsafe { *get() == nil }
	assert read(c'VINIX_CRT_ENV_UTF8') == unsafe { nil }
	// Native Mac setenv requires a vector even when it contains no entries.
	mut empty := [unsafe { &char(nil) }]!
	unsafe { *cell = &empty[0] }
	assert set(c'VINIX_CRT_ENV_REPOPULATED', c'ok', 1) == 0
	env_read_value(read, c'VINIX_CRT_ENV_REPOPULATED', c'ok')
	assert get() == cell && image_runtime == unsafe { nil }
	println('IOS-CRT-ENVIRON-CHILD: live cell and libc vector mutations verified')
	C._Exit(0)
}

fn test_crt_environ() {
	mode := os.getenv('VINIX_IOS_CRT_ENV_CHILD')
	if mode != '' { env_child(mode == 'native') }
	entry := libsystem_symbol('/usr/lib/libSystem.B.dylib', '__NSGetEnviron') or { panic(err) }
	assert entry == u64(unsafe { voidptr(darwin_ns_get_environ) })
	assert runtime_symbol('/usr/lib/libSystem.B.dylib', '__NSGetEnviron') or { panic(err) } == entry
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib',
		'/System/Library/Frameworks/Foundation.framework/Foundation']! {
		if _ := runtime_symbol(library, '__NSGetEnviron') {
			assert false
		}
	}
	cell := darwin_ns_get_environ()
	initial := unsafe { *cell }
	for _ in 0 .. 2 {
		for context in ['adapter', 'native']! {
			$if !macos {
				if context == 'native' { continue }
			}
			mut child := os.new_process(os.executable())
			child.set_environment({
				'VINIX_IOS_CRT_ENV_CHILD': context
			})
			child.set_redirect_stdio_merged()
			child.run()
			output := child.stdout_slurp()
			child.wait()
			code := child.code
			child.close()
			assert code == 0, context + ': ' + output
			assert output == 'IOS-CRT-ENVIRON-CHILD: live cell and libc vector mutations verified\n'
			assert darwin_ns_get_environ() == cell && unsafe { *cell == initial }
		}
	}
	println('IOS-CRT-ENVIRON: scoped triple-pointer C ABI, stable writable libc alias, fresh child isolation, UTF-8/empty/equal values, vector growth, overwrite, removal, null/empty vector replacement, repopulation, eight readers and unchanged errno')
}
