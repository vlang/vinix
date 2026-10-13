// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import json2
import os
import sourcecommand

fn checked(argv []string, environment map[string]string, log string) !sourcecommand.Output {
	r := sourcecommand.capture_full(argv, environment, 300, 16 * 1024 * 1024, cachecli.cancelled)!
	text := r.stdout + r.stderr
	os.write_file(log, text)!
	if r.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:', 'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('host-tool qualification failed: ' + log)
	}
	return r
}

fn qualify() ! {
	if os.args.len != 4 { return error('expected COMPILER NEW_EVIDENCE arm|x86|san') }
	compiler, work, profile := os.args[1], os.args[2], os.args[3]
	if os.exists(work) || profile !in ['arm', 'x86', 'san'] { return error('expected new evidence and profile') }
	os.mkdir_all(work)!
	os.mkdir(work + '/tmp')!
	root := os.real_path(os.dir(@FILE) + '/../..')
	mut environment := os.environ()
	for key, value in {'V':compiler, 'VINIX_V_COMPILER':compiler, 'VTMP':work + '/tmp', 'TMPDIR':work + '/tmp',
		'V_C_ERROR_BUG_REPORT_DISABLED':'1', 'V_MACOS_V3_NO_FALLBACK':'1',
		'ASAN_OPTIONS':'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1', 'UBSAN_OPTIONS':'halt_on_error=1:print_stacktrace=1'} {
		environment[key] = value
	}
	mut flags := []string{}
	mut wrapper_flags := ''
	mut cc_flags := []string{}
	if profile == 'x86' {
		flags = ['-arch', 'amd64', '-cflags', '--target=x86_64-apple-macos13', '-ldflags', '--target=x86_64-apple-macos13']
		wrapper_flags = '-arch amd64 -cflags --target=x86_64-apple-macos13 -ldflags --target=x86_64-apple-macos13 '
		// The native ARM Darwin reference traps on overflow. Its x86 SDK
		// implementation raises SIGILL under Rosetta, which the unchanged
		// original SIGTRAP oracle rejects. Qualify the x86 controller with
		// the native reference instead of weakening that oracle.
		cc_flags = ['--target=arm64-apple-macos13']
	}
	if profile == 'san' {
		flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined', '-cflags', '-fno-omit-frame-pointer', '-cflags', '-O1', '-ldflags', '-fsanitize=address,undefined']
		wrapper_flags = '-gc none -cflags -fsanitize=address,undefined -cflags -fno-omit-frame-pointer -cflags -O1 -ldflags -fsanitize=address,undefined '
	}
	mut receipts := []json2.Any{}
	for name, path in {'main':root + '/build-support/source-tools/main.v',
		'host-check':root + '/build-support/source-tools/check-host.v', 'source-check':root + '/build-support/source-tools/check.v'} {
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', work + '/' + name, path], environment, work + '/' + name + '-build.log')!
		receipts << json2.Any({'name':json2.Any(name),'sha256':json2.Any(sha256.sum(os.read_bytes(work + '/' + name)!).hex())})
	}
	checked([work + '/host-check', work + '/host-fixtures', root], environment, work + '/host-check.log')!
	checked([work + '/source-check', work + '/source-fixtures', root], environment, work + '/source-check.log')!
	checked([work + '/main', '--help'], environment, work + '/help.log')!
	for kind, fixture in {'cxx':'cxx-extended.cpp', 'assertions':'assertions.c', 'safety':'libsystem-safety.c', 'process':'process.c'} {
		mut options := ['-O1', '-Wall', '-Wextra', '-Werror']
		if kind == 'cxx' { options << ['-DIOS_CXX_REFERENCE', '-std=c++17'] }
		cc := if kind == 'cxx' { '/usr/bin/clang++' } else { '/usr/bin/clang' }
		checked([cc, ...cc_flags, ...options, root + '/tests/ios/' + fixture, '-o', work + '/' + kind], environment, work + '/' + kind + '-build.log')!
		checked([work + '/main', 'darwin-signals', kind, work + '/' + kind], environment, work + '/' + kind + '-signals.log')!
		if kind != 'process' { checked([work + '/' + kind], environment, work + '/' + kind + '-normal.log')! }
		// The process fixture's ordinary mode changes credentials. Only its
		// original signal modes are run during this focused qualification.
	}
	failure := sourcecommand.capture_full([work + '/main', 'darwin-signals', 'cxx', '/usr/bin/false'], environment, 10, 65536, cachecli.cancelled)!
	assert failure.status != 0 && failure.stderr.contains('unexpected signal')
	// Exercise the public build wrapper and its real CPython header include,
	// without importing a module, initializing an interpreter or invoking Python.
	wrapper := work + '/v-compiler'
	os.write_file(wrapper, '#!/bin/sh\nexec /usr/bin/env -u CFLAGS -u LDFLAGS "' + compiler + '" -nocache -cc /usr/bin/clang ' + wrapper_flags + '"$@"\n')!
	os.chmod(wrapper, 0o755)!
	environment['V'] = wrapper
	environment['VINIX_V_COMPILER'] = wrapper
	environment['VINIX_HOST_PYTHON'] = '/usr/bin/python3'
	header := checked([work + '/main', 'cpython-headers', '/usr/bin/python3'], environment, work + '/headers.log')!.stdout.trim_space()
	assert os.is_file(header + '/Python.h')
	checked([work + '/main', 'cpython-version', '/usr/bin/python3'], environment, work + '/version.log')!
	probe := work + '/header-probe.v'
	os.write_file(probe, 'module main\n#include <Python.h>\n@[export: \'vinix_header_probe\']\nfn probe() i32 { return i32(C.PY_MAJOR_VERSION * 100 + C.PY_MINOR_VERSION) }\n')!
	checked(['/bin/sh', root + '/build-support/build-v-host-library.sh', probe, work + '/header-probe.dylib'], environment, work + '/public-header-library.log')!
	checked(['/usr/bin/nm', '-gU', work + '/header-probe.dylib'], environment, work + '/header-exports.log')!
	for path in ['tests/ios/reference-frameworks.sh', 'examples/ios-2048/build.sh', 'examples/ios-calculator/build.sh',
		'scripts/build-blender-native-aarch64.sh', 'build-support/build-v-host-library.sh'] {
		checked(['/bin/bash', '-n', root + '/' + path], environment, work + '/' + os.file_name(path) + '-syntax.log')!
	}
	if profile == 'arm' {
		// Build actual signed bundles with the retained recipes. The pinned
		// upstream clone is a read-only local Git source, not a network fetch.
		mut app_environment := environment.clone()
		app_environment['VINIX_IOS_CALCULATOR_BUILD_DIR'] = work + '/calculator'
		app_environment['IOS_CLANG'] = '/usr/bin/clang'
		app_environment['IOS_LD'] = '/opt/homebrew/bin/ld64.lld'
		checked(['/bin/bash', root + '/examples/ios-calculator/build.sh'], app_environment, work + '/calculator-build.log')!
		os.mkdir(work + '/game')!
		checked(['/usr/bin/git', 'clone', '--shared', root + '/build/ios/2048/source', work + '/game/source'], environment, work + '/game-clone.log')!
		app_environment['VINIX_IOS_2048_BUILD_DIR'] = work + '/game'
		checked(['/bin/bash', root + '/examples/ios-2048/build.sh'], app_environment, work + '/game-build.log')!
		for package in [work + '/calculator/Calculator.ipa', work + '/game/NumberTileGame.ipa'] {
			checked(['/usr/bin/unzip', '-t', package], environment, package + '-test.log')!
		}
	}
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({'status':json2.Any('PASS'), 'profile':json2.Any(profile),
		'receipts':json2.Any(receipts), 'limits':json2.Any('Nine embedded blocks in five Shell callers. Native ARM Darwin C/C++ references, including signal-only process modes, run under ARM/x86/sanitized V controllers. The separate x86 Darwin overflow attempt raises SIGILL and fails the retained original SIGTRAP oracle. SDK headers are inert data; original source checks and real signed calculator/2048 Mach-O builds on ARM pass. No Python, interpreter initialization, Keychain/security/credentials fixture, Blender build, UI application or Vinix guest executes. Sanitizers instrument V; zlib and reference fixtures are unchanged SDK inputs. IPA archives retain classic ZIP limits.')}), prettify:true) + '\n')!
	println('PASS native host-tool qualification ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	qualify() or { eprintln(err); exit(1) }
}
