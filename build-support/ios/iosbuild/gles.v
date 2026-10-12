// SPDX-License-Identifier: GPL-2.0-or-later
module iosbuild

import cachecli
import json2
import os

#flag -I @DIR
#include "copy_abi.h"

$if darwin {
	@[typedef]
	struct C.vinix_ios_file_stat {
		st_mode      u32
		st_atimespec C.timespec
		st_mtimespec C.timespec
		st_flags     u32
	}
} $else {
	@[typedef]
	struct C.vinix_ios_file_stat {
		st_mode u32
		st_atim C.timespec
		st_mtim C.timespec
	}
}

fn C.vinix_ios_file_stat_call(&char, &C.vinix_ios_file_stat) i32
fn C.utimensat(i32, &char, &C.timespec, i32) i32

$if darwin {
	fn C.listxattr(&char, &char, usize, i32) isize
	fn C.getxattr(&char, &char, voidptr, usize, u32, i32) isize
	fn C.setxattr(&char, &char, voidptr, usize, u32, i32) i32
	fn C.chflags(&char, u32) i32
} $else {
	fn C.listxattr(&char, &char, usize) isize
	fn C.getxattr(&char, &char, voidptr, usize) isize
	fn C.setxattr(&char, &char, voidptr, usize, i32) i32
}

fn copy_xattrs(source string, destination string) ! {
	count := $if darwin { C.listxattr(source.str, unsafe { nil }, 0, 0) } $else { C.listxattr(source.str, unsafe { nil }, 0) }
	if count < 0 {
		if C.errno in [C.ENOTSUP, C.ENODATA, C.EINVAL] { return }
		return os.error_posix()
	}
	if count == 0 { return }
	mut names := []u8{len: int(count)}
	actual := $if darwin { C.listxattr(source.str, &char(names.data), usize(count), 0) } $else { C.listxattr(source.str, &char(names.data), usize(count)) }
	if actual < 0 { return os.error_posix() }
	for name in names[..int(actual)].bytestr().split('\x00').filter(it != '') {
		size := $if darwin { C.getxattr(source.str, name.str, unsafe { nil }, 0, 0, 0) } $else { C.getxattr(source.str, name.str, unsafe { nil }, 0) }
		if size < 0 {
			if C.errno in [C.EPERM, C.ENOTSUP, C.ENODATA, C.EINVAL] { continue }
			return os.error_posix()
		}
		mut value := []u8{len: int(size)}
		read := $if darwin { C.getxattr(source.str, name.str, value.data, usize(size), 0, 0) } $else { C.getxattr(source.str, name.str, value.data, usize(size)) }
		if read < 0 { return os.error_posix() }
		written := $if darwin { C.setxattr(destination.str, name.str, value.data, usize(read), 0, 0) } $else { C.setxattr(destination.str, name.str, value.data, usize(read), 0) }
		if written != 0 && C.errno !in [C.EPERM, C.ENOTSUP, C.ENODATA, C.EINVAL] {
			return os.error_posix()
		}
	}
}

pub fn copy_library(source string, destination string) ! {
	if os.stat(source)!.get_filetype() != .regular {
		return error('graphics input is not a regular file: ' + source)
	}
	os.cp(source, destination)!
	mut information := C.vinix_ios_file_stat{}
	if C.vinix_ios_file_stat_call(source.str, &information) != 0 { return os.error_posix() }
	mut stamps := []C.timespec{}
	$if darwin {
		stamps << information.st_atimespec
		stamps << information.st_mtimespec
	} $else {
		stamps << information.st_atim
		stamps << information.st_mtim
	}
	if C.utimensat(C.AT_FDCWD, destination.str, stamps.data, 0) != 0 { return os.error_posix() }
	copy_xattrs(source, destination)!
	os.chmod(destination, int(information.st_mode & 0o7777))!
	$if darwin {
		if C.chflags(destination.str, information.st_flags) != 0 && C.errno !in [
			C.ENOTSUP,
			C.EOPNOTSUPP,
		] {
			return os.error_posix()
		}
	}
}

pub fn needed_libraries(text string) []string {
	mut result := []string{}
	for line in text.split_into_lines() {
		if !line.contains('(NEEDED)') { continue }
		rest := line.all_after('(NEEDED)')
		if rest.contains('[') && rest.all_after_last('[').contains(']') {
			result << rest.all_after_last('[').all_before(']')
		}
	}
	return result
}

fn alias_file(path string, target string) ! {
	os.rm(path) or { if os.is_link(path) || os.exists(path) { return err } }
	os.symlink(target, path)!
}

pub fn stage_gles(tools Tools, output string, sysroot string, mesa string, readelf string) !map[string]string {
	library := output + '/usr/lib/vinix/ios-gles'
	mkdir(library)!
	mut directories := []string{}
	for root in [mesa, sysroot] {
		for name in ['usr/lib', 'lib'] { directories << root + '/' + name }
	}
	mut pending := ['libEGL.so.1', 'libGLESv2.so.2', 'libfreetype.so.6']
	mut sources := map[string]string{}
	for pending.len > 0 {
		name := pending.pop()
		if name in sources { continue }
		if name == '' || name.contains('/') || name.contains('\x00') {
			return error('invalid graphics dependency: ' + name)
		}
		mut source := ''
		for directory in directories {
			candidate := directory + '/' + name
			if os.is_file(candidate) {
				source = resolved(candidate)!
				break
			}
		}
		if source == '' {
			return error('Missing ARM64 graphics dependency ' + name + '; build the X11/userland sysroots')
		}
		header := tools.checked([readelf, '-h', source])!
		if !header.contains('AArch64') || !header.contains('ELF64') {
			return error('Not an ARM64 ELF library: ' + source)
		}
		dynamic := tools.checked([readelf, '-d', source])!
		pending << needed_libraries(dynamic)
		sources[name] = source
		copy_library(source, library + '/' + name)!
	}
	gallium := sources.keys().filter(it.starts_with('libgallium-'))
	if gallium.len == 0 { return error('Mesa EGL must use the shared Gallium driver build') }
	mkdir(library + '/dri')!
	alias_file(library + '/dri/swrast_dri.so', '../' + gallium[0])!
	for pair in [['libEGL.so', 'libEGL.so.1'], ['libGLESv2.so', 'libGLESv2.so.2'],
		['libfreetype.so', 'libfreetype.so.6'], ['ld-musl-aarch64.so.1', 'libc.musl-aarch64.so.1']] {
		alias_file(library + '/' + pair[0], pair[1])!
	}
	publish(library + '/sources.json', json2.encode(sources, prettify: true) + '\n')!
	println('Staged ' + sources.len.str() + ' ARM64 graphics libraries in ' + library)
	return sources
}

pub fn gles_cli(tools Tools, argv []string) !int {
	args := cachecli.arguments(argv, ['--output', '--sysroot', '--mesa-sysroot', '--readelf'], [], [], 0, 0, 'Stage a private ARM64 Mesa runtime without replacing desktop libraries.\nUsage: stage-gles --output DIR --sysroot DIR --mesa-sysroot DIR --readelf TOOL') or { return error_with_code(err.msg(), 2) }
	output := args.required('--output') or { return error_with_code(err.msg(), 2) }
	sysroot := args.required('--sysroot') or { return error_with_code(err.msg(), 2) }
	mesa := args.required('--mesa-sysroot') or { return error_with_code(err.msg(), 2) }
	readelf := args.required('--readelf') or { return error_with_code(err.msg(), 2) }
	stage_gles(tools, output, sysroot, mesa, readelf)!
	return 0
}
