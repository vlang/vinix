// SPDX-License-Identifier: GPL-2.0-or-later
// Current-V paired broker/transport build and real protocol host regressions.
module main

import crypto.sha256
import json2
import os

fn run(argv []string, log string) !string {
	os.write_file(log + '.argv.json', json2.encode(argv, prettify: true))!
	result := os.exec(argv)
	os.write_file(log, result.output)!
	os.write_file(log + '.exit', result.exit_code.str())!
	if result.exit_code != 0 { return error('command failed: ' + log) }
	return result.output
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free(); free(hash) } }
	mut bytes := []u8{len: 65536}
	defer { unsafe { bytes.free() } }
	for {
		n := file.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(bytes[..n])!
	}
	mut checksum := []u8{len: 32}
	defer { unsafe { checksum.free() } }
	hash.checksum_into(mut checksum)
	return checksum.hex()
}

fn capture(root string, paths []string) !map[string]string {
	mut hashes := map[string]string{}
	for path in paths {
		if path in hashes { continue }
		hashes[path] = digest(path)!
		target := root + '/inputs/' + path.trim_left('/')
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
		if digest(target)! != hashes[path] { return error('copy differs: ' + path) }
	}
	os.write_file(root + '/input-sha256.json', json2.encode(hashes, prettify: true))!
	return hashes
}

fn unchanged(hashes map[string]string) ! {
	for path, expected in hashes {
		if digest(path)! != expected { return error('input changed: ' + path) }
	}
}

fn execute(mode string, root string) ! {
	if mode !in ['plain', 'asan', 'build'] || os.exists(root) { return error('valid mode and fresh output required') }
	os.mkdir_all(root)!
	repo := os.real_path(os.dir(@FILE) + '/../..')
	v := '/Users/alex/code/v/v'
	cross := '/opt/homebrew/bin/aarch64-linux-musl-gcc'
	os.setenv('VEXE', v, true)
	os.chdir(repo)!
	common := [v, '-new-compiler', '-no-parallel', '-nocache', '-gc', 'none', '-path', '@vlib|' + repo + '/build-support/android|' + repo + '/tests/native-android-ws']
	broker := repo + '/build-support/android/native-account-broker.v'
	client := repo + '/build-support/android/accountclient'
	mut inputs := [v, os.real_path(@FILE)]
	sources := [broker, client, repo + '/build-support/android/native-run.v']
	for source in sources {
		mut command := common.clone()
		if mode == 'build' { command << ['-os', 'linux', '-arch', 'arm64', '-cc', cross] }
		if source == client {
			command << '-shared'
			if mode == 'build' { command << ['-enable-globals', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler'] }
		}
		command << ['-print-v-files', source]
		listing := run(command, root + '/listing-' + os.base(source) + '.log')!
		for line in listing.split_into_lines() {
			path := line.trim_space()
			if path.ends_with('.v') && os.is_file(path) { inputs << os.real_path(path) }
		}
	}
	mut tests := []string{}
	for directory in ['accountbroker', 'accountclient', 'accountmanifest', 'nativeaccountauth', 'nativeapk'] {
		for name in os.ls(repo + '/build-support/android/' + directory)! {
			if name.ends_with('_test.v') { tests << repo + '/build-support/android/' + directory + '/' + name }
		}
	}
	tests << repo + '/tests/native-android-ws/companionstage/stage_test.v'
	inputs << repo + '/tests/native-android-ws/companionstage/stage.v'
	tests.sort()
	inputs << tests
	run([v, 'version'], root + '/v-version.log')!
	run(['git', 'rev-parse', 'HEAD'], root + '/source-revision.log')!
	if mode != 'build' {
		hashes := capture(root, inputs)!
		os.mkdir(root + '/companion-fixtures', mode: 0o700)!
		os.setenv('VINIX_COMPANION_STAGE_TEST_ROOT', root + '/companion-fixtures', true)
		if mode == 'asan' { os.setenv('ASAN_OPTIONS', 'detect_leaks=0:halt_on_error=1', true) }
		for index, source in tests {
			name := index.str() + '-' + os.base(os.dir(source)) + '-' + os.base(source)
			mut command := common.clone()
			command << ['-cc', 'cc']
			if mode == 'asan' {
				command << ['-cflags', '-fsanitize=address -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address']
			}
			command << ['-o', root + '/' + name, source]
			run(command, root + '/' + name + '.compile.log')!
			run([root + '/' + name], root + '/' + name + '.run.log')!
		}
		unchanged(hashes)!
		println('CURRENT-ACCOUNT-PROTOCOL-CHECK-PASS mode=' + mode + ' files=' + tests.len.str())
		return
	}
	runtime := repo + '/build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	header := '/Users/alex/.local/state/vinix/android/account-native-compile-2026-10-26-r1/sqlite3.h'
	sqlite := runtime + '/usr/lib/libsqlite3.so.0'
	inputs << [cross, header, sqlite]
	zlib := repo + '/build/n64/zlib-source'
	for name in os.ls(zlib)! {
		if name.ends_with('.c') || name.ends_with('.h') || name == 'LICENSE' { inputs << zlib + '/' + name }
	}
	inputs << cross.replace('gcc', 'ar')
	hashes := capture(root, inputs)!
	os.mkdir_all(root + '/native')!
	os.cp(header, root + '/native/sqlite3.h')!
	os.cp(sqlite, root + '/native/libsqlite3.so')!
	os.mkdir_all(root + '/zlib')!
	for path in inputs.filter(it.starts_with(zlib + '/')) { os.cp(path, root + '/zlib/' + os.base(path))! }
	mut objects := []string{}
	for unit in ['adler32', 'compress', 'crc32', 'deflate', 'gzclose', 'gzlib', 'gzread', 'gzwrite',
		'inflate', 'infback', 'inftrees', 'inffast', 'trees', 'uncompr', 'zutil'] {
		object := root + '/zlib/' + unit + '.o'
		run([cross, '-O2', '-fPIC', '-D_LARGEFILE64_SOURCE=1', '-I' + root + '/zlib',
			'-c', root + '/zlib/' + unit + '.c', '-o', object], root + '/zlib/' + unit + '.compile.log')!
		objects << object
	}
	mut archive := [cross.replace('gcc', 'ar'), 'rcs', root + '/zlib/libz.a']
	archive << objects
	run(archive, root + '/zlib/archive.log')!
	mut arm := common.clone()
	arm << ['-os', 'linux', '-arch', 'arm64', '-cc', cross, '-showcc', '-keepc']
	optimization := '-O2 --param=ggc-min-expand=5 --param=ggc-min-heapsize=8192'
	mut broker_command := arm.clone()
	broker_command << ['-cflags', optimization + ' -static -no-pie -I' + root + '/zlib -L' + root + '/zlib',
		'-o', root + '/native-account-broker', broker]
	run(broker_command, root + '/broker-build.log')!
	mut launcher_command := arm.clone()
	launcher_command << ['-cflags', optimization + ' -static -no-pie -I' + root + '/zlib -L' + root + '/zlib',
		'-o', root + '/run-android', repo + '/build-support/android/native-run.v']
	run(launcher_command, root + '/launcher-build.log')!
	mut client_command := arm.clone()
	client_command << ['-shared', '-enable-globals', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-cflags', optimization + ' -fPIC -I' + root + '/native -L' + root + '/native -I' + root + '/zlib -L' + root + '/zlib',
		'-ldflags', '-Wl,-z,defs -Wl,-z,max-page-size=65536', '-o', root + '/libvinix-android-account.so', client]
	run(client_command, root + '/client-build.log')!
	for name in ['native-account-broker', 'libvinix-android-account.so', 'run-android'] {
		bytes := os.read_bytes(root + '/' + name)!
		kind := if name.ends_with('.so') { u8(3) } else { u8(2) }
		if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
			|| bytes[16..20] != [kind, u8(0), 183, 0] {
			return error('AArch64 ELF64 required: ' + name)
		}
		os.write_file(root + '/' + name + '.sha256', digest(root + '/' + name)!)!
	}
	symbols := run([cross.replace('gcc', 'nm'), '-D', '--defined-only', root + '/libvinix-android-account.so'], root + '/client-symbols.log')!
	mut defined := []string{}
	for line in symbols.split_into_lines() {
		parts := line.fields()
		if parts.len >= 3 && parts[parts.len - 2] == 'T' { defined << parts.last() }
	}
	mut exports := 0
	for path in inputs {
		if !path.starts_with(client + '/') || !path.ends_with('.v') || path.ends_with('_test.v') { continue }
		for line in os.read_file(path)!.split_into_lines() {
			if !line.trim_space().starts_with('@[export:') { continue }
			name := line.all_after("'").all_before("'")
			if name == '' || name !in defined { return error('missing account ABI export: ' + name) }
			exports++
		}
	}
	if exports < 60 { return error('account ABI source listing incomplete') }
	unchanged(hashes)!
	println('CURRENT-ACCOUNT-PROTOCOL-BUILD-PASS ' + root)
}

fn main() {
	if os.args.len != 3 { eprintln('usage: build-current-account-protocol plain|asan|build FRESH_ROOT'); exit(2) }
	execute(os.args[1], os.abs_path(os.args[2])) or { eprintln(err); exit(1) }
}
