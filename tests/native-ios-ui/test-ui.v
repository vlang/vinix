// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import encoding.binary
import gamehost
import iosui
import json2
import net.unix
import os
import sourcecommand
import tarstream
import time

#include <poll.h>
struct C.pollfd {
pub mut:
	fd      i32
	events  i16
	revents i16
}

fn C.poll(&C.pollfd, usize, i32) i32
fn C.fork() i32
fn C.raise(i32) i32

fn read_fd(fd int, count int) ![]u8 {
	mut bytes := []u8{len: count}
	mut at := 0
	for at < count {
		n := unsafe { C.read(fd, &u8(bytes.data) + at, usize(count - at)) }
		if n <= 0 { return error('fixture read closed') }
		at += int(n)
	}
	return bytes
}

fn write_fd(fd int, bytes []u8, split bool) ! {
	mut at := 0
	for at < bytes.len {
		n := unsafe { C.write(fd, &u8(bytes.data) + at, usize(if split { 1 } else { bytes.len - at })) }
		if n <= 0 { return error('fixture write closed') }
		at += int(n)
	}
}

fn u32_bytes(value u32) []u8 {
	mut bytes := []u8{len: 4}
	binary.little_endian_put_u32(mut bytes, value)
	return bytes
}

fn element(text string, children [][]u8) []u8 {
	mut bytes := []u8{len: 274}
	bytes[0] = 2
	for index in 0 .. 12 {
		item := if index == 0 {
			'ios.7'
		} else if index == 3 {
			text
		} else {
			''
		}
		bytes << u32_bytes(u32(item.len))
		bytes << item.bytes()
	}
	bytes << u32_bytes(0)
	bytes << u32_bytes(u32(children.len))
	for child in children { bytes << child }
	return bytes
}

fn wire_fixture(mode string) ! {
	work := os.getenv('VINIX_IOS_UI_CASE')
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
	if mode in ['eof', 'descendant'] { return }
	if mode == 'hang' {
		for { time.sleep(10 * time.millisecond) }
	}
	if mode == 'large' {
		write_fd(1, 'o'.repeat(3 * 1024 * 1024).bytes(), false)!
		write_fd(2, 'e'.repeat(3 * 1024 * 1024).bytes(), false)!
	}
	request, response := os.getenv('VINIX_REQUEST_FD').int(), os.getenv('VINIX_RESPONSE_FD').int()
	mut reply := []u8{len: 128}
	for index, value in [u8(0x50), 0x50, 0x41, 0x56, 10, 0, 0, 0] { reply[index] = value }
	reply[56] = if mode == 'state' { u8(3) } else { u8(1) }
	if mode == 'magic' { reply[0] = 0 }
	if mode == 'length' { binary.little_endian_put_u32(mut reply[124..], 1024 * 1024 + 1) }
	write_fd(response, if mode == 'short' { reply[..17] } else { reply }, mode == 'split')!
	if mode in ['magic', 'length', 'state', 'short'] { return }
	for {
		header := read_fd(request, 136)!
		assert header[..8] == [u8(0x50), 0x50, 0x41, 0x56, 10, header[5], 0, 0]
		assert binary.little_endian_u32_at(header, 8) == 390 && binary.little_endian_u32_at(header, 12) == 680
		length := int(binary.little_endian_u32_at(header, 132))
		read_fd(request, length)!
		mut payload := if header[5] == 1 {
			element('hello 漢字 😀', [element('2', [])])
		} else {
			[]u8{}
		}
		if mode == 'utf8' && header[5] == 1 { payload = element('\xff', []) }
		if mode == 'menus' && header[5] == 1 {
			payload = element('', [])
			payload[payload.len - 8] = 1
		}
		if mode == 'children' && header[5] == 1 {
			payload = element('', [])
			payload[payload.len - 4] = 255
		}
		binary.little_endian_put_u32(mut reply[124..], u32(payload.len))
		write_fd(response, reply, mode == 'split')!
		write_fd(response, payload, mode == 'split')!
		if header[5] == 6 {
			if mode == 'stderr' { write_fd(2, 'fixture error'.bytes(), false)! }
			if mode == 'exit7' { exit(7) }
			return
		}
	}
}

fn request(mut connection unix.StreamConn) !map[string]json2.Any {
	mut bytes := []u8{}
	mut one := []u8{len: 1}
	for {
		if connection.read(mut one)! == 0 { return error('QMP fixture closed') }
		if one[0] == 10 { break }
		bytes << one[0]
	}
	return json2.decode[map[string]json2.Any](bytes.bytestr())!
}

fn desktop_fixture() ! {
	work := os.getenv('VINIX_IOS_UI_CASE')
	mode := os.getenv('VINIX_IOS_UI_MODE')
	os.write_file(work + '/child.pid', os.getpid().str())!
	assert os.args[1..4] == ['--no-build', '--serial', '--mem=2048']
	assert os.args[4].starts_with('--guest-init=')
	assert os.getenv('VINIX_QEMU_PERSIST_SIZE_MB') == '64' && os.getenv('VINIX_QEMU_NETWORK') == '0'
	assert os.getenv('VINIX_QEMU_PERSIST') == '' && os.getenv('VINIX_QEMU_OVERLAY') == '' && os.getenv('VINIX_QEMU_ROOT_DISK') == ''
	mut input := C.pollfd{ fd: 0, events: i16(C.POLLIN) }
	assert C.poll(&input, 1, 10) == 0 // stdin is an open idle pipe
	init := os.read_bytes(os.args[4].all_after('='))!
	assert init[..4] == [u8(127), `E`, `L`, `F`] && init[18] == 183
	for index in 0 .. int(binary.little_endian_u16_at(init, 56)) {
		at := int(binary.little_endian_u64_at(init, 32)) + index * int(binary.little_endian_u16_at(init, 54))
		assert binary.little_endian_u32_at(init, at) != 3 // no ELF interpreter
	}
	os.write_file_array(work + '/init.elf', init)!
	mut image := tarstream.open_plain(os.getenv('VINIX_INITRAMFS'))!
	mut found := map[string]bool{}
	for {
		member := image.next() or {
			if err is tarstream.End { break }
			return err
		}
		found[member.name] = true
		if member.name == './usr/bin/vinix-desktop' {
			mut data := []u8{len: int(member.size)}
			assert image.read(mut data)! == data.len && data.bytestr() == 'desktop fixture' && member.mode == 0o755
		}
		if member.name == './usr/lib/linked' {
			assert member.linkname == 'library'
		}
	}
	image.close()
	assert found['./usr/share/vinix/icons/calculator.qoi'] && found['./usr/lib/library'] && found['./usr/lib/linked']
	if mode == 'early' { exit(7) }
	if mode == 'fail' {
		println('FAIL: fixture boot')
		return
	}
	if mode == 'panic' {
		println('KERNEL PANIC fixture')
		return
	}
	if mode in ['timeout', 'interrupt', 'terminate'] {
		for { time.sleep(10 * time.millisecond) }
	}
	path := os.getenv('VINIX_QEMU_EXTRA').all_after('-qmp unix:').all_before(',server,nowait')
	mut listener := unix.listen_stream(path)!
	defer { listener.close() or {} }
	println('vinix-desktop: ready')
	flush_stdout()
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	connection.write_string(if mode == 'malformed' { 'not JSON\n' } else { '[]\n' })!
	if mode == 'malformed' {
		for { time.sleep(10 * time.millisecond) }
	}
	mut requests := []json2.Any{}
	mut stamps := []json2.Any{}
	for {
		row := request(mut connection)!
		assert 'id' !in row
		requests << json2.Any(row)
		stamps << json2.Any(time.sys_mono_now())
		name := row['execute']!.str()
		if name == 'screendump' {
			output := row['arguments']!.as_map()['filename']!.str()
			os.write_file(output, 'P6\n1 1\n255\n\x01\x02\x03')!
			if !output.ends_with('-before.ppm') && mode != 'score' {
				println('iOS UILabel: 12\niOS UILabel: SCORE: 4\niOS UILabel: SCORE: 12')
				flush_stdout()
			}
		}
		connection.write_string(if mode == 'qmp-error' {
			'{"error":{"class":"fixture"}}\n'
		} else {
			'{"event":"STOP"}\n{"return":{}}\n'
		})!
		if name == 'quit' {
			os.write_file(work + '/requests.json', json2.encode(requests))!
			os.write_file(work + '/stamps.json', json2.encode(stamps))!
			return
		}
	}
}

fn gone(work string, name string) ! {
	pid := os.read_file(work + '/' + name)!.int()
	deadline := time.sys_mono_now() + 3 * time.second
	for time.sys_mono_now() < deadline {
		if C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH { return }
		time.sleep(10 * time.millisecond)
	}
	return error('process remains: ' + name + '/' + pid.str())
}

fn send_signal(work string, signal i32) {
	deadline := time.sys_mono_now() + 5 * time.second
	for !os.exists(work + '/child.pid') && time.sys_mono_now() < deadline {
		time.sleep(time.millisecond)
	}
	C.raise(signal)
}

fn wire_cases(work string) ! {
	baseline := os.ls('/dev/fd')!.len
	for mode in ['pass', 'split', 'large', 'utf8', 'menus', 'children', 'eof', 'magic', 'length',
		'state', 'short', 'stderr', 'exit7', 'descendant', 'interrupt', 'terminate'] {
		case := work + '/' + mode
		gamehost.mkdir(case)!
		os.setenv('VINIX_IOS_UI_CASE', case, true)
		guard := cachecli.own_commands()
		mut failed := false
		if mode in ['interrupt', 'terminate'] {
			sender := spawn send_signal(case, if mode == 'interrupt' { C.SIGINT } else { C.SIGTERM })
			iosui.client(os.executable(), 'wire/hang') or {
				failed = true
				iosui.Client{}
			}
			sender.wait()
			assert cachecli.cancelled()
		} else {
			wire_case(mode) or { failed = true }
		}
		assert failed == (mode !in ['pass', 'split', 'large']), mode
		guard.close()
		gone(case, 'child.pid')!
		if mode == 'descendant' { gone(case, 'descendant.pid')! }
		assert os.ls('/dev/fd')!.len == baseline, mode
	}
	for index in 0 .. 100 {
		case := work + '/eof-' + index.str()
		gamehost.mkdir(case)!
		os.setenv('VINIX_IOS_UI_CASE', case, true)
		guard := cachecli.own_commands()
		mut failed := false
		iosui.client(os.executable(), 'wire/eof') or {
			failed = true
			iosui.Client{}
		}
		assert failed
		mut missing := false
		sourcecommand.spawn_duplex('/missing-vinix-ios-fixture'.split(' '), os.environ(), 'VINIX_REQUEST_FD', 'VINIX_RESPONSE_FD') or {
			missing = true
			sourcecommand.DuplexChild{}
		}
		assert missing
		guard.close()
		gone(case, 'child.pid')!
		assert os.ls('/dev/fd')!.len == baseline
	}
	println('PASS 16 protocol/diagnostic/exit/signal cases and 100 EOF/spawn retirement cycles')
}

fn wire_case(mode string) ! {
	mut connection := iosui.client(os.executable(), 'wire/' + mode)!
	defer { connection.child.close() or {} }
	tree := connection.build()!
	assert tree.text == 'hello 漢字 😀' && tree.id == 'ios.7' && tree.children.len == 1 && tree.children[0].text == '2'
	connection.send(3, 'C2+3='.bytes())!
	if mode == 'large' {
		assert connection.child.stdout.len == 3 * 1024 * 1024 && connection.child.stderr.len == 3 * 1024 * 1024
		connection.child.close()!
		connection.child.close()!
		return
	}
	connection.close()!
	connection.close()!
}

fn codec_cases() ! {
	valid := element('native', [])
	assert iosui.decode_tree(valid)!.text == 'native'
	for length in 0 .. valid.len {
		mut failed := false
		iosui.decode_tree(valid[..length]) or {
			failed = true
			iosui.Element{}
		}
		assert failed, length.str()
	}
	mut trailing := valid.clone()
	trailing << 0
	mut failed := false
	iosui.decode_tree(trailing) or {
		failed = true
		iosui.Element{}
	}
	assert failed
	mut nested := valid.clone()
	for _ in 0 .. 514 { nested = element('', [nested]) }
	failed = false
	iosui.decode_tree(nested) or {
		failed = true
		iosui.Element{}
	}
	assert failed
	assert iosui.desktop_score('iOS UILabel: SCORE: 4\niOS UILabel: SCORE: 128\niOS UILabel: SCORE: x\n')! == 128
	assert iosui.desktop_score('missing')! == -1
	for value in [0.5, 1.5, 2.5, -0.5, -1.5] {
		events := iosui.absolute_events(value * 2048 / 32767, 0)
		expected := [0, 2, 2, 0, -2][[0.5, 1.5, 2.5, -0.5, -1.5].index(value)]
		assert events[0].as_map()['data']!.as_map()['value']!.int() == expected
	}
	println('PASS every truncated element prefix, nesting bound, Unicode and ties-to-even coordinates')
}

fn desktop_cases(work string) ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	project := work + '/project'
	for directory in ['tests/ios', 'desktop/assets', 'scripts', 'build/ios/staging/usr/lib'] {
		gamehost.mkdir(project + '/' + directory)!
	}
	gamehost.copy_file(root + '/tests/ios/desktop-init.c', project + '/tests/ios/desktop-init.c')!
	gamehost.copy_file(root + '/desktop/assets/calculator.qoi', project + '/desktop/assets/calculator.qoi')!
	os.symlink(root + '/build-aarch64-userland', project + '/build-aarch64-userland')!
	os.symlink(os.executable(), project + '/scripts/run-aarch64.sh')!
	os.write_file(project + '/build/ios/staging/usr/lib/library', 'native library')!
	os.symlink('library', project + '/build/ios/staging/usr/lib/linked')!
	os.write_file(project + '/desktop-binary', 'desktop fixture')!
	os.chmod(project + '/desktop-binary', 0o755)!
	os.setenv('PATH', '/opt/homebrew/opt/llvm/bin:' + os.getenv('PATH'), true)
	baseline := os.ls('/dev/fd')!.len
	for mode in ['calculator', '2048', 'early', 'fail', 'panic', 'timeout', 'malformed', 'qmp-error',
		'score', 'interrupt', 'terminate'] {
		case := work + '/' + mode
		gamehost.mkdir(case)!
		os.setenv('VINIX_IOS_UI_CASE', case, true)
		os.setenv('VINIX_IOS_UI_MODE', mode, true)
		for name in ['VINIX_QEMU_PERSIST', 'VINIX_QEMU_OVERLAY', 'VINIX_QEMU_ROOT_DISK'] {
			os.setenv(name, 'must be removed', true)
		}
		guard := cachecli.own_commands()
		sender := spawn desktop_signal(case, mode)
		mut failed := false
		app := if mode == '2048' { '2048' } else { 'calculator' }
		iosui.desktop(project, project + '/desktop-binary', if mode == 'timeout' { 1 } else { 10 }, app) or {
			failed = true
			eprintln(mode + ': ' + err.msg())
		}
		assert failed == (mode !in ['calculator', '2048']), mode
		sender.wait()
		if mode in ['interrupt', 'terminate'] {
			assert cachecli.cancelled()
		}
		guard.close()
		gone(case, 'child.pid')!
		assert os.ls('/dev/fd')!.len == baseline, mode
		if !failed {
			rows := json2.decode[[]json2.Any](os.read_file(case + '/requests.json')!)!
			assert rows.len == if mode == 'calculator' { 12 } else { 150 }
			assert rows[0].as_map()['execute']!.str() == 'qmp_capabilities' && rows.last().as_map()['execute']!.str() == 'quit'
			verify_events(rows, mode)!
			assert os.read_file(project + '/build/ios/' + app + '.ppm')!.starts_with('P6\n1 1\n')
			stamps := json2.decode[[]json2.Any](os.read_file(case + '/stamps.json')!)!
			assert stamps[1].i64() - stamps[0].i64() >= 950 * time.millisecond
			assert stamps[3].i64() - stamps[2].i64() >= 140 * time.millisecond
		}
	}
	println('PASS 11 actual logged-pipe/Unix-QMP desktop cases, static AArch64 init and USTAR staging')
}

fn desktop_signal(work string, mode string) {
	if mode in ['interrupt', 'terminate'] {
		send_signal(work, if mode == 'interrupt' { C.SIGINT } else { C.SIGTERM })
	}
}

fn verify_events(rows []json2.Any, mode string) ! {
	mut expected := [][]json2.Any{}
	points := if mode == 'calculator' {
		[[177.75, 441.75], [452.25, 624.75], [269.25, 533.25], [452.25, 716.25]]
	} else {
		[[280.0, 378.0]]
	}
	for point in points {
		mut event := iosui.absolute_events(point[0], point[1])
		event << json2.Any({
			'type': json2.Any('btn')
			'data': json2.Any({
				'button': json2.Any('left')
				'down':   json2.Any(true)
			})
		})
		expected << event
		expected << [json2.Any({
			'type': json2.Any('btn')
			'data': json2.Any({
				'button': json2.Any('left')
				'down':   json2.Any(false)
			})
		})]
	}
	if mode == '2048' {
		directions := [[420, 434, 220, 434], [315, 534, 315, 334], [220, 434, 420, 434],
			[315, 334, 315, 534]]
		for index in 0 .. 16 {
			point := directions[index % 4]
			expected << iosui.absolute_events(point[0], point[1])
			expected << [json2.Any({
				'type': json2.Any('btn')
				'data': json2.Any({
					'button': json2.Any('left')
					'down':   json2.Any(true)
				})
			})]
			for step in 1 .. 7 {
				expected << iosui.absolute_events(point[0] + f64(point[2] - point[0]) * step / 6, point[1] + f64(point[3] - point[1]) * step / 6)
			}
			expected << [json2.Any({
				'type': json2.Any('btn')
				'data': json2.Any({
					'button': json2.Any('left')
					'down':   json2.Any(false)
				})
			})]
		}
	}
	actual := rows.filter(it.as_map()['execute'] or { json2.Any('') } == json2.Any('input-send-event'))
	assert actual.len == expected.len
	for index, row in actual {
		// Decoded JSON numbers use i64; normalize the frozen input sequence to
		// the same JSON representation before comparing the complete wire data.
		canonical := json2.decode[[]json2.Any](json2.encode(expected[index]))!
		assert row.as_map()['arguments']!.as_map()['events']!.as_array() == canonical, json2.encode(row)
	}
}

fn run() ! {
	if os.args.len > 1 && os.args[1] == '--no-build' {
		desktop_fixture()!
		return
	}
	if os.args.len == 2 && os.args[1].starts_with('wire/') {
		wire_fixture(os.args[1].all_after('wire/'))!
		return
	}
	if os.args.len != 2 { return error('expected new evidence directory') }
	work := os.args[1]
	if os.exists(work) { return error('evidence already exists') }
	gamehost.mkdir(work)!
	codec_cases()!
	wire_cases(work + '/wire')!
	desktop_cases(work + '/desktop')!
	os.write_file(work + '/passed', 'PASS\n')!
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(1)
	}
}
