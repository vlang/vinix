// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import crypto.sha256
import os
import time

#include <sys/resource.h>

struct C.rlimit {
	rlim_cur u64
	rlim_max u64
}

fn C.fork() i32
fn C.setrlimit(int, &C.rlimit) int
fn C.waitpid(i32, &i32, int) i32
fn C._exit(int)

fn firmware_test_dir() string {
	dir := os.join_path(os.temp_dir(), 'vinix-firmware-' + os.getpid().str() + '-' + time.sys_mono_now().str())
	os.mkdir(dir) or { panic(err.msg()) }
	return dir
}

fn test_firmware_copy_preserves_holes_boundaries_and_private_writes() {
	dir := firmware_test_dir()
	defer { os.rmdir_all(dir) or {} }
	source := dir + '/template'
	destination := dir + '/variables'
	mut bytes := []u8{len: 1048576 + 7}
	for offset in [0, 65535, 65536, 196607, 524288, 1048576 + 2] { bytes[offset] = 0x7a }
	os.write_file_array(source, bytes) or { panic(err.msg()) }
	before := sha256.sum(bytes).hex()
	copy_firmware_variables(source, destination) or { panic(err.msg()) }
	actual := os.read_bytes(destination) or { panic(err.msg()) }
	assert actual == bytes && os.file_size(destination) == u64(bytes.len)
	mut info := C.stat{}
	assert unsafe { C.stat(destination.str, &info) } == 0
	assert info.st_mode & 0o777 == 0o600
	// On a sparse filesystem the copied zero runs consume no data blocks.
	$if macos || linux {
		assert info.st_blocks * 512 < i64(bytes.len) / 2
	}
	fd := C.open(destination.str, C.O_WRONLY)
	assert fd >= 0 && C.lseek(fd, 524288, C.SEEK_SET) == 524288
	assert C.write(fd, c'GUEST', 5) == 5 && C.close(fd) == 0
	assert sha256.sum(os.read_bytes(source) or { panic(err.msg()) }).hex() == before
	assert sha256.sum(os.read_bytes(destination) or { panic(err.msg()) }).hex() != before
}

fn test_firmware_copy_preserves_empty_and_zero_tail_lengths() {
	dir := firmware_test_dir()
	defer { os.rmdir_all(dir) or {} }
	for size in [0, 1, 65536, 65537, 131079] {
		source := dir + '/template-' + size.str()
		destination := dir + '/variables-' + size.str()
		bytes := []u8{len: size}
		os.write_file_array(source, bytes) or { panic(err.msg()) }
		copy_firmware_variables(source, destination) or { panic(err.msg()) }
		assert os.file_size(destination) == u64(size)
		assert os.read_bytes(destination) or { panic(err.msg()) } == bytes
	}
}

fn test_firmware_copy_refuses_existing_files_and_links_without_changes() {
	dir := firmware_test_dir()
	defer { os.rmdir_all(dir) or {} }
	source := dir + '/template'
	destination := dir + '/existing'
	link := dir + '/link'
	os.write_file(source, 'TEMPLATE') or { panic(err.msg()) }
	os.write_file(destination, 'EXISTING') or { panic(err.msg()) }
	copy_firmware_variables(source, destination) or {
		assert os.read_file(destination) or { panic(err.msg()) } == 'EXISTING'
		os.symlink(destination, link) or { panic(err.msg()) }
		copy_firmware_variables(source, link) or {
			assert os.is_link(link) && os.read_file(destination) or { panic(err.msg()) } == 'EXISTING'
			assert os.read_file(source) or { panic(err.msg()) } == 'TEMPLATE'
			return
		}
		panic('copied onto an existing link')
	}
	panic('copied onto an existing file')
}

fn test_firmware_copy_refuses_missing_and_nonregular_templates() {
	dir := firmware_test_dir()
	defer { os.rmdir_all(dir) or {} }
	destination := dir + '/variables'
	copy_firmware_variables(dir + '/missing', destination) or {
		assert !os.exists(destination)
		copy_firmware_variables(dir, destination) or {
			assert !os.exists(destination)
			return
		}
		panic('copied a directory')
	}
	panic('copied a missing template')
}

fn test_firmware_copy_removes_partial_image_after_real_size_failure() {
	dir := firmware_test_dir()
	defer { os.rmdir_all(dir) or {} }
	source := dir + '/template'
	destination := dir + '/variables'
	os.write_file_array(source, []u8{len: 65536}) or { panic(err.msg()) }
	child := C.fork()
	assert child >= 0
	if child == 0 {
		unsafe { C.signal(C.SIGXFSZ, C.SIG_IGN) }
		limits := C.rlimit{ rlim_cur: 1024, rlim_max: 1024 }
		if C.setrlimit(C.RLIMIT_FSIZE, &limits) != 0 { C._exit(2) }
		copy_firmware_variables(source, destination) or {
			if os.exists(destination) { C._exit(3) }
			C._exit(0)
		}
		C._exit(4)
	}
	mut status := i32(0)
	assert C.waitpid(child, &status, 0) == child && status == 0
	assert !os.exists(destination) && os.file_size(source) == 65536
}
