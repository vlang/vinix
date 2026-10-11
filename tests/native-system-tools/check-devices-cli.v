// SPDX-License-Identifier: GPL-2.0-or-later
module main

import diskhost
import ext2host
import fixturehost
import hosttest
import json2
import math
import net
import os
import policyhost
import time

#include <signal.h>
#include <unistd.h>

fn C.kill(int, int) int
fn C.killpg(int, int) int
fn C.write(int, voidptr, usize) i64
fn C._exit(int)

__global drain_fd = int(-1)

// This process models QEMU's serial and NBD interfaces. Its results qualify
// controller orchestration; actual guest checks are recorded separately.
fn drain(_ int) {
	if drain_fd >= 0 { C.write(drain_fd, c'KERNEL PANIC during final drain\n', 32) }
	C._exit(0)
}

fn wave() []u8 {
	mut samples := []u8{}
	for index, frequency in [440, 660, 880] {
		duration := [f64(2), 0.45, 0.5][index]
		for at in 0 .. int(duration * 48000) {
			value := u16(i16(12000 * math.sin(2 * math.pi * frequency * f64(at) / 48000)))
			samples << [u8(value), u8(value >> 8)]
		}
	}
	mut data := []u8{len: 44}
	for index, byte in 'RIFF'.bytes() { data[index] = byte }
	ext2host.put_le(mut data, 4, u64(samples.len + 36), 4)
	for index, byte in 'WAVEfmt '.bytes() { data[8 + index] = byte }
	ext2host.put_le(mut data, 16, 16, 4)
	ext2host.put_le(mut data, 20, 1, 2)
	ext2host.put_le(mut data, 22, 1, 2)
	ext2host.put_le(mut data, 24, 48000, 4)
	ext2host.put_le(mut data, 34, 16, 2)
	for index, byte in 'data'.bytes() { data[36 + index] = byte }
	ext2host.put_le(mut data, 40, u64(samples.len), 4)
	data << samples
	return data
}

fn read_exact(mut connection net.TcpConn, count int) ![]u8 {
	mut data := []u8{len: count}
	mut at := 0
	for at < count {
		n := connection.read(mut data[at..])!
		if n == 0 { return error('Model NBD EOF') }
		at += n
	}
	return data
}

fn send_all(mut connection net.TcpConn, data []u8) ! {
	mut at := 0
	for at < data.len {
		n := connection.write(data[at..])!
		if n <= 0 { return error('Model NBD short write') }
		at += n
	}
}

fn backend(flags u16) ! {
	drive := os.args.filter(it.contains('file=nbd://'))[0]
	uri := drive.all_after('file=nbd://').all_before(',')
	mut connection := net.dial_tcp(uri.all_before('/'))!
	defer { connection.close() or {} }
	connection.set_read_timeout(time.second)
	greeting := read_exact(mut connection, 18)!
	assert ext2host.get_be(greeting, 0, 8) == ext2host.nbd_magic
	send_all(mut connection, [u8(0), 0, 0, 3])!
	mut option := []u8{len: 16}
	ext2host.put_be(mut option, 0, ext2host.option_magic, 8)
	ext2host.put_be(mut option, 8, 1, 4)
	send_all(mut connection, option)!
	info := read_exact(mut connection, 10)!
	assert ext2host.get_be(info, 8, 2) == flags
	mut request := []u8{len: 29}
	ext2host.put_be(mut request, 0, ext2host.request_magic, 4)
	ext2host.put_be(mut request, 6, 1, 2)
	ext2host.put_be(mut request, 24, 1, 4)
	request[28] = `X`
	send_all(mut connection, request)!
	assert ext2host.get_be(read_exact(mut connection, 16)!, 4, 4) == 30
}

fn machine() ! {
	mode := os.getenv('VINIX_DEVICE_MODEL')
	family := os.getenv('VINIX_DEVICE_FAMILY')
	os.write_file(os.getenv('VINIX_DEVICE_ARGV'), os.args[1..].join('\n'))!
	if family == 'pci-arm' {
		serial := os.args[os.args.index('-serial') + 1].all_after('file:')
		if mode == 'ignore-term' { unsafe { C.signal(C.SIGTERM, C.SIG_IGN) } }
		if mode == 'drain' {
			file := os.open_file(serial, 'a', 0o600)!
			drain_fd = file.fd
			unsafe { C.signal(C.SIGTERM, voidptr(drain)) }
		}
		if mode != 'timeout' {
			os.write_file(serial, systemhost_marker())!
			if mode == 'early-exit' {
				time.sleep(100 * time.millisecond)
				exit(7)
			}
			if mode == 'late' {
				time.sleep(200 * time.millisecond)
				mut file := os.open_file(serial, 'a')!
				file.write_string('KERNEL PANIC\n')!
				file.close()
			}
		}
		for { time.sleep(20 * time.millisecond) }
	} else if family == 'sound' {
		state := os.getenv('VINIX_DEVICE_STATE')
		os.write_file(state + '/sound.wav', wave().bytestr())!
		println('virtio-snd: stream 0\nSOUND TEST PASS: OSS parameters\nSOUND TEST PASS: the device has one owner at a time\nSOUND TEST PASS: handled signals do not interrupt writes\nSOUND TEST PASS: writes are paced by playback\nSOUND TEST PASS: a blocked writer can be killed\nSOUND TEST PASS: reopened at another rate')
		if mode == 'failure' { println('SOUND TEST FAIL line 42') }
		println('VINIX SOUND TEST: GUEST DONE')
	} else {
		backend(if family == 'fsync-scope' { u16(1) } else { u16(3) })!
		if mode == 'change-source' {
			path := os.getenv('VINIX_DEVICE_STATE') + '/source/mapped.bin'
			os.chmod(path, 0o600)!
			mut file := os.open_file(path, 'r+')!
			file.write_string('changed host data')!
			file.close()
		}
		marker := if family == 'export-read' {
			'DOTA2 EXPORT:'
		} else if family == 'virtio-ro' {
			'VIRTIO-RO'
		} else {
			'FSYNC-SCOPE'
		}
		if family == 'fsync-scope' { println('FSYNC-SCOPE FAILING-DISK-CONFIRMED') }
		println(marker + if mode == 'failure' { ' FAIL: controlled failure' } else { ' PASS' })
	}
	flush_stdout()
	time.sleep(150 * time.millisecond)
}

fn systemhost_marker() string {
	return 'PCI ARM GUEST: Linux ABI PID1 PASS\n' + if os.getenv('VINIX_DEVICE_CONFIG') == '1' {
		'pci: ARM checked config widths, bounds and interrupt masks passed\n'
	} else {
		''
	}
}

fn capture(argv []string, env map[string]string) !fixturehost.CapturedCommand {
	return fixturehost.capture_owned_bounded(argv, env, policyhost.caller_arch(), '', -1, policyhost.command_interrupted, false)!
}

fn command(argv []string, env map[string]string, status int, log string) ! {
	result := capture(argv, env)!
	os.write_file(log, result.stdout + result.stderr)!
	if result.status != status {
		return error('Expected ' + status.str() + ', got ' + result.status.str() + '; ' + log + '\n' + result.stdout + result.stderr)
	}
}

fn checked() ! {
	if os.args.len !in [4, 5, 6] || (os.args.len == 6 && os.args[5] != '--interrupt-only') {
		return error('check-devices-cli PREFIX PROFILE KERNEL-DIR [FRESH-WORK-DIR]')
	}
	prefix, profile, kernel := os.args[1], os.args[2], os.args[3]
	interrupt_only := os.args.len == 6
	work := hosttest.work_dir(if os.args.len >= 5 { os.args[4] } else { '' }, 'vinix-devices-cli-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	qemu := os.find_abs_path_of_executable('qemu-system-aarch64')!
	share := os.dir(os.dir(qemu)) + '/share/qemu'
	mut env := policyhost.environment()
	env['VINIX_QEMU_BIN'] = os.executable()
	env['VINIX_OVMF_CODE'] = share + '/edk2-aarch64-code.fd'
	env['VINIX_OVMF_VARS'] = share + '/edk2-arm-vars.fd'
	env['USE_TCG'] = '1'
	env['VINIX_DEVICE_ARGV'] = work + '/argv'
	os.mkdir_all(work + '/packages/game/dota')!
	os.write_file(work + '/packages/game/dota/pak01_dir.vpk', 'sample directory data')!
	for family in if interrupt_only { []string{} } else { ['fsync-scope', 'virtio-ro', 'export-read', 'sound'] } {
		for mode in if family == 'virtio-ro' {
			['pass', 'failure', 'change-source']
		} else {
			['pass', 'failure']
		} {
			state := hosttest.module_resolve(work + '/' + family + '-' + mode)!
			env['VINIX_DEVICE_MODEL'] = mode
			env['VINIX_DEVICE_FAMILY'] = family
			env['VINIX_DEVICE_STATE'] = state
			mut args := ['--kernel-dir', kernel,
				if family in ['fsync-scope', 'virtio-ro'] { '--work' } else { '--state-dir' },
				state]
			if family == 'sound' { args << '--build-fixture' }
			if family == 'export-read' { args << ['--source', work + '/packages'] }
			command([prefix + family + '-' + profile, ...args], env, if mode == 'pass' {
				0
			} else {
				1
			}, work + '/' + family + '-' + mode + '.log')!
			argv := os.read_file(work + '/argv')!
			if family != 'sound' {
				assert argv.contains('virtio-blk-pci,drive=guest-iso')
				assert !argv.contains('virtio-blk-device,drive=guest-iso')
				assert argv.contains('file=nbd://127.0.0.1:')
				assert argv.contains('readonly=on')
				assert argv.contains('id=unused,format=raw,file=' + state + '/unused.raw')
				nbd_at := argv.index('file=nbd://') or { return error('Missing NBD argument') }
				unused_at := argv.index('id=unused,format=raw,file=') or { return error('Missing unused disk argument') }
				assert nbd_at < unused_at
				report := json2.decode[json2.Any](os.read_file(state + '/results.json')!)!.as_map()
				assert report['passed']!.bool() == (mode == 'pass')
				if family == 'fsync-scope' {
					assert !report['advertised_read_only']!.bool() && report['backend_rejects_writes']!.bool()
				}
				if mode == 'change-source' {
					assert !report['readonly_host_files_unchanged']!.bool()
				}
			} else {
				assert argv.contains('virtio-sound-device,audiodev=vinix-audio,streams=1')
			}
			hosttest.remove_work_dir(state)!
		}
	}
	if !interrupt_only { println('PASS full storage/sound CLI: NBD flags, write rejection, source hashes, guest failures and WAV verdict') }
	env['VINIX_DEVICE_FAMILY'] = 'pci-arm'
	for mode in if interrupt_only { []string{} } else { ['pass', 'config-pass', 'early-exit', 'late', 'drain', 'timeout', 'ignore-term'] } {
		state := hosttest.module_resolve(work + '/pci-' + mode)!
		env['VINIX_DEVICE_MODEL'] = mode
		env['VINIX_DEVICE_CONFIG'] = if mode == 'config-pass' { '1' } else { '0' }
		args := ['--kernel', kernel + '/bin/vinix', '--state-dir', state, '--qemu', os.executable(),
			'--firmware', share + '/edk2-aarch64-code.fd', '--vars-template',
			share + '/edk2-arm-vars.fd', '--timeout', if mode == 'timeout' { '0.3' } else { '4' },
			...if mode != 'config-pass' { ['--no-config-test'] } else { []string{} }]
		command([prefix + 'pci-arm-' + profile, ...args], env, if mode in ['pass', 'config-pass',
			'ignore-term'] {
			0
		} else {
			1
		}, work + '/pci-' + mode + '.log')!
		report := json2.decode[json2.Any](os.read_file(state + '/result.json')!)!.as_map()
		assert report['status']!.str() == if mode in ['pass', 'config-pass', 'ignore-term'] {
			'passed'
		} else {
			'failed'
		}
		assert C.kill(report['owned_pid']!.int(), 0) < 0
		if mode == 'ignore-term' {
			assert report['owned_process_exit']!.int() == -9
		}
		hosttest.remove_work_dir(state)!
	}
	if !interrupt_only { println('PASS full PCI CLI: marker settle, early exit, late failure, final drain, deadline and TERM/KILL retirement') }
	// An observer interruption must retire its private QEMU group and report 130.
	state := hosttest.module_resolve(work + '/pci-interrupt')!
	env['VINIX_DEVICE_MODEL'] = 'timeout'
	mut child := fixturehost.spawn_logged([prefix + 'pci-arm-' + profile, '--kernel',
		kernel + '/bin/vinix', '--state-dir', state, '--qemu', os.executable(), '--firmware',
		share + '/edk2-aarch64-code.fd', '--vars-template', share + '/edk2-arm-vars.fd',
		'--no-config-test'], env, policyhost.caller_arch(), '', work + '/interrupt.log')!
	defer { child.close() }
	// Readiness includes a cold SDK/generator build under parallel profiles;
	// this setup budget is separate from the production guest deadline.
	deadline := time.sys_mono_now() + u64(300 * time.second)
	mut owned_pid := 0
	for owned_pid == 0 && time.sys_mono_now() < deadline {
		if child.poll()! {
			return error('Interrupt fixture exited during preparation: ' + os.read_file(work + '/interrupt.log')!)
		}
		if os.exists(state + '/result.json') {
			report := json2.decode[json2.Any](os.read_file(state + '/result.json')!) or {
				time.sleep(20 * time.millisecond)
				continue
			}
			values := report.as_map()
			owned_pid = (values['owned_pid'] or { json2.Any(0) }).int()
		}
		time.sleep(20 * time.millisecond)
	}
	if owned_pid == 0 {
		C.kill(child.pid, C.SIGINT)
		child.wait_for(15, policyhost.command_interrupted) or {}
		return error('Interrupt fixture did not finish its cold preparation: ' + os.read_file(work + '/interrupt.log')!)
	}
	assert C.kill(child.pid, C.SIGINT) == 0
	assert child.wait_for(10, policyhost.command_interrupted)! == 130
	assert C.kill(owned_pid, 0) < 0
	println('PASS observer interrupt and owned process cleanup')
}

fn main() {
	if os.getenv('VINIX_DEVICE_MODEL') != '' {
		machine() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	guard := policyhost.own_commands()
	defer { guard.close() }
	checked() or {
		eprintln(err)
		exit(1)
	}
}
