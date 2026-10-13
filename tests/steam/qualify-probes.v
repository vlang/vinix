// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import compress.gzip
import crypto.sha256
import encoding.binary
import json2
import os
import sourcecommand
import time

struct LogOwner {
mut:
	file os.File
}

fn retain_chunk(chunk string, context voidptr) ! {
	mut owner := unsafe { &LogOwner(context) }
	owner.file.write_string(chunk)!
}

fn checked(argv []string, environment map[string]string, log string, timeout f64) !sourcecommand.Output {
	mut owner := LogOwner{ file: os.create(log)! }
	defer { owner.file.close() }
	result := sourcecommand.capture_observed(argv, environment, timeout, 16 * 1024 * 1024, cachecli.cancelled, retain_chunk, unsafe { &owner }, 0)!
	text := result.stdout + result.stderr
	os.write_file(log, text)!
	if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:',
		'ERROR: AddressSanitizer'].any(text.contains(it)) {
		return error('Steam probe qualification failed: ' + log)
	}
	return result
}

fn cpio(mut output []u8, name string, mode u32, data []u8, major u32, minor u32, inode u32) {
	output << '070701'.bytes()
	for number in [inode, mode, u32(0), 0, 1, 0, u32(data.len), 0, 0, major, minor, u32(name.len + 1),
		0] {
		hex := number.hex()
		output << ('0'.repeat(8 - hex.len) + hex).bytes()
	}
	output << name.bytes()
	output << u8(0)
	for output.len % 4 != 0 { output << u8(0) }
	output << data
	for output.len % 4 != 0 { output << u8(0) }
}

fn ramdisk(executable string, output string) ! {
	mut archive := []u8{}
	mut inode := u32(1)
	for name in ['dev', 'dev/shm', 'proc', 'usr', 'usr/bin'] {
		cpio(mut archive, name, 0o40755, [], 0, 0, inode)
		inode++
	}
	cpio(mut archive, 'dev/console', 0o20600, [], 5, 1, inode)
	inode++
	data := os.read_bytes(executable)!
	cpio(mut archive, 'init', 0o100755, data, 0, 0, inode)
	inode++
	// This test input is a real ELF, just as the guest's qemu-i386 file is.
	// The probe tests pread into an unfaulted mapping, without interpreting it.
	cpio(mut archive, 'usr/bin/qemu-i386', 0o100755, data, 0, 0, inode)
	inode++
	cpio(mut archive, 'TRAILER!!!', 0, [], 0, 0, inode)
	os.write_file(output, gzip.compress(archive)!.bytestr())!
}

fn run() ! {
	if os.args.len != 6 {
		return error('expected COMPILER NEW_EVIDENCE arm|x86|san ARM_LINUX_KERNEL X86_LINUX_KERNEL')
	}
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
		'hosted':  root + '/tests/steam/hosted-command/main.v'
		'builder': root + '/tests/native-validation-tools/build-guest.v'
	} {
		checked([compiler, '-nocache', '-cc', '/usr/bin/clang', ...flags, '-o', work + '/' + name,
			path], environment, work + '/' + name + '-build.log', -1)!
		receipts << json2.Any({
			'program': json2.Any(name)
			'sha256':  json2.Any(sha256.sum(os.read_bytes(work + '/' + name)!).hex())
		})
	}
	environment['VINIX_STEAM_HOSTED_COMMAND'] = work + '/hosted'
	checked(['/bin/sh', root + '/tests/steam/hosted-test.sh'], environment, work + '/hosted-tests.log', 65)!
	for argv in [[]string{}, ['/usr/bin/false'], ['/nonexistent/vinix-steam-launcher']] {
		result := sourcecommand.capture_full([work + '/hosted', ...argv], environment, 25, 1024 * 1024, cachecli.cancelled)!
		assert result.status == if argv.len == 0 { 2 } else { 1 }, result.str()
	}
	os.cp(os.executable(), work + '/timeout-launcher')!
	started := time.sys_mono_now()
	failed := sourcecommand.capture_full([work + '/hosted', work + '/timeout-launcher'], environment, 28, 1024 * 1024, cachecli.cancelled)!
	os.write_file(work + '/timeout.log', failed.stdout + failed.stderr)!
	elapsed := f64(time.sys_mono_now() - started) / f64(time.second)
	assert failed.status == 1 && elapsed >= 20 && elapsed < 27, failed.str()
	for arch in ['aarch64', 'x86_64'] {
		for kind in ['production', 'sdk'] {
			output := work + '/' + kind + '-' + arch
			mut argv := [work + '/builder', '--arch', arch, '--static', '--source',
				root + '/tests/steam/syscall-probes/main.v', '--output', output, '--cache',
				work + '/guest-cache', '--v', compiler]
			if kind == 'sdk' { argv << ['--define', 'steam_probe_sdk'] }
			if arch == 'x86_64' {
				argv << ['--sysroot', root + '/build-amd64-desktop/initramfs-root']
			}
			checked(argv, environment, output + '-build.log', -1)!
			data := os.read_bytes(output)!
			assert data[..6] == [u8(127), `E`, `L`, `F`, 2, 1]
			assert binary.little_endian_u16_at(data, 18) == if arch == 'aarch64' {
				u16(183)
			} else {
				u16(62)
			}
			receipts << json2.Any({
				'program': json2.Any(kind + '-' + arch)
				'sha256':  json2.Any(sha256.sum(data).hex())
			})
		}
		initramfs := work + '/initramfs-' + arch + '.gz'
		ramdisk(work + '/sdk-' + arch, initramfs)!
		kernel := os.args[if arch == 'aarch64' { 4 } else { 5 }]
		mut argv := [
			if arch == 'aarch64' {
				'/opt/homebrew/bin/qemu-system-aarch64'
			} else {
				'/opt/homebrew/bin/qemu-system-x86_64'
			},
			'-nodefaults',
			'-display',
			'none',
			'-serial',
			'stdio',
			'-no-reboot',
			'-m',
			'256',
			'-smp',
			'1',
		]
		argv << if arch == 'aarch64' {
			['-machine', 'virt', '-accel', 'hvf', '-cpu', 'host']
		} else {
			['-machine', 'q35', '-accel', 'tcg']
		}
		console := if arch == 'aarch64' { 'ttyAMA0' } else { 'ttyS0' }
		argv << ['-kernel', kernel, '-initrd', initramfs, '-append',
			'console=' + console + ' panic=1 rdinit=/init -- --sdk-boot']
		result := checked(argv, environment, work + '/linux-' + arch + '.log', 60)!
		assert result.stdout.count('NATIVE STEAM SDK: PASS') == 1, result.stdout
		for probe in ['semaphores', 'lazy-buffer', 'unix-hangup', 'ipv4-ancillary', 'ppoll',
			'shared-mapping'] {
			assert result.stdout.count('STEAM SDK PASS: ' + probe) == 10, probe
		}
		receipts << json2.Any({
			'sdk_kernel':       json2.Any(arch)
			'sha256':           json2.Any(sha256.sum(os.read_bytes(kernel)!).hex())
			'initramfs_sha256': json2.Any(sha256.sum(os.read_bytes(initramfs)!).hex())
		})
		println('PASS 60 real Linux Steam probe cases ' + profile + '/' + arch)
		flush_stdout()
	}
	for path in ['tests/steam/steam-init.sh', 'tests/steam/hosted-test.sh',
		'scripts/build-steam-aarch64.sh'] {
		checked(['/bin/sh', '-n', root + '/' + path], environment, work + '/' + os.file_name(path) + '-syntax.log', -1)!
	}
	os.write_file(work + '/qualification.json', json2.encode(json2.Any({
		'status':   json2.Any('PASS')
		'profile':  json2.Any(profile)
		'receipts': json2.Any(receipts)
		'limits':   json2.Any('Actual musl-linked V probes execute on private RAM-only Alpine Linux SDK VMs on both architectures; repeated descriptor/path/child cleanup checked. No Python, Steam client, graphical app or Vinix guest executes. This establishes probe behavior and resource cleanup on the reference Linux SDK, not a new Vinix kernel pass.')
	}),
		prettify: true
	) + '\n')!
	println('PASS Steam probe qualification ' + profile)
}

fn main() {
	if os.file_name(os.executable()) == 'timeout-launcher' {
		time.sleep(30 * time.second)
		exit(0)
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(1)
	}
}
