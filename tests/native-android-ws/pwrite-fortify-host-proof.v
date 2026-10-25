// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded host/ARM64 proof; never changes a retained Maps run.
module main

import crypto.sha256
import encoding.base64
import json2
import net.http
import os
import time

const compiler = '/Users/alex/code/vinix/build/android-maps/queue284-tools/v_old276'
const aosp = 'https://android.googlesource.com/platform/bionic/+/a1bc57f84cf3d05ec20a25e0126ecdcc4847fa5b/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn record(root string, name string, argv []string) !string {
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(root + '/' + name + '.log', r.output)!
	os.write_file(root + '/' + name + '.json', json2.encode({
		'argv': json2.Any(argv)
		'executable_sha256': json2.Any(hash(os.real_path(argv[0]))!)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(r.exit_code)
	}, prettify: true) + '\n')!
	assert r.exit_code == 0, name + ': ' + r.output
	return r.output
}

fn symbols(text string, name string, defined bool) bool {
	return text.split_into_lines().any(it.fields().len >= 8
		&& it.fields().last() == name && it.contains(' GLOBAL ')
		&& (if defined { it.contains(' FUNC ') && !it.contains(' UND ') } else { it.contains(' UND ') }))
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular artifact: ' + key) }
		}
	}
}

fn main() {
	$if prod { panic('requires assertions') }
	run() or { eprintln(err); exit(1) }
}

fn run() ! {
	assert os.args.len == 2, 'usage: pwrite-fortify-host-proof EXTERNAL_PREPARED_ROOT'
	root := os.real_path(os.args[1])
	assert !os.exists(root + '/sha256.json')
	assert hash(compiler)! == '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
	generator := 'tests/linuxkpi/generate_module.v'
	revision := os.read_file(root + '/source-revision.txt')!.trim_space()
	committed := os.exec(['git', 'show', revision + ':' + generator])
	assert committed.exit_code == 0
	assert sha256.sum(committed.output.bytes()).hex() == hash(generator)!
	os.cp(generator, root + '/source/generate_module.v')!
	for relative in ['build-support/android/wsloader/fortify.v',
		'build-support/android/wsloader/fortify_test.v', 'tests/native-android-ws/assetprobe/libc.v'] {
		frozen := if relative.starts_with('build-support/') {
			root + '/source/wsloader/' + os.file_name(relative)
		} else { root + '/source/assetprobe/libc.v' }
		assert hash(relative)! == hash(frozen)!, relative
	}
	for path in ['libc/bionic/fortify.cpp', 'libc/private/bionic_fortify.h'] {
		response := http.get(aosp + path + '?format=TEXT')!
		assert response.status_code == 200
		os.write_file(root + '/' + os.file_name(path), base64.decode_str(response.body))!
	}
	contract := os.read_file(root + '/fortify.cpp')!.fields().join(' ')
	for suffix in ['', '64'] {
		assert contract.contains('__pwrite' + suffix + '_chk(int fd, const void* buf, size_t count, off' + suffix + '_t offset, size_t buf_size)')
		assert contract.contains('__check_count("pwrite' + suffix + '", "count", count);')
		assert contract.contains('__check_buffer_access("pwrite' + suffix + '", "read from", count, buf_size);')
		assert contract.contains('return pwrite' + suffix + '(fd, buf, count, offset);')
	}
	checks := os.read_file(root + '/bionic_fortify.h')!.fields().join(' ')
	assert checks.contains('value > SSIZE_MAX')
	assert checks.contains('claim > actual')
	readelf := os.find_abs_path_of_executable('aarch64-linux-musl-readelf')!
	loader := record(root, 'verified-loader-symbols', [readelf, '--syms', '--wide', root + '/android-loader.o'])!
	for symbol in ['bionic___pwrite_chk', 'bionic___pwrite64_chk'] { assert symbols(loader, symbol, true) }
	assert symbols(loader, 'pwrite', false)
	old := os.read_file(root + '/maps356-loader-dynsym.txt')!
	assert symbols(old, 'bionic___pread_chk', true)
	assert !symbols(old, 'bionic___pwrite_chk', true)
	assert !symbols(old, 'bionic___pwrite64_chk', true)
	assert os.read_file(root + '/libAppDataSearch-dynsym.txt')!.contains('__pwrite_chk@LIBC_N')
	// The full assetprobe also needs generated TLS declarations. Compile the
	// real libc fixture alone here to inspect its raw Android symbol imports.
	probe := root + '/libc-probe/assetprobe'
	os.mkdir_all(probe)!
	os.cp(root + '/source/assetprobe/libc.v', probe + '/libc.v')!
	os.setenv('VINIX_V_COMPILER', compiler, true)
	record(root, 'libc-probe-generation', [compiler, '-nocache', '-cc', 'cc', 'run',
		'tests/linuxkpi/generate_module.v', probe, root + '/libc-probe.c', '--arch', 'arm64'])!
	record(root, 'libc-probe-object-build', [os.find_abs_path_of_executable('aarch64-linux-musl-gcc')!,
		'-O2', '-fPIC', '-c', root + '/libc-probe.c', '-o', root + '/libc-probe.o'])!
	imports := record(root, 'verified-libc-probe-symbols', [readelf, '--syms', '--wide', root + '/libc-probe.o'])!
	for symbol in ['__pread_chk', '__pread64_chk', '__pwrite_chk', '__pwrite64_chk'] {
		assert symbols(imports, symbol, false)
	}
	os.cp('tests/native-android-ws/pwrite-fortify-host-proof.v', root + '/source/pwrite-fortify-host-proof.v')!
	os.write_file(root + '/validation.json', json2.encode({
		'checked_utc': json2.Any(time.utc().str())
		'aosp_revision': json2.Any('a1bc57f84cf3d05ec20a25e0126ecdcc4847fa5b')
		'arm64_loader_exports_and_host_pwrite_import': json2.Any(true)
		'raw_android_fixture_imports': json2.Any(true)
		'maps356_loader_lacks_new_exports': json2.Any(true)
		'maps_guest_replay_performed': json2.Any(false)
	}, prettify: true) + '\n')!
	mut pins := map[string]string{}
	inventory(root, '', mut pins)!
	os.write_file(root + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println('PWRITE-FORTIFY-HOST-PROOF-PASS files=${pins.len} manifest=' + hash(root + '/sha256.json')!)
}
