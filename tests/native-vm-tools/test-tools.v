// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import gamehost
import json2
import math
import net.unix
import os
import sourcecommand
import tarstream
import time
import vmhost

#include <termios.h>
struct C.termios {}

fn C.tcgetattr(i32, &C.termios) i32
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.cfmakeraw(&C.termios)
fn C.fork() i32
fn C.raise(i32) i32

fn emit(text string) ! {
	mut out := os.stdout()
	unsafe { out.write_full_buffer(text.str, usize(text.len))! }
	out.flush()
}

fn raw() {
	mut settings := C.termios{}
	assert C.tcgetattr(0, &settings) == 0
	C.cfmakeraw(&settings)
	assert C.tcsetattr(0, C.TCSANOW, &settings) == 0
}

fn read_request(mut conn unix.StreamConn) !map[string]json2.Any {
	mut bytes := []u8{}
	mut one := []u8{len: 1}
	for {
		n := conn.read(mut one)!
		if n == 0 { return error('closed') }
		if one[0] == 10 { break }
		bytes << one[0]
	}
	return json2.decode[map[string]json2.Any](bytes.bytestr())!
}

fn mock() !bool {
	if os.args.len < 4 || os.args[1] != 'mock' { return false }
	family := os.args[2]
	mode := os.args[3]
	work := os.getenv('VINIX_VM_CASE')
	os.write_file(work + '/child.pid', os.getpid().str())!
	if mode == 'descendant' {
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			os.write_file(work + '/descendant.pid', os.getpid().str())!
			for { time.sleep(10 * time.millisecond) }
		}
		for !os.exists(work + '/descendant.pid') { time.sleep(time.millisecond) }
	}
	if mode == 'early' { exit(7) }
	if family == 'browser' {
		raw()
		if mode == 'kill' { unsafe { C.signal(C.SIGTERM, C.SIG_IGN) } }
		profile := vmhost.browser_profile(os.getenv('VINIX_VM_PROFILE'))!
		if mode !in ['timeout', 'kill', 'overflow', 'interrupt', 'terminate'] {
			body := profile.features.join('\n') + '\n' + if mode == 'fail' {
				profile.failures[0]
			} else {
				profile.pass
			} + '\n'
			if mode == 'large' { emit('native diagnostic\n'.repeat(80000))! }
			if mode == 'split' {
				for byte in body.bytes() {
					emit([byte].bytestr())!
					time.sleep(time.millisecond)
				}
			} else {
				emit(body)!
			}
		}
		if mode in ['timeout', 'kill', 'interrupt', 'terminate'] {
			for { time.sleep(10 * time.millisecond) }
		}
		mut byte := u8(0)
		for C.read(0, &byte, 1) == 1 {
			if byte == `x` {
				os.write_file(work + '/monitor-exit', 'PASS\n')!
				exit(if mode == 'nonzero' { 7 } else { 0 })
			}
		}
	} else if family == 'activity' {
		if mode in ['hang', 'interrupt', 'terminate'] {
			for { time.sleep(10 * time.millisecond) }
		}
		mut stderr := os.stderr()
		stderr.writeln('ACTIVITY-CHECK diagnostic stderr')!
		stderr.flush()
		emit(if mode == 'fail' {
			'ACTIVITY-CHECK FAIL x\nACTIVITY-CHECK DONE failures=1\n'
		} else {
			'ACTIVITY-CHECK DONE failures=0\n'
		})!
		for { time.sleep(10 * time.millisecond) }
	} else if family == 'pointer' {
		mut listener := unix.listen_stream(work + '/qmp.sock')!
		defer { listener.close() or {} }
		if mode == 'not-ready' {
			for { time.sleep(10 * time.millisecond) }
		}
		if mode in ['interrupt', 'terminate'] {
			for { time.sleep(10 * time.millisecond) }
		}
		emit('POINTER_SCROLL READY\n')!
		mut conn := listener.accept()!
		defer { conn.close() or {} }
		if mode == 'malformed' {
			conn.write_string('not JSON\n')!
			for { time.sleep(10 * time.millisecond) }
		}
		// The original accepts any JSON greeting, rather than demanding a QMP key.
		prefix := if mode == 'bom' { '\xef\xbb\xbf' } else { '' }
		conn.write_string(prefix + '[]\n')!
		assert read_request(mut conn)!['execute']!.str() == 'qmp_capabilities'
		conn.write_string(prefix + '{"return":{}}\n')!
		mut requests := []json2.Any{}
		for index, event in [['wheel-left', '-1', '0'], ['wheel-right', '1', '0'],
			['wheel-up', '0', '1'], ['wheel-down', '0', '-1']] {
			request := read_request(mut conn)!
			assert request['execute']!.str() == 'input-send-event' && 'id' !in request
			events := request['arguments']!.as_map()['events']!.as_array()
			assert events.len == 2
			for i, row in events {
				data := row.as_map()
				assert data['type']!.str() == 'btn'
				button := data['data']!.as_map()
				assert button['button']!.str() == event[0]
				assert button['down']!.bool() == (i == 0)
			}
			requests << json2.Any(request)
			if mode == 'qmp-error' {
				conn.write_string('{"error":{"desc":"native denied"}}\n')!
				for { time.sleep(10 * time.millisecond) }
			}
			conn.write_string(prefix + '{"event":"STOP"}\n' + prefix + '{"return":{}}\n')!
			if mode == 'serial-eof' { exit(0) }
			emit('POINTER_SCROLL dx=' + event[1] + ' dy=' + event[2] + '\n')!
			if index == 3 {
				os.write_file(work + '/qmp-requests.json', json2.encode(json2.Any(requests)))!
				emit('POINTER_SCROLL PASS\n')!
			}
		}
		for { time.sleep(10 * time.millisecond) }
	}
	return true
}

fn policies(root string) ! {
	goldens := json2.decode[json2.Any](os.read_file(root + '/tests/native-vm-tools/browser-profiles.json')!)!.as_map()['profiles']!.as_map()
	for name in ['chromium', 'firefox', 'desktop', 'libreoffice', 'package', 'first-run', 'steam'] {
		profile := vmhost.browser_profile(name)!
		original := goldens[name]!.as_map()
		assert profile.init == original['init']!.str() && profile.pass == original['pass']!.str()
		assert profile.features == original['features']!.as_array().map(it.str())
		assert profile.failures == original['failures']!.as_array().map(it.str())
		assert profile.persist == original['persist']!.str()
		flags := if name == 'chromium' { []string{} } else { ['--' + name] }
		args := vmhost.browser_options(root, flags)!
		assert args.profile == profile
		assert args.timeout == if name == 'package' { '5400' } else { '1800' }
		assert args.memory == if name == 'steam' { '32768' } else { '8192' }
		launch := vmhost.browser_launch(root, args, {
			'VINIX_QEMU_PERSIST':            '1'
			'VINIX_QEMU_PACKAGE_STORE_PORT': '321'
			'VINIX_QEMU_PACKAGE_PERSIST':    '1'
		}, 'Linux', '456')
		assert launch.command == [root + '/scripts/run-aarch64.sh', '--no-build', '--serial',
			'--mem=' + args.memory, '--guest-init=' + args.guest]
		assert 'VINIX_QEMU_PERSIST' !in launch.environment
		assert launch.environment['VINIX_QEMU_PACKAGE_STORE_PORT']! == '321'
		assert launch.environment['VINIX_QEMU_PACKAGE_PERSIST']! == '1'
		assert launch.environment['VINIX_QEMU_PERSIST_SIZE_MB']! == profile.persist
		assert launch.environment['USE_TCG']! == '1'
		markers := [...profile.features, profile.pass, ...profile.failures, 'FATAL EXCEPTION',
			'KERNEL PANIC']
		for mask in 0 .. (1 << markers.len) {
			mut output := ''
			mut expected := []string{}
			for index, marker in markers { if mask & (1 << index) != 0 { output += marker + '\n' } }
			for index, marker in [...profile.features, profile.pass] {
				if mask & (1 << index) == 0 {
					expected << 'ERROR: missing expected browser result: ' + marker
				}
			}
			for index, marker in [...profile.failures, 'FATAL EXCEPTION', 'KERNEL PANIC'] {
				if mask & (1 << (index + profile.features.len + 1)) != 0 {
					expected << 'ERROR: observed browser failure: ' + marker
				}
			}
			result := vmhost.BrowserResult{ bytes: output.bytes(), observed: sourcecommand.ChildExit{ exited: true } }
			assert vmhost.browser_failures(profile, result) == expected, name + ' ' + mask.str()
		}
	}
	for first in ['firefox', 'desktop', 'package', 'libreoffice', 'first-run', 'steam'] {
		for second in ['firefox', 'desktop', 'package', 'libreoffice', 'first-run', 'steam'] {
			if first == second { continue }
			mut rejected := false
			vmhost.browser_options(root, ['--' + first, '--' + second]) or { rejected = err.code() == 2 }
			assert rejected
		}
	}
	assert vmhost.browser_options(root, ['--timeout', '-1']) or {
		assert err.code() == 2
		vmhost.BrowserOptions{}
	} == vmhost.BrowserOptions{}
	for text, expected in {
		'ACTIVITY-CHECK DONE failures=0':                                 0
		'ACTIVITY-CHECK DONE failures=00':                                1
		'ACTIVITY-CHECK DONE failures=01':                                1
		'ACTIVITY-CHECK DONE failures=0x':                                0
		'ACTIVITY-CHECK FAIL\nACTIVITY-CHECK DONE failures=0':            1
		'ACTIVITY-CHECK DONE failures=١':                                 1
		'ACTIVITY-CHECK DONE failures=x\nACTIVITY-CHECK DONE failures=0': 0
	} {
		assert vmhost.activity_verdict(text.bytes()) == expected
	}
	baseline := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		assert vmhost.available_port()!.int() > 0
		assert os.ls('/dev/fd')!.len == baseline
	}
	println('PASS seven original profiles, exhaustive marker/report matrices, CLI exclusions/defaults, launch environments and 100 real port retirements')
}

fn send_signal(path string, signal i32) {
	until := time.sys_mono_now() + 10 * time.second
	for !os.exists(path) && time.sys_mono_now() < until { time.sleep(time.millisecond) }
	assert os.exists(path)
	C.raise(signal)
}

fn assert_dead(work string, pid string) ! {
	number := os.read_file(work + '/' + pid)!.int()
	until := time.sys_mono_now() + 5 * time.second
	for C.kill(i32(number), 0) == 0 && time.sys_mono_now() < until {
		time.sleep(10 * time.millisecond)
	}
	assert C.kill(i32(number), 0) != 0 && C.errno == C.ESRCH, work + '/' + pid
}

fn processes(work string) ! {
	baseline := os.ls('/dev/fd')!.len
	for family, modes in {
		'browser':  ['pass', 'split', 'large', 'descendant', 'fail', 'nonzero', 'early', 'timeout',
			'kill', 'overflow', 'interrupt', 'terminate']
		'activity': ['pass', 'fail', 'early', 'hang', 'descendant', 'interrupt', 'terminate']
		'pointer':  ['pass', 'bom', 'malformed', 'qmp-error', 'serial-eof', 'not-ready', 'interrupt',
			'terminate']
	} {
		for mode in modes {
			case := work + '/' + family + '-' + mode
			gamehost.mkdir(case)!
			guard := cachecli.own_commands()
			mut env := os.environ()
			env['VINIX_VM_CASE'] = case
			env['VINIX_VM_PROFILE'] = 'chromium'
			launch := vmhost.Launch{[os.executable(), 'mock', family, mode], env, case}
			sender := if mode in ['interrupt', 'terminate'] {
				spawn send_signal(case + '/child.pid', if mode == 'interrupt' {
					C.SIGINT
				} else {
					C.SIGTERM
				})
			} else {
				spawn no_signal()
			}
			if family == 'browser' {
				mut failed := false
				result := vmhost.browser_capture(launch, vmhost.browser_profile('chromium')!, if mode == 'overflow' {
					math.inf(1)
				} else if mode in ['timeout', 'kill'] {
					0.05
				} else {
					15
				}, false) or {
					failed = true
					vmhost.BrowserResult{}
				}
				assert failed == (mode in ['overflow', 'interrupt', 'terminate']), family + '/' + mode
				if !failed {
					assert (vmhost.browser_failures(vmhost.browser_profile('chromium')!, result).len == 0) == (mode in [
						'pass',
						'split',
						'large',
						'descendant',
					]), family + '/' + mode + ' ' + vmhost.browser_failures(vmhost.browser_profile('chromium')!, result).str()
				}
			} else if family == 'activity' {
				mut failed := false
				bytes := vmhost.activity_capture(launch, case + '/log', if mode == 'hang' {
					0.05
				} else {
					4
				}) or {
					failed = true
					[]u8{}
				}
				assert failed == (mode in ['interrupt', 'terminate']), family + '/' + mode
				if !failed {
					assert vmhost.activity_verdict(bytes) == if mode in ['pass', 'descendant'] {
						0
					} else {
						1
					}
					assert os.read_bytes(case + '/log')! == bytes
					if mode == 'pass' {
						assert bytes.bytestr().contains('diagnostic stderr')
					}
				}
			} else {
				mut failed := false
				vmhost.pointer_capture(launch, case + '/qmp.sock', case + '/log', if mode == 'not-ready' {
					0.05
				} else {
					4
				}) or {
					failed = true
					eprintln('pointer ' + mode + ' error: ' + err.msg())
				}
				assert failed == (mode !in ['pass', 'bom']), family + '/' + mode
				assert os.is_file(case + '/log')
				if mode in ['pass', 'bom'] {
					assert json2.decode[[]json2.Any](os.read_file(case + '/qmp-requests.json')!)!.len == 4
				}
			}
			sender.wait()
			guard.close()
			assert_dead(case, 'child.pid')!
			if mode == 'descendant' { assert_dead(case, 'descendant.pid')! }
			assert os.ls('/dev/fd')!.len == baseline, family + '/' + mode
			println('PASS actual owned ' + family + ' ' + mode)
			flush_stdout()
		}
	}
}

fn no_signal() {}

fn native_builds(root string, work string) ! {
	guard := cachecli.own_commands()
	defer { guard.close() }
	gamehost.mkdir(work)!
	for arch in ['aarch64', 'x86_64'] {
		directory := work + '/' + arch
		gamehost.mkdir(directory)!
		mut env := os.environ()
		binary := vmhost.activity_compile(root, root, directory, arch, env)!
		bytes := os.read_bytes(binary)!
		assert bytes[..4] == [u8(127), `E`, `L`, `F`] && bytes[18] == if arch == 'aarch64' {
			u8(183)
		} else {
			u8(62)
		}
		image := vmhost.init_archive(binary, directory, false)!
		mut reader := tarstream.open_plain(image)!
		mut names := []string{}
		for {
			member := reader.next() or {
				if err is tarstream.End { break }
				return err
			}
			names << member.name
			if member.name == './sbin/init' {
				mut content := []u8{len: int(member.size)}
				assert reader.read(mut content)! == content.len
				assert content == bytes
			}
		}
		reader.close()
		assert names == ['.', './dev', './root', './sbin', './sbin/init', './tmp']
	}
	directory := work + '/pointer'
	gamehost.mkdir(directory)!
	binary := vmhost.pointer_compile(root, directory, os.environ())!
	bytes := os.read_bytes(binary)!
	assert bytes[..4] == [u8(127), `E`, `L`, `F`] && bytes[18] == 183
	image := vmhost.init_archive(binary, directory, true)!
	mut reader := tarstream.open_plain(image)!
	assert reader.next()!.name == 'sbin'
	init := reader.next()!
	assert init.name == 'sbin/init' && init.mode == 0o755
	reader.close()
	println('PASS three real static guest ELFs and native USTAR initramfs member/byte/mode checks')
}

fn main() {
	if mock() or { panic(err) } { return }
	if os.args.len != 2 { exit(2) }
	work := os.args[1]
	gamehost.mkdir(work) or { panic(err) }
	root := os.real_path(os.dir(@FILE) + '/../..')
	policies(root) or { panic(err) }
	// Keep Unix socket names within the SDK limit even when the retained
	// qualification directory has a long absolute path.
	mut pattern := ('/tmp/vinix-vm-cases.XXXXXX\x00').bytes()
	assert C.mkdtemp(pattern.data) != unsafe { nil }
	process_root := pattern.bytestr().all_before('\x00')
	defer { gamehost.remove(process_root) or {} }
	processes(process_root) or { panic(err) }
	native_builds(root, work + '/native') or { panic(err) }
	os.write_file(work + '/passed', 'PASS\n') or { panic(err) }
}
