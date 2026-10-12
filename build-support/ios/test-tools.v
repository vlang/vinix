// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import iosbuild
import os
import sourcecommand
import sync
import tarcore
import time

#flag -I @DIR
#include "test-abi.h"

$if darwin {
	@[typedef]
	struct C.vinix_ios_test_stat {
		st_mtimespec C.timespec
	}
} $else {
	@[typedef]
	struct C.vinix_ios_test_stat {
		st_mtim C.timespec
	}
}

fn C.vinix_ios_test_stat_call(&char, &C.vinix_ios_test_stat) i32

struct Control {
	root  string
	mutex &sync.Mutex = &sync.Mutex{}
mut:
	compiled       int
	active         int
	maximum        int
	fail_compile   bool
	fail_archive   bool
	bad_header     bool
	no_gallium     bool
	compiler_flags []string
}

fn controlled(argv []string, pointer voidptr) !sourcecommand.Output {
	mut control := unsafe { &Control(pointer) }
	if argv[0].ends_with('/clang++') {
		if argv.last() == '--version' {
			return sourcecommand.Output{ stdout: 'controlled clang++ version\n' }
		}
		control.mutex.@lock()
		control.compiled++
		control.active++
		if control.active > control.maximum { control.maximum = control.active }
		control.compiler_flags = argv.clone()
		fail := control.fail_compile
		control.mutex.unlock()
		time.sleep(10 * time.millisecond)
		control.mutex.@lock()
		control.active--
		control.mutex.unlock()
		if fail { return sourcecommand.Output{ status: 7, stderr: 'controlled compiler failure' } }
		output := argv.last()
		os.write_file(output, 'controlled object: ' + argv[argv.len - 3])!
		return sourcecommand.Output{}
	}
	if argv[0].ends_with('/llvm-ar') {
		assert argv[1] == 'rcs'
		if control.fail_archive {
			return sourcecommand.Output{ status: 8, stderr: 'controlled archive failure' }
		}
		os.write_file(argv[2], 'controlled library: ' + argv[3..].join('\n'))!
		return sourcecommand.Output{}
	}
	if argv[0] == 'controlled-readelf' {
		if argv[1] == '-h' {
			return sourcecommand.Output{
				stdout: if control.bad_header {
					'ELF64 X86-64'
				} else {
					'ELF64 AArch64'
				}
			}
		}
		name := argv.last().all_after_last('/')
		needed := match name {
			'libfreetype.so.6' { ['libcommon.so.1'] }
			'libGLESv2.so.2' { ['libcommon.so.1', 'libEGL.so.1'] }
			'libEGL.so.1' {
				if control.no_gallium {
					['libcommon.so.1']
				} else {
					['libgallium-fixture.so', 'libcommon.so.1']
				}
			}
			'libgallium-fixture.so' { ['libcommon.so.1'] }
			else { []string{} }
		}
		return sourcecommand.Output{ stdout: needed.map('0x1 (NEEDED) Shared library: [' + it + ']').join('\n') }
	}
	if argv[0] == 'curl' {
		os.write_file(argv.last(), 'controlled download')!
		return sourcecommand.Output{}
	}
	return error('unexpected controlled command: ' + argv.str())
}

fn archive(path string, name string, kind u8, data string) ! {
	mut writer := tarcore.create(path)!
	defer { writer.close() }
	writer.add(tarcore.Member{ name: name, kind: kind, size: data.len, linkname: '../../never-follow' }, data.bytes())!
	writer.finish()!
}

fn cases(work string) ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	iosbuild.mkdir(work)!
	before := os.ls('/dev/fd')!.len
	mixed := iosbuild.Tools{ root: root }.combined([os.executable(), '--mixed-streams'])!
	assert mixed.status == 7 && mixed.stdout == 'first\nsecond\nthird\n' && mixed.stderr == ''
	text := os.read_file(root + '/compat/ios/runner/abi/cxx-symbols.txt')!
	header, stub := iosbuild.symbol_outputs(text)!
	assert header.replace('generate-cxx-symbols. */', 'generate-cxx-symbols.py. */') == os.read_file(root + '/compat/ios/runner/abi/cxx-symbols.h')!.replace('generate-cxx-symbols. */', 'generate-cxx-symbols.py. */')
	assert stub == os.read_file(root + '/tests/ios/libcxx.tbd')!
	for invalid in ['_duplicate\n_duplicate\n__Unwind_Resume\n', 'invalid\n__Unwind_Resume\n',
		'_missing_unwind\n'] {
		mut failed := false
		iosbuild.symbol_outputs(invalid) or { failed = true }
		assert failed
	}
	println('SYMBOL OUTPUTS / exact original header and TBD, duplicate/name/missing-unwind controls: PASS')
	archive(work + '/regular.tar', 'prefix/dir/file', `0`, 'literal archive bytes')!
	iosbuild.unpack(work + '/regular.tar', work + '/unpacked', true)!
	assert os.read_file(work + '/unpacked/dir/file')! == 'literal archive bytes'
	archive(work + '/link.tar', 'link', `2`, '')!
	iosbuild.unpack(work + '/link.tar', work + '/ignored', false)!
	assert !os.exists(work + '/ignored/link') && !os.is_link(work + '/ignored/link')
	for index, name in ['../escape', 'prefix/../escape', '/absolute', 'prefix'] {
		path := work + '/unsafe-' + index.str() + '.tar'
		archive(path, name, `0`, 'must not escape')!
		mut failed := false
		iosbuild.unpack(path, work + '/rejected-' + index.str(), index > 0) or { failed = true }
		assert failed
	}
	println('ARCHIVE INPUTS / streaming regular files, skipped links, traversal and empty stripped paths: PASS')
	mut control := Control{ root: root }
	tools := iosbuild.Tools{ root: root, command_hook: controlled, context: &control }
	artifact := iosbuild.Artifact{'fixture', 'https://controlled.invalid/fixture', sha256.hexhash('controlled download')}
	tools.fetch(work + '/download', artifact)!
	assert os.read_file(work + '/download')! == 'controlled download'
	mut failed := false
	tools.fetch(work + '/bad-download', iosbuild.Artifact{'fixture', artifact.url, 'incorrect'}) or { failed = true }
	assert failed && !os.exists(work + '/bad-download')
	assert os.ls(work)!.all(!it.starts_with('.ios-native.'))
	println('FETCH / checksum before publication and private-owner cleanup: PASS')
	build := work + '/cxx'
	iosbuild.mkdir(build)!
	for artifact_input in iosbuild.cxx_artifacts {
		os.cp(root + '/build/ios/cxx/' + artifact_input.name, build + '/' + artifact_input.name)!
	}
	iosbuild.build_cxx(tools, build, root + '/build-aarch64-userland/staging', 'controlled-llvm')!
	count := control.compiled
	assert count == 47 && control.maximum <= 4 && control.active == 0, 'compiled=' + count.str() + ' maximum=' + control.maximum.str() + ' active=' + control.active.str()
	for flag in ['--target=aarch64-linux-musl', '-ffixed-x18', '-D_LIBCPP_ABI_ALTERNATE_STRING_LAYOUT',
		'-std=c++23', '-DVINIX_IOS_CXX_ABI'] {
		assert flag in control.compiler_flags
	}
	assert !control.compiler_flags.any(it.ends_with('/new.cpp') || it.ends_with('/typeinfo.cpp'))
	iosbuild.build_cxx(tools, build, root + '/build-aarch64-userland/staging', 'controlled-llvm')!
	assert control.compiled == count
	object := control.compiler_flags.last()
	os.write_file(object, 'corrupt cached object')!
	iosbuild.build_cxx(tools, build, root + '/build-aarch64-userland/staging', 'controlled-llvm')!
	assert control.compiled == count + 1
	library := os.read_file(build + '/libcxx-ios.a')!
	stamp := os.read_file(build + '/build-stamp')!
	control.fail_archive = true
	failed = false
	iosbuild.build_cxx(tools, build, root + '/build-aarch64-userland/staging', 'controlled-llvm') or { failed = true }
	assert failed && os.read_file(build + '/libcxx-ios.a')! == library && os.read_file(build + '/build-stamp')! == stamp
	control.fail_archive = false
	control.fail_compile = true
	os.write_file(build + '/libcxx/src/string.cpp', os.read_file(build + '/libcxx/src/string.cpp')! + '\n// controlled source mutation\n')!
	failed = false
	iosbuild.build_cxx(tools, build, root + '/build-aarch64-userland/staging', 'controlled-llvm') or { failed = true }
	assert failed && control.active == 0 && os.read_file(build + '/libcxx-ios.a')! == library && os.read_file(build + '/build-stamp')! == stamp
	println('CXX / four real pinned archives, exact ABI patches, bounded workers, warm and corrupt caches, joined failure and old-library preservation: PASS')
	for dir in ['mesa/usr/lib', 'mesa/lib', 'native/usr/lib', 'native/lib'] {
		iosbuild.mkdir(work + '/' + dir)!
	}
	for name in ['libfreetype.so.6', 'libGLESv2.so.2', 'libEGL.so.1', 'libgallium-fixture.so',
		'libcommon.so.1'] {
		os.write_file(work + '/mesa/usr/lib/' + name, 'mesa priority: ' + name)!
		os.chmod(work + '/mesa/usr/lib/' + name, 0o751)!
		os.utime(work + '/mesa/usr/lib/' + name, 1700000000, 1700000001)!
		os.write_file(work + '/native/usr/lib/' + name, 'lower priority: ' + name)!
	}
	metadata_source := work + '/mesa/usr/lib/libfreetype.so.6'
	stamps := [C.timespec{ tv_sec: 1700000000, tv_nsec: 123456789 },
		C.timespec{ tv_sec: 1700000001, tv_nsec: 987654321 }]!
	assert C.utimensat(C.AT_FDCWD, metadata_source.str, &stamps[0], 0) == 0
	attribute := $if darwin { 'com.vinix.ios.native-test' } $else { 'user.vinix.ios.native-test' }
	value := 'preserved library attribute'
	$if darwin {
		assert C.setxattr(metadata_source.str, attribute.str, value.str, usize(value.len), 0, 0) == 0
	} $else {
		assert C.setxattr(metadata_source.str, attribute.str, value.str, usize(value.len), 0) == 0
	}
	sources := iosbuild.stage_gles(tools, work + '/gles', work + '/native', work + '/mesa', 'controlled-readelf')!
	metadata_destination := work + '/gles/usr/lib/vinix/ios-gles/libfreetype.so.6'
	mut information := C.vinix_ios_test_stat{}
	assert C.vinix_ios_test_stat_call(metadata_destination.str, &information) == 0
	$if darwin {
		assert information.st_mtimespec.tv_nsec == 987654321
	} $else {
		assert information.st_mtim.tv_nsec == 987654321
	}
	mut attribute_bytes := []u8{len: value.len}
	attribute_count := $if darwin { C.getxattr(metadata_destination.str, attribute.str, attribute_bytes.data, usize(value.len), 0, 0) } $else { C.getxattr(metadata_destination.str, attribute.str, attribute_bytes.data, usize(value.len)) }
	assert attribute_count == value.len && attribute_bytes.bytestr() == value
	assert sources.len == 5 && sources.values().all(it.starts_with(work + '/mesa/'))
	for name, source in sources {
		destination := work + '/gles/usr/lib/vinix/ios-gles/' + name
		assert os.read_file(destination)! == os.read_file(source)! && os.stat(destination)!.mtime == os.stat(source)!.mtime && (os.stat(destination)!.mode & 0o7777) == 0o751
	}
	assert os.readlink(work + '/gles/usr/lib/vinix/ios-gles/dri/swrast_dri.so')! == '../libgallium-fixture.so'
	iosbuild.stage_gles(tools, work + '/gles', work + '/native', work + '/mesa', 'controlled-readelf')!
	control.bad_header = true
	failed = false
	iosbuild.stage_gles(tools, work + '/bad-gles', work + '/native', work + '/mesa', 'controlled-readelf') or { failed = true }
	assert failed
	control.bad_header = false
	control.no_gallium = true
	failed = false
	iosbuild.stage_gles(tools, work + '/no-gallium', work + '/native', work + '/mesa', 'controlled-readelf') or { failed = true }
	assert failed
	failed = false
	iosbuild.stage_gles(tools, work + '/missing', work + '/missing-native', work + '/missing-mesa', 'controlled-readelf') or { failed = true }
	assert failed
	assert iosbuild.needed_libraries('prefix (NEEDED) [first]\nignored [none]\nprefix (NEEDED) [ignored] [last]') == [
		'first',
		'last',
	]
	println('GLES / dependency cycles, source priority, file bytes/mode/time, internal aliases, repeat, wrong ABI, absent Gallium and missing dependency: PASS')
	assert os.ls('/dev/fd')!.len == before
	os.write_file(work + '/passed', 'PASS\n')!
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--mixed-streams' {
		print('first\n')
		flush_stdout()
		eprint('second\n')
		flush_stderr()
		print('third\n')
		flush_stdout()
		exit(7)
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
