// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os
import time

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.atexit(ImageExit) i32

type IEExit = fn (i32)

__global ie_key = u64(0)

fn ie_libc_callback() {
	assert C.write(1, c'L', 1) == 1
}

fn ie_image_callback() {
	assert C.write(1, c'I', 1) == 1
}

fn ie_cxa_callback(_ voidptr) {
	assert C.write(1, c'D', 1) == 1
}

fn ie_tls_callback(_ voidptr) {
	assert C.write(1, c'T', 1) == 1
}

fn ie_worker(entry u64, status i32) {
	assert C.pthread_setspecific(ie_key, c'tls') == 0
	unsafe { IEExit(voidptr(entry))(status) }
	C._exit(112)
}

fn ie_tls_worker() {
	assert C.pthread_setspecific(ie_key, c'tls') == 0
}

fn ie_child(mode string, status i32, path string) {
	stream := C.fopen(path.str, c'wb')
	assert stream != unsafe { nil }
	mut buffer := [4096]char{}
	assert C.setvbuf(stream, unsafe { &buffer[0] }, C._IOFBF, 4096) == 0
	assert C.fwrite(c'unflushed', 1, 9, stream) == 9
	assert C.atexit(ie_libc_callback) == 0
	assert C.ios_key_create(unsafe { voidptr(&ie_key) }, unsafe { voidptr(ie_tls_callback) }) == 0
	assert C.pthread_setspecific(ie_key, c'tls') == 0
	if mode != 'uninitialized' {
		image_runtime_start(macho.Image{}, macho.Layout{}, 0)
		assert image_atexit(ie_image_callback) == 0
		assert image_cxa_atexit(ie_cxa_callback, unsafe { nil }, 1) == 0
	}
	mut entry := libsystem_symbol('/usr/lib/libSystem.B.dylib', '__Exit') or { panic(err) }
	if mode.starts_with('native') {
		$if macos {
			handle := C.dlopen(c'/usr/lib/libSystem.B.dylib', 2)
			assert handle != unsafe { nil }
			entry = u64(C.dlsym(handle, c'_Exit'))
			assert entry != 0
		} $else {
			panic('native Darwin comparison requires macOS')
		}
	}
	assert C.write(1, c'R', 1) == 1
	if mode == 'regular-control' { C.exit(int(status)) }
	if mode == 'image-control' { image_exit(int(status)) }
	if mode == 'tls-control' {
		worker := spawn ie_tls_worker()
		worker.wait()
		darwin_c11_exit(status)
	}
	if mode.ends_with('worker') {
		worker := spawn ie_worker(entry, status)
		// Bound a broken implementation that exits only the calling thread.
		time.sleep(2 * time.second)
		C._exit(111)
		worker.wait()
	} else {
		unsafe { IEExit(voidptr(entry))(status) }
	}
	C._exit(112)
}

fn ie_case(directory string, mode string, status i32) {
	path := directory + '/buffer'
	mut child := os.new_process(os.executable())
	mut environment := os.environ()
	environment['VINIX_IOS_IMMEDIATE_EXIT_MODE'] = mode
	environment['VINIX_IOS_IMMEDIATE_EXIT_STATUS'] = status.str()
	environment['VINIX_IOS_IMMEDIATE_EXIT_FILE'] = path
	child.set_environment(environment)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	code := child.code
	child.close()
	assert code == int(u32(status) & 255), 'mode=${mode} status=${status} observed=${code}: ' + output
	expected := match mode {
		'regular-control' { 'RL' }
		'image-control' { 'RDIL' }
		'tls-control' { 'RT' }
		else { 'R' }
	}
	assert output == expected, mode + ': ' + output
	assert os.read_file(path) or { panic(err) } == if mode in ['regular-control', 'image-control']! {
		'unflushed'
	} else {
		''
	}
	os.rm(path) or { panic(err) }
}

fn test_immediate_exit() {
	mode := os.getenv('VINIX_IOS_IMMEDIATE_EXIT_MODE')
	if mode != '' {
		ie_child(mode, i32(os.getenv('VINIX_IOS_IMMEDIATE_EXIT_STATUS').int()), os.getenv('VINIX_IOS_IMMEDIATE_EXIT_FILE'))
		C._exit(112)
	}
	assert image_runtime == unsafe { nil }
	entry := libsystem_symbol('/usr/lib/libSystem.B.dylib', '__Exit') or { panic(err) }
	assert entry == u64(unsafe { voidptr(darwin_c11_exit) })
	assert runtime_symbol('/usr/lib/libSystem.B.dylib', '__Exit') or { panic(err) } == entry
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib',
		'/System/Library/Frameworks/Foundation.framework/Foundation']! {
		if _ := runtime_symbol(library, '__Exit') {
			assert false
		}
	}
	directory := os.join_path(os.temp_dir(), 'vinix-ios-exit-' + os.getpid().str())
	os.mkdir(directory)!
	defer { os.rmdir_all(directory) or { panic(err) } }
	for context in ['main', 'worker']! {
		for status in [i32(0), 37, 255, 256, -1, -2147483647 - 1, 2147483647]! {
			ie_case(directory, context, status)
			$if macos {
				ie_case(directory, 'native-' + context, status)
			}
		}
	}
	for control in ['regular-control', 'image-control', 'tls-control', 'uninitialized']! {
		ie_case(directory, control, 37)
	}
	assert image_runtime == unsafe { nil }
	println('IOS-IMMEDIATE-EXIT: scoped signed 32-bit C ABI, low-byte status, no return, skipped libc/image/C++/TLS callbacks and buffered stdio, positive cleanup controls, whole-process worker termination and uninitialized runtime')
}
