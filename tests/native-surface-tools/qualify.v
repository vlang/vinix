// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import encoding.binary
import json2
import os
import sourcecommand

fn checked(argv []string, environment map[string]string, log string) !sourcecommand.Output {
	result := sourcecommand.capture_full(argv, environment, -1, 16 * 1024 * 1024, cachecli.cancelled)!
	text := result.stdout + result.stderr
	os.write_file(log, text)!
	if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:',
		'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('surface qualification failed: ' + log)
	}
	return result
}

fn qualify() ! {
	if os.args.len != 4 { return error('expected COMPILER NEW_EVIDENCE arm|x86|san') }
	compiler, work, profile := os.args[1], os.args[2], os.args[3]
	if os.exists(work) || profile !in ['arm', 'x86', 'san'] {
		return error('expected new evidence and profile')
	}
	os.mkdir_all(work)!
	os.mkdir(work + '/tmp')!
	root := os.real_path(os.dir(@FILE) + '/../..')
	mut environment := os.environ()
	for key, value in {
		'V':                             compiler
		'VINIX_V_COMPILER':              compiler
		'VTMP':                          work + '/tmp'
		'TMPDIR':                        work + '/tmp'
		'V_C_ERROR_BUG_REPORT_DISABLED': '1'
		'V_MACOS_V3_NO_FALLBACK':        '1'
		'ASAN_OPTIONS':                  'detect_leaks=0:detect_stack_use_after_return=1:abort_on_error=1'
		'UBSAN_OPTIONS':                 'halt_on_error=1:print_stacktrace=1'
	} {
		environment[key] = value
	}
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
		'main':    root + '/tests/native-surface-tools/main.v'
		'core':    root + '/tests/native-surface-tools/surfacecore/core_test.v'
		'xlib':    root + '/tests/native-surface-tools/xfixture'
		'builder': root + '/tests/native-validation-tools/build-guest.v'
	} {
		output := work + '/' + name + if name == 'xlib' { '.dylib' } else { '' }
		mut args := [compiler, '-nocache', '-cc', '/usr/bin/clang', '-gc', 'none', ...flags]
		if name == 'xlib' { args << '-shared' }
		checked([...args, '-o', output, path], environment, output + '-build.log')!
		receipts << json2.Any({
			'name':   json2.Any(name)
			'sha256': json2.Any(sha256.sum(os.read_bytes(output)!).hex())
		})
	}
	checked([work + '/core'], environment, work + '/core.log')!
	checked([work + '/main', '--help'], environment, work + '/help.log')!
	path := work + '/surface'
	os.write_file(path, []u8{len: 8192, init: u8(0x11)}.bytestr())!
	for args, expected in {
		'colors':           '1\n'
		'colors-with-size': '8192 1\n'
	} {
		assert checked([work + '/main', args, path], environment, work + '/' + args + '.log')!.stdout == expected
	}
	for operation in ['damage', 'crc'] {
		assert checked([work + '/main', operation, work + '/missing'], environment, work + '/' + operation + '-missing.log')!.stdout == '-1\n'
	}
	for mode in ['success', 'missing-display', 'screen-count', 'no-shm', 'has-randr', 'missing-image',
		'bad-pixel', 'null-data', 'bad-header', 'bad-offset'] {
		mut bytes := []u8{len: 8192, init: u8(0xa5)}
		binary.big_endian_put_u32(mut bytes[0..4], 100)
		binary.big_endian_put_u32(mut bytes[76..80], 0)
		if mode == 'bad-header' { bytes = bytes[..79].clone() }
		if mode == 'bad-offset' { binary.big_endian_put_u32(mut bytes[0..4], 0xffffffff) }
		os.write_file(path, bytes.bytestr())!
		environment['VINIX_SURFACE_XLIB'] = work + '/xlib.dylib'
		environment['VINIX_SURFACE_MODEL_MODE'] = mode
		environment['VINIX_SURFACE_MODEL_FRAMEBUFFER'] = path
		environment['VINIX_SURFACE_MODEL_RECEIPT'] = work + '/capture-' + mode + '.json'
		result := sourcecommand.capture_full([work + '/main', 'obs-capture', path], environment, 10, 1024 * 1024, cachecli.cancelled)!
		os.write_file(work + '/capture-' + mode + '.log', result.stdout + result.stderr)!
		assert result.status == if mode == 'success' { 0 } else { 1 }, result.str()
		assert ![': fn ', 'V panic:', 'runtime error:', 'ERROR: AddressSanitizer'].any((result.stdout + result.stderr).contains(it))
		assert os.read_bytes(path)! == bytes, mode + '/pixel restoration'
		record := json2.decode[map[string]json2.Any](os.read_file(environment['VINIX_SURFACE_MODEL_RECEIPT'])!)!
		assert record['opened']!.int() == 0 && record['images']!.int() == 0
		assert record['destroyed']!.int() == if mode in ['success', 'bad-pixel', 'null-data'] {
			1
		} else {
			0
		}
	}
	for arch in ['aarch64', 'x86_64'] {
		output := work + '/guest-' + arch
		mut argv := [work + '/builder', '--arch', arch, '--source',
			root + '/tests/native-surface-tools/main.v', '--source-input',
			root + '/tests/native-surface-tools/surfacecore', '--output', output, '--cache',
			work + '/guest-cache', '--v', compiler]
		if arch == 'x86_64' { argv << ['--sysroot', root + '/build-amd64-desktop/initramfs-root'] }
		checked(argv, environment, output + '-build.log')!
		bytes := os.read_bytes(output)!
		assert bytes[..6] == [u8(127), `E`, `L`, `F`, 2, 1]
		assert binary.little_endian_u16_at(bytes, 18) == if arch == 'aarch64' {
			u16(183)
		} else {
			u16(62)
		}
		receipts << json2.Any({
			'guest':  json2.Any(arch)
			'sha256': json2.Any(sha256.sum(bytes).hex())
		})
	}
	for path2 in ['tests/browsers/firefox-init.sh', 'tests/browsers/chromium-init.sh',
		'tests/browsers/desktop-init.sh', 'tests/office/libreoffice-init.sh',
		'tests/packages/obs-init.sh', 'scripts/build-desktop-aarch64.sh'] {
		checked(['/bin/bash', '-n', root + '/' + path2], environment, work + '/' + os.file_name(path2) + '-syntax.log')!
	}
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({
		'status':   json2.Any('PASS')
		'profile':  json2.Any(profile)
		'receipts': json2.Any(receipts)
		'limits':   json2.Any('Actual shared mappings and file samplers run on macOS; X11 ABI/failure/pixel-restore/image/display/library ownership uses a native V fixture. Both real dynamic musl guest ELFs are linked. No Python, browser, office app, OBS, real X11 server or Vinix guest executes.')
	}),
		prettify: true
	) + '\n')!
	println('PASS native surface qualification ' + profile)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	qualify() or {
		eprintln(err)
		exit(1)
	}
}
