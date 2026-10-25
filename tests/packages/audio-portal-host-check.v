// SPDX-License-Identifier: GPL-2.0-or-later
// Maintained host qualification. Generated output belongs outside the checkout.
module main

import crypto.sha256
import json2
import os
import time

struct Pin { path string sha256 string }
struct Check { name string argv []string seconds f64 artifacts []Pin }
struct Receipt { format int = 1 source_revision string inputs []Pin checks []Check }

fn pin(path string) !Pin {
	bytes := os.read_bytes(path)!
	mut hash := sha256.new()
	mut sum := []u8{len: sha256.size}
	defer { unsafe { bytes.free(); sum.free(); hash.free(); free(hash) } }
	hash.write(bytes)!
	hash.checksum_into(mut sum)
	return Pin{ path: path, sha256: sum.hex() }
}

fn freeze_file(source string, destination string) !Pin {
	os.mkdir_all(os.dir(destination))!
	before := pin(source)!
	os.cp(source, destination)!
	retained := pin(destination)!
	if before.sha256 != retained.sha256 || pin(source)!.sha256 != before.sha256 { return error('input changed during retention: ' + source) }
	return retained
}

fn freeze_tree(source string, destination string) ![]Pin {
	mut result := []Pin{}
	for name in os.ls(source)! {
		input := source + '/' + name
		output := destination + '/' + name
		mode := (os.lstat(input)!).mode & 0o170000
		if mode == 0o040000 { result << freeze_tree(input, output)! }
		else if mode == 0o100000 { result << freeze_file(input, output)! }
		else { return error('nonregular retained input: ' + input) }
	}
	return result
}

fn checked(name string, argv []string, work string, artifact string) !Check {
	argv_path := work + '/' + name + '.argv.json'
	os.write_file(argv_path, json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	start := time.now(); child.run()
	output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	log := work + '/' + name + '.txt'
	os.write_file(log, output)!
	if code != 0 || output.contains('V panic:') || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') {
		return error(name + ' failed; inspect ' + log)
	}
	println(name + ' PASS')
	return Check{ name: name, argv: argv, seconds: f64(time.since(start).milliseconds()) / 1000,
		artifacts: if artifact == '' { [pin(log)!, pin(argv_path)!] } else { [pin(log)!, pin(argv_path)!, pin(artifact)!] } }
}

fn qualify() ! {
	if os.args.len != 2 { return error('usage: audio-portal-host-check NEW_EXTERNAL_DIRECTORY; set V to the exact V executable') }
	root := os.dir(os.dir(os.dir(@FILE)))
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) || work.starts_with(root + '/') { return error('results require a new external directory') }
	selected_v := os.real_path(os.find_abs_path_of_executable(os.getenv_opt('V') or { return error('set V to the selected compiler') })!)
	os.mkdir_all(work)!
	frozen := work + '/source'
	v := work + '/toolchain/v'
	mut inputs := [freeze_file(selected_v, v)!]
	os.chmod(v, 0o755)!
	for tree in ['vlib', 'thirdparty'] { inputs << freeze_tree(os.dir(selected_v) + '/' + tree, work + '/toolchain/' + tree)! }
	inputs << freeze_file(os.dir(selected_v) + '/v.mod', work + '/toolchain/v.mod')!
	for tree in ['tools/packages', 'tools/accounts', 'compat/ios/plist'] { inputs << freeze_tree(root + '/' + tree, frozen + '/' + tree)! }
	inputs << freeze_file(root + '/desktop/tools/tests/heap_tracker.h', frozen + '/desktop/tools/tests/heap_tracker.h')!
	inputs << freeze_file(@FILE, frozen + '/tests/packages/audio-portal-host-check.v')!
	for key in ['VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(key, v, true) }
	for key, value in {'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_C_ERROR_BUG_REPORT_DISABLED': '1',
		'ASAN_OPTIONS': 'detect_leaks=0', 'UBSAN_OPTIONS': 'halt_on_error=1'} { os.setenv(key, value, true) }
	for key in ['VINIX_AUDIO_PROTOCOL', 'VINIX_AUDIO_SOCKET', 'VINIX_AUDIO_DEVICE', 'VINIX_AUDIO_INODE',
		'VINIX_AUDIO_WORKER', 'VINIX_AUDIO_GENERATION', 'VINIX_AUDIO_MANIFEST', 'VINIX_AUDIO_BOOTSTRAP_FD'] { os.unsetenv(key) }
	suites := [
		['portal', 'tools/packages/audiopcm/portal_test.v', 'focused'],
		['audio-transport', 'tools/packages/pkglaunch/audio_test.v', 'focused'],
		['audio-launch', 'tools/packages/pkgcore/audio_launch_test.v', 'focused'],
		['protocol', 'tools/packages/pkglaunch/protocol_test.v', 'historical'],
		['display', 'tools/packages/pkglaunch/display_test.v', 'historical'],
		['ownership', 'tools/packages/pkglaunch/ownership_test.v', 'historical'],
		['client-ownership', 'tools/packages/pkglaunch/client_ownership_test.v', 'historical'],
		['streams', 'tools/packages/pkglaunch/streams_test.v', 'historical'],
		['launch-ownership', 'tools/packages/pkgcore/launch_ownership_test.v', 'historical'],
		['session-ownership', 'tools/accounts/sessioncore/launch_ownership_test.v', 'historical'],
	]
	clang := os.find_abs_path_of_executable('clang')!
	inputs << pin(clang)!
	os.write_file(work + '/inputs.json', json2.encode(inputs) + '\n')!
	flags := ['-backend', 'c', '-cc', 'clang', '-gc', 'none', '-manualfree', '-enable-globals',
		'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-cflags', '-I' + frozen + '/desktop/tools/tests',
		'-path', '@vlib|' + frozen + '|' + frozen + '/tools/accounts|@vmodules']
	mut checks := []Check{}
	checks << checked('v-version', [v, 'version'], work, '')!
	checks << checked('clang-version', [clang, '--version'], work, '')!
	for suite in suites {
		for mode in ['normal', 'production', 'sanitized'] {
			// Historical suites use assertions, which -prod strips. Only focused
			// tests contain explicit checks and run in production mode.
			if mode == 'production' && suite[2] != 'focused' { continue }
			name := suite[0] + '-' + mode
			binary := work + '/' + name
			tracking := if suite[0] in ['portal', 'audio-transport', 'ownership', 'launch-ownership', 'session-ownership'] { ['-d', 'track_heap'] } else { []string{} }
			extra := if mode == 'production' { ['-prod'] } else if mode == 'sanitized' {
				['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
			} else { []string{} }
			checks << checked(name + '-compile', [v, ...flags, ...tracking, ...extra, '-o', binary, frozen + '/' + suite[1]], work, binary)!
			checks << checked(name + '-run', [binary], work, binary)!
		}
	}
	for arch in ['arm64', 'amd64'] {
		for entry in [['package', 'tools/packages/main.v'], ['session', 'tools/accounts/session.v']] {
			name := entry[0] + '-' + arch + '-production-c'
			output := work + '/' + name + '.c'
			checks << checked(name, [v, ...flags, '-prod', '-os', 'linux', '-arch', arch, '-o', output, frozen + '/' + entry[1]], work, output)!
		}
	}
	for input in inputs { if pin(input.path)! != input { return error('source/compiler changed during qualification: ' + input.path) } }
	revision := os.exec(['git', '-C', root, 'rev-parse', 'HEAD'])
	if revision.exit_code != 0 { return error('cannot record source revision') }
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ source_revision: revision.output.trim_space(), inputs: inputs, checks: checks }) + '\n')!
	println('AUDIO PORTAL HOST ' + checks.len.str() + ' checks PASS')
}

fn main() { qualify() or { eprintln(err); exit(1) } }
