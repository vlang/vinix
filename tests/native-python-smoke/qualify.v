// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import cpythonapi
import crypto.sha256
import encoding.binary
import json2
import os
import sourcecommand

fn checked(argv []string, environment map[string]string, log string) !sourcecommand.Output {
	result := sourcecommand.capture_full(argv, environment, -1, 32 * 1024 * 1024, cachecli.cancelled)!
	text := result.stdout + result.stderr
	os.write_file(log, text)!
	if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:',
		'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('native Python smoke qualification failed: ' + log)
	}
	return result
}

fn run() ! {
	if os.args.len != 4 { return error('expected COMPILER NEW_EVIDENCE arm|x86|san') }
	compiler, work, profile := os.args[1], os.args[2], os.args[3]
	if os.exists(work) || profile !in ['arm', 'x86', 'san'] {
		return error('expected new evidence and profile')
	}
	os.mkdir_all(work)!
	os.mkdir(work + '/tmp')!
	os.setenv('VTMP', work + '/tmp', true)
	os.setenv('TMPDIR', work + '/tmp', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1', true)
	os.setenv('UBSAN_OPTIONS', 'halt_on_error=1:print_stacktrace=1', true)
	os.setenv('V', compiler, true)
	root := os.real_path(os.dir(@FILE) + '/../..')
	mut flags := []string{}
	if profile == 'x86' {
		flags = ['-arch', 'amd64', '-cflags', '--target=x86_64-apple-macos13', '-ldflags',
			'--target=x86_64-apple-macos13']
	}
	if profile == 'san' {
		flags = ['-gc', 'none', '-cflags', '-fsanitize=address,undefined', '-cflags',
			'-fno-omit-frame-pointer', '-cflags', '-O1', '-ldflags', '-fsanitize=address,undefined']
	}
	mut receipts := []json2.Any{}
	for name, path in {
		'main':      root + '/tests/native-python-smoke/main.v'
		'ownership': root + '/tests/native-python-smoke/pysmoke/callback_test.v'
		'builder':   root + '/build-support/python-smoke.v'
	} {
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-path',
			'@vlib|' + root + '/tests/native-python-smoke|@vmodules', '-o', work + '/' + name,
			path], os.environ(), work + '/' + name + '-build.log')!
		receipts << json2.Any({
			'name':   json2.Any(name)
			'sha256': json2.Any(sha256.sum(os.read_bytes(work + '/' + name)!).hex())
		})
		println('PASS cold native Python smoke build ' + profile + '/' + name)
		flush_stdout()
	}
	checked([work + '/ownership'], os.environ(), work + '/ownership.log')!
	checked([work + '/main', '--help'], os.environ(), work + '/help.log')!
	mut environment := os.environ()
	environment['VINIX_CPYTHON_LIBRARY'] = '/nonexistent/vinix-cpython-sdk'
	for argv in [['--abi-only'], ['--fcntl-only'], ['--unknown']] {
		result := sourcecommand.capture_full([work + '/main', ...argv], environment, -1, 1024 * 1024, cachecli.cancelled)!
		assert result.status == if argv[0] == '--unknown' { 2 } else { 1 }, result.str()
		os.write_file(work + '/guard-' + argv[0].trim_left('-') + '.log', result.stdout + result.stderr)!
	}
	for arch in ['aarch64', 'x86_64'] {
		output := work + '/guest-' + arch
		checked([work + '/builder', '--arch', arch, '--cc', '/opt/homebrew/opt/llvm/bin/clang',
			'--output', output], os.environ(), output + '-build.log')!
		bytes := os.read_bytes(output)!
		assert bytes[..6] == [u8(127), `E`, `L`, `F`, 2, 1] && binary.little_endian_u16_at(bytes, 18) == if arch == 'aarch64' {
			u16(183)
		} else {
			u16(62)
		}
		receipt := json2.decode[map[string]json2.Any](os.read_file(output + '.native.json')!)!
		assert receipt['executable_sha256']!.str() == sha256.sum(bytes).hex()
		receipts << json2.Any(receipt)
		layer := root + if arch == 'aarch64' {
			'/build-aarch64-python'
		} else {
			'/build-amd64-python'
		}
		sdk := layer + '/staging/usr/lib/libpython3.12.so.1.0'
		symbols := checked(['/opt/homebrew/opt/llvm/bin/llvm-nm', '--dynamic', '--defined-only',
			sdk], os.environ(), work + '/sdk-' + arch + '-symbols.log')!
		mut names := map[string]bool{}
		for line in symbols.stdout.split_into_lines() {
			parts := line.fields()
			if parts.len >= 3 { names[parts.last()] = true }
		}
		for name in cpythonapi.symbols {
			assert names[name], arch + '/' + name
		}
		receipts << json2.Any({
			'sdk':     json2.Any(sdk)
			'sha256':  json2.Any(sha256.sum(os.read_bytes(sdk)!).hex())
			'symbols': json2.Any(cpythonapi.symbols.len)
		})
		// A compiler failure must preserve a previously qualified destination.
		before := sha256.sum(os.read_bytes(output)!).hex()
		failed := sourcecommand.capture_full([work + '/builder', '--arch', arch, '--cc',
			'/usr/bin/false', '--output', output], os.environ(), -1, 1024 * 1024, cachecli.cancelled)!
		assert failed.status == 1 && sha256.sum(os.read_bytes(output)!).hex() == before
		os.write_file(work + '/failure-' + arch + '.log', failed.stdout + failed.stderr)!
	}
	for argv in [['--output', work + '/invalid', '--arch', 'bad'],
		['--output', work + '/invalid', '--sysroot', '/missing-smoke-sdk']] {
		result := sourcecommand.capture_full([work + '/builder', ...argv], os.environ(), -1, 1024 * 1024, cachecli.cancelled)!
		assert result.status in [1, 2] && !os.exists(work + '/invalid')
	}
	for path in ['scripts/build-python-aarch64.sh', 'scripts/build-developer-tools-aarch64.sh', 'tests/developer-tools/smoke.sh'] {
		checked(['/bin/bash', '-n', root + '/' + path], os.environ(), work + '/syntax-' + os.file_name(path) + '.log')!
	}
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({
		'status':   json2.Any('PASS')
		'profile':  json2.Any(profile)
		'receipts': json2.Any(receipts)
		'limits':   json2.Any('No interpreter, SDK Python modules or Vinix guest executed. Ownership/callback tests use a native V model, and actual staged CPython ELF exports are checked as data. Both guest executables are generated and linked against real existing musl SDKs; this establishes builds/ABI availability and preserves source checks without asserting a new guest runtime result.')
	}),
		prettify: true
	) + '\n')!
	println('PASS native Python smoke qualification ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(1)
	}
}
