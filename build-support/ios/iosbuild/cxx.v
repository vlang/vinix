// SPDX-License-Identifier: GPL-2.0-or-later
module iosbuild

import cachecli
import cachekey
import crypto.sha256
import json2
import os
import tarstream

pub struct Artifact {
pub:
	name   string
	url    string
	sha256 string
}

pub const cxx_artifacts = [
	Artifact{'libcxx.src.tar.xz', 'https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.7/libcxx-19.1.7.src.tar.xz', 'b736109650ffc750dbdc506483347b3713ded9d0300f48432b820ad66b6a9052'},
	Artifact{'libcxx-dev.apk', 'https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64/libc++-dev-19.1.4-r1.apk', '0ff7de0cec1c2b94b3f3b82289ea8ee0d0a8efeba181124b4d3533e7d907afbc'},
	Artifact{'libcxx-static.apk', 'https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64/libc++-static-19.1.4-r1.apk', '3cb6dd7b4765c9fd46104e4be87cf3b3b36f3d100c06c2a10229f45719b5b8c0'},
	Artifact{'llvm-unwind.apk', 'https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64/llvm-libunwind-static-19.1.4-r1.apk', '472f47d99b2fff39b10b6404491fdb155ce9a8d52bb0e7201a6abbd68b1303e7'},
]

pub fn (tools Tools) fetch(path string, artifact Artifact) ! {
	if !os.exists(path) {
		work := private_directory(parent(path))!
		defer { os.rmdir_all(work) or {} }
		download := work + '/download'
		tools.checked(['curl', '-fL', '--connect-timeout', '120', '--speed-time', '120', '--speed-limit',
			'1', artifact.url, '-o', download])!
		if digest(download)! != artifact.sha256 { return error('checksum mismatch: ' + path) }
		cachecli.replace_file(download, path)!
	}
	if digest(path)! != artifact.sha256 { return error('checksum mismatch: ' + path) }
}

pub fn unpack(archive string, destination string, strip_first bool) ! {
	mut reader := tarstream.open_concatenated(archive)!
	defer { reader.close() }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		if !member.regular() { continue }
		mut parts := member.name.split('/').filter(it != '' && it != '.')
		if strip_first && parts.len > 0 { parts = parts[1..].clone() }
		if parts.len == 0 || '..' in parts || member.name.starts_with('/') || member.name.contains('\x00') {
			return error('unsafe archive path: ' + member.name)
		}
		output := destination + '/' + parts.join('/')
		mkdir(parent(output))!
		mut file := os.create(output)!
		mut failed := ''
		for {
			count := reader.read(mut buffer) or {
				failed = err.msg()
				break
			}
			if count == 0 { break }
			unsafe {
				file.write_full_buffer(buffer.data, usize(count)) or {
					failed = err.msg()
					break
				}
			}
		}
		file.close()
		if failed != '' { return error(failed) }
	}
}

pub fn patch_headers(headers string, ctype string) !string {
	locale := headers + '/__locale'
	text := os.read_file(locale)!
	needle := 'public:\n#if defined(_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE)\n'
	if text.count(needle) != 1 { return error('libc++ ctype_base header changed') }
	thread_header := headers + '/__thread/support/pthread.h'
	thread_text := os.read_file(thread_header)!
	old_tls := 'typedef pthread_key_t __libcpp_tls_key;'
	old_create := 'return pthread_key_create(__key, __at_exit);'
	if thread_text.count(old_tls) != 1 || thread_text.count(old_create) != 1 {
		return error('libc++ TLS key header changed')
	}
	tls := thread_text.replace(old_tls, 'typedef uint64_t __libcpp_tls_key;').replace(old_create, 'pthread_key_t native_key; int result = pthread_key_create(&native_key, __at_exit); if (!result) *__key = native_key; return result;')
	os.write_file(locale, text.replace(needle, 'public:\n' + ctype))!
	os.write_file(thread_header, tls)!
	return tls
}

pub fn cxx_flags(root string, output string, sysroot string, llvm string) []string {
	return [llvm + '/clang++', '--target=aarch64-linux-musl', '--sysroot=' + sysroot, '-I',
		output + '/libcxx/src', '-idirafter', root + '/build-aarch64-userland/sysroot/include',
		'-nostdinc++', '-isystem', output + '/sysroot/usr/include/c++/v1', '-include',
		root + '/build-support/ios/cxx-abi.h', '-D_LIBCPP_BUILDING_LIBRARY',
		'-DLIBCXX_BUILDING_LIBCXXABI', '-D_LIBCPP_ABI_ALTERNATE_STRING_LAYOUT', '-DVINIX_IOS_CXX_ABI',
		'-std=c++23', '-O2', '-fPIC', '-ffixed-x18', '-fvisibility=hidden',
		'-fvisibility-inlines-hidden', '-c']
}

fn compile_one(tools Tools, path string, objects string, flags []string, cached map[string]string) !string {
	name := path.all_after_last('/').all_before_last('.')
	output := objects + '/' + name + '.o'
	if expected := cached[output] {
		if os.is_file(output) && digest(output)! == expected { return output }
	}
	result := tools.combined([...flags, path, '-o', output])!
	os.write_file(objects + '/' + name + '.log', result.stdout + result.stderr)!
	if result.status != 0 {
		return error(path.all_after_last('/') + ':\n' + result.stdout + result.stderr)
	}
	return output
}

pub fn build_cxx(tools Tools, output string, sysroot string, llvm string) ! {
	mkdir(output)!
	for artifact in cxx_artifacts { tools.fetch(output + '/' + artifact.name, artifact)! }
	source := output + '/libcxx'
	if !os.is_file(source + '/src/string.cpp') {
		unpack(output + '/libcxx.src.tar.xz', source, true)!
	}
	for name in ['libcxx-dev.apk', 'libcxx-static.apk', 'llvm-unwind.apk'] {
		unpack(output + '/' + name, output + '/sysroot', false)!
	}
	ctype := os.read_file(tools.root + '/build-support/ios/cxx-ctype.inc')!
	tls := patch_headers(output + '/sysroot/usr/include/c++/v1', ctype)!
	objects := output + '/objects'
	mkdir(objects)!
	flags := cxx_flags(tools.root, output, sysroot, llvm)
	version := tools.checked([llvm + '/clang++', '--version'])!
	mut sources := []string{}
	for directory in [source + '/src', source + '/src/ryu'] {
		for name in os.ls(directory)! {
			if name.ends_with('.cpp') && (directory.ends_with('/ryu') || name.all_before_last('.') !in [
				'new',
				'typeinfo',
			]) {
				sources << directory + '/' + name
			}
		}
	}
	mut source_hashes := map[string]string{}
	mut names := map[string]bool{}
	for path in sources {
		name := path.all_after_last('/').all_before_last('.')
		if name in names { return error('duplicate C++ object name: ' + name) }
		names[name] = true
		source_hashes[path] = digest(path)!
	}
	abi_path := tools.root + '/build-support/ios/cxx-abi.h'
	abi := os.read_file(abi_path)!
	inputs := cachekey.tree_key([source + '/src', output + '/sysroot/usr/include/c++/v1'], false, 'vinix-ios-cxx-inputs-v1')!
	stamp := sha256.hexhash('vinix-ios-cxx-native-v2\n' + json2.encode(flags) + version + abi + ctype + tls + inputs)
	stamp_file := output + '/build-stamp'
	mut cached := map[string]string{}
	if (os.read_file(stamp_file) or { '' }) == stamp {
		cached = json2.decode[map[string]string](os.read_file(output + '/object-sha256.json') or { '' }) or { map[string]string{} }
	}
	mut compiled := []string{}
	mut offset := 0
	for offset < sources.len {
		cachecli.checkpoint()!
		mut pending := []thread !string{}
		for offset < sources.len && pending.len < 4 {
			pending << spawn compile_one(tools, sources[offset], objects, flags, cached)
			offset++
		}
		mut failure := ''
		for task in pending {
			object := task.wait() or {
				if failure == '' { failure = err.msg() }
				continue
			}
			compiled << object
		}
		if failure != '' { return error(failure) }
	}
	for path, expected in source_hashes {
		if digest(path)! != expected {
			return error('C++ sources changed during compilation: ' + path)
		}
	}
	if cachekey.tree_key([source + '/src', output + '/sysroot/usr/include/c++/v1'], false, 'vinix-ios-cxx-inputs-v1')! != inputs || os.read_file(abi_path)! != abi || os.read_file(tools.root + '/build-support/ios/cxx-ctype.inc')! != ctype {
		return error('C++ compiler inputs changed during compilation')
	}
	library := output + '/libcxx-ios.a'
	work := private_directory(output)!
	defer { os.rmdir_all(work) or {} }
	tools.checked([llvm + '/llvm-ar', 'rcs', work + '/libcxx-ios.a', ...compiled])!
	cachecli.replace_file(work + '/libcxx-ios.a', library)!
	mut hashes := map[string]string{}
	for object in compiled { hashes[object] = digest(object)! }
	publish(output + '/object-sha256.json', json2.encode(hashes, prettify: true))!
	publish(stamp_file, stamp)!
	println('Built ' + library)
}

pub fn build_cxx_cli(tools Tools, argv []string) !int {
	args := cachecli.arguments(argv, ['--output', '--sysroot'], [], [], 0, 0, 'Build musl libc++ with the Apple ARM64 string and mbstate_t ABI.\nUsage: build-cxx [--output DIR --sysroot DIR]') or { return error_with_code(err.msg(), 2) }
	output := resolved(args.value('--output', tools.root + '/build/ios/cxx'))!
	sysroot := resolved(args.value('--sysroot', tools.root + '/build-aarch64-userland/staging'))!
	build_cxx(tools, output, sysroot, os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' })!
	return 0
}
