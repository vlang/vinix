// SPDX-License-Identifier: GPL-2.0-or-later
module main

import emulatorhost as e
import fixturehost
import guesthost
import hosttest
import json2
import net.unix
import os
import policyhost
import time

#include <signal.h>
fn C.kill(i32, i32) i32
fn C.fcntl(i32, i32, ...voidptr) i32

fn stdio_child() ! {
	for fd in 0 .. 3 { need(C.fcntl(fd, C.F_GETFD) >= 0, 'missing child standard descriptor')! }
	output := [u8(`A`), 0, `B`]!
	errors := [u8(`C`), 0, `D`]!
	need(C.write(1, &output[0], 3) == 3 && C.write(2, &errors[0], 3) == 3, 'binary child streams')!
}
fn stdio_layout(work string, mode int) ! {
	mut saved := [3]i32{init: -1}
	mut flags := [3]i32{}
	for fd in 0 .. 3 {
		flags[fd] = C.fcntl(fd, C.F_GETFD)
		saved[fd] = C.fcntl(fd, C.F_DUPFD_CLOEXEC, 20)
	}
	defer {
		for fd in 0 .. 3 { if saved[fd] >= 0 { C.dup2(saved[fd], fd); C.fcntl(fd, C.F_SETFD, flags[fd]); C.close(saved[fd]) } }
	}
	mut selection := mode
	mut expected := [3]i32{}
	for fd in 0 .. 3 {
		choice := selection % 3
		selection /= 3
		if choice == 1 { C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) } else if choice == 2 { C.close(fd) }
		expected[fd] = C.fcntl(fd, C.F_GETFD)
	}
	mut child := fixturehost.spawn_logged([os.executable(), '--stdio-child'], policyhost.environment(), policyhost.caller_arch(), '', work + '/layout-' + mode.str() + '.log')!
	need(child.wait_for(5, policyhost.command_interrupted)! == 0, 'stdio child status')!
	child.close()
	for fd in 0 .. 3 { need(C.fcntl(fd, C.F_GETFD) == expected[fd], 'parent standard descriptor changed')! }
	need(os.read_bytes(work + '/layout-' + mode.str() + '.log')! == [u8(`A`), 0, `B`, `C`, 0, `D`], 'stdio layout binary log')!
}

fn need(condition bool, message string) ! { if !condition { return error(message) } }
fn fd_count() int { return (os.ls('/dev/fd') or { os.ls('/proc/self/fd') or { []string{} } }).len }

fn line(mut connection unix.StreamConn, mut pending []u8) !string {
	for {
		end := pending.index(u8(10))
		if end >= 0 { result := pending[..end].bytestr(); pending = pending[end + 1..].clone(); return result }
		mut buffer := []u8{len: 8192}
		count := connection.read(mut buffer)!
		pending << buffer[..count]
	}
	return error('unreachable server read')
}
fn screenshot(name string, first bool) ! {
	phase := if name.ends_with('desktop-title.ppm') { 0 } else if name.ends_with('desktop-gameplay.ppm') { if first { 1 } else { 6 } }
		else if name.ends_with('desktop-animated.ppm') { 2 } else if name.ends_with('desktop-controller.ppm') { 3 }
		else if name.ends_with('desktop-analog.ppm') { 4 } else { 5 }
	mut data := 'P6\n2048 1536\n255\n'.bytes()
	data << []u8{len: 2048 * 1536 * 3, init: u8(phase * 31)}
	os.write_file_array(name, data)!
}
fn server(path string, kind string, mode string) ! {
	mut listener := unix.listen_stream(path)!
	defer { listener.close() or {}; listener.unlink() or {} }
	println('vinix-desktop: ready\n' + e.label(kind) + ': loaded'); flush_stdout()
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	connection.write_string('{"QMP":{"version":{}}}\n')!
	mut pending := []u8{}
	mut first := true
	for {
		request := json2.decode[json2.Any](line(mut connection, mut pending)!)!.as_map()
		command := request['execute']!.str()
		parameters := request['arguments']!.as_map()
		println(json2.encode({'time': json2.Any(f64(time.sys_mono_now()) / 1e9), 'request': json2.Any(request)})); flush_stdout()
		if command != 'qmp_capabilities' && mode == 'malformed' { connection.write_string('{bad\n')!; return }
		if command != 'qmp_capabilities' && mode == 'eof' { return }
		if command != 'qmp_capabilities' && mode == 'quiet' { for { time.sleep(25 * time.millisecond) } }
		if command != 'qmp_capabilities' && mode == 'error' { connection.write_string('{"error":{"class":"Bad","desc":"deliberate"},"return":true}\n')!; continue }
		if command == 'screendump' {
			name := parameters['filename']!.str()
			screenshot(name, first)!
			if name.ends_with('desktop-gameplay.ppm') { first = false }
		}
		if command == 'input-send-event' {
			events := parameters['events']!.as_array()
			if events.len == 3 {
				x := events[0].as_map()['data']!.as_map()['value']!.int()
				y := events[1].as_map()['data']!.as_map()['value']!.int()
				if x == e.rounded(f64(903) * 32767 / 2048) && y == e.rounded(f64(77) * 32767 / 1536) { println(e.label(kind) + ': clean shutdown'); flush_stdout() }
			}
		}
		if command == 'number' { connection.write_string('{"event":"ASYNC"}\n{"return":184467440737095516160001}\n')! }
		else { connection.write_string('{"return":{}}\n')! }
		if command == 'quit' { return }
	}
}

fn staging(work string) ! {
	source := work + '/source'
	target := work + '/target'
	e.mkdir(source + '/tracks')!
	os.write_file(source + '/set.m3u', ' # comment\u0085disc.cue\u2028./set.m3u\u2029alias.cue\n')!
	os.write_file(source + '/disc.cue', '  fILe "tracks\\one.bin" BINARY\r\nFILE tracks/two.bin BINARY\nFILE ignored.bin\n')!
	os.write_file(source + '/tracks/one.bin', '\x00\xff\x80one')!
	os.write_file(source + '/tracks/two.bin', 'two')!
	os.chmod(source + '/tracks/two.bin', 0o751)!
	os.symlink('disc.cue', source + '/alias.cue')!
	e.stage_game('ps1', source + '/set.m3u', target + '/set.m3u')!
	need(os.read_bytes(target + '/tracks/one.bin')! == '\x00\xff\x80one'.bytes(), 'binary CUE track')!
	need(os.read_file(target + '/tracks/two.bin')! == 'two', 'second CUE track')!
	need(!os.exists(target + '/alias.cue'), 'physical source deduplication')!
	need((os.stat(target + '/tracks/two.bin')!).mode & 0o777 == 0o751, 'copy2 permissions')!
	for name in ['../escape.bin', '/absolute.bin', 'tracks/../../escape.bin'] {
		os.write_file(source + '/bad.cue', 'FILE "' + name + '" BINARY\n')!
		if _ := e.stage_game('ps1', source + '/bad.cue', target + '/bad.cue') { return error('unsafe CUE reference accepted') }
	}
	os.write_file(source + '/bad.m3u', '\xff')!
	if _ := e.stage_game('ps1', source + '/bad.m3u', target + '/bad.m3u') { return error('invalid UTF-8 accepted') }
	os.symlink('absent', source + '/dangling')!
	timestamps := [C.timespec{1700000000, 123456789}, C.timespec{1700000001, 987654321}]!
	need(C.utimensat(C.AT_FDCWD, (source + '/dangling').str, &timestamps[0], C.AT_SYMLINK_NOFOLLOW) == 0, 'source link timestamps')!
	e.stage_tree(source, work + '/merged')!
	need(os.readlink(work + '/merged/dangling')! == 'absent', 'dangling link copied literally')!
	need((os.lstat(work + '/merged/dangling')!).mtime == 1700000001, 'symlink timestamp copied')!
	for kind in ['n64', 'ps2'] { e.stage_game(kind, source + '/tracks/one.bin', work + '/' + kind + '/one.bin')! }
	mut rom := []u8{len: 8192, init: u8(index % 251)}
	half, word, stalled := e.n64_variants(rom)!
	for index in 0 .. rom.len { need(half[index] == rom[index ^ 1] && word[index] == rom[index ^ 3], 'ROM byte orders')! }
	need(stalled[..0x40] == rom[..0x40] && stalled[0x1000..] == rom[0x1000..] && stalled[0x43] == 8, 'budget mutation bounds')!
	for index in 0x40 .. 0x1000 { need(stalled[index] == if index == 0x43 { 8 } else { 0 }, 'budget instructions')! }
	rom.delete_last()
	if _, _, _ := e.n64_variants(rom) { return error('unaligned ROM accepted') }
	for kind in ['n64', 'ps1', 'ps2'] {
		markers := e.features(kind, true)
		need(markers.len == if kind == 'n64' { 12 } else if kind == 'ps1' { 7 } else { 8 }, 'all guest feature markers')!
		text := markers.join('\n')
		need(guesthost.abi_verdict(text, 'aarch64', markers, [e.label(kind) + ' FAIL:'], true, false, 0) == 0, 'guest verdict')!
		need(guesthost.abi_verdict(text + '\n' + markers[0], 'aarch64', markers, [], true, false, 0) == 1, 'duplicate guest result')!
	}
	println('PASS CUE/M3U closure, stat/link staging, ROM variants and guest marker gates')
}

fn pixels() ! {
	mut data := 'P6\t02048\n01536\r255 '.bytes()
	data << []u8{len: 2048 * 1536 * 3, init: u8(index % 251)}
	for kind in ['n64', 'ps1', 'ps2'] {
		actual := e.game_pixels(data, kind)!
		rect := e.game_rect(kind)
		need(actual.len == rect.width * rect.height * 3, 'crop dimensions')!
		for row in 0 .. rect.height {
			for col in 0 .. rect.width * 3 {
				expected := u8((((rect.y + row) * 2048 + rect.x) * 3 + col) % 251)
				if actual[row * rect.width * 3 + col] != expected { return error('crop pixel differs') }
			}
		}
	}
	for prefix in ['P3\n2048 1536\n255\n', 'P6\n2048 1536\n256\n', 'P6\n2047 1536\n255\n', 'P6\n2048 1536\n255\r\n'] {
		mut bad := prefix.bytes(); bad << data[data.len - 2048 * 1536 * 3..]
		if _ := e.game_pixels(bad, 'n64') { return error('invalid PPM accepted') }
	}
	need(e.changed([u8(1), 2, 3, 4], [u8(1), 2]) == 2, 'partial RGB slices')!
	need(e.rounded(2.5) == 2 && e.rounded(3.5) == 4 && e.rounded(-2.5) == -2 && e.rounded(-3.5) == -4, 'ties to even')!
	println('PASS complete RGB crops, P6 boundaries, changed pixels and ties-to-even coordinates')
}

fn wait_socket(path string, mut child fixturehost.LoggedChild) ! {
	end := time.sys_mono_now() + u64(5 * time.second)
	for !os.exists(path) {
		if child.poll()! || time.sys_mono_now() >= end { return error('controlled QMP server did not start') }
		time.sleep(10 * time.millisecond)
	}
}
fn qmp_cases(work string) ! {
	baseline := fd_count()
	for _ in 0 .. 128 { if _ := e.qmp_connect(work + '/missing.sock') { return error('missing QMP socket connected') } }
	need(fd_count() == baseline, 'failed QMP connections leak descriptors')!
	for mode in ['normal', 'error', 'malformed', 'eof'] {
		path := work + '/qmp-' + mode
		log := work + '/qmp-' + mode + '.log'
		mut child := fixturehost.spawn_logged([os.executable(), '--server', path, 'n64', mode], policyhost.environment(), policyhost.caller_arch(), '', log)!
		wait_socket(path, mut child)!
		mut q := e.qmp_connect(path)!
		if mode == 'normal' {
			value := q.call('number', {})!
			need(value is e.QmpNumber && value.text == '184467440737095516160001', 'exact large QMP integer')!
			q.move(130, 350)!
			q.click(520, 581)!
			q.hold(441, 606, 0.08)!
			q.drag(520, 663, 380, 663, 0.08)!
			q.call('quit', {})!
			child.wait_for(5, policyhost.command_interrupted)!
			mut rows := []map[string]json2.Any{}
			for text in os.read_file(log)!.split_into_lines() { if text.starts_with('{') { rows << json2.decode[json2.Any](text)!.as_map() } }
			need(rows.len == 11, 'QMP complete input sequence')!
			for first, second in {3:4, 5:6, 7:8, 8:9} {
				duration := rows[second]['time']!.f64() - rows[first]['time']!.f64()
				need(duration >= if first == 3 { 0.14 } else if first == 5 { 0.07 } else if first == 7 { 0.24 } else { 0.07 }, 'pointer sleep was shortened')!
			}
		} else { if _ := q.call('bad', {}) { return error('invalid QMP reply accepted') } }
		q.close(); q.close(); child.close()
	}
	need(fd_count() == baseline, 'QMP success/failure retirement')!
	path := work + '/qmp-quiet'
	mut server_child := fixturehost.spawn_logged([os.executable(), '--server', path, 'n64', 'quiet'], policyhost.environment(), policyhost.caller_arch(), '', work + '/quiet-server.log')!
	defer { server_child.close() }
	wait_socket(path, mut server_child)!
	mut client := fixturehost.spawn_logged([os.executable(), '--cancel-client', path], policyhost.environment(), policyhost.caller_arch(), '', work + '/quiet-client.log')!
	defer { client.close() }
	end := time.sys_mono_now() + u64(5 * time.second)
	for !os.read_file(work + '/quiet-server.log')!.contains('waiting') {
		need(time.sys_mono_now() < end && !client.poll()!, 'QMP cancellation client did not reach reply wait')!
		time.sleep(10 * time.millisecond)
	}
	started := time.sys_mono_now()
	C.kill(client.pid, C.SIGINT)
	need(client.wait_for(5, policyhost.command_interrupted)! == 130, 'QMP interrupt status')!
	need(time.sys_mono_now() - started < u64(time.second), 'QMP interrupt delayed')!
	println('PASS Unix QMP events, errors, EOF, malformed JSON, arbitrary integers, ordered input and measured sleeps')
	println('PASS SIGINT during an unanswered QMP command')
}

fn scenarios(work string) ! {
	for kind in ['n64', 'ps1', 'ps2'] {
		path := work + '/desktop-' + kind
		log := work + '/desktop-' + kind + '.log'
		e.mkdir(work + '/' + kind)!
		mut child := fixturehost.spawn_logged([os.executable(), '--server', path, kind, 'normal'], policyhost.environment(), policyhost.caller_arch(), '', log)!
		defer { child.close() }
		wait_socket(path, mut child)!
		e.desktop_scenario(kind, work + '/' + kind, log, path, 60, mut child)!
		need(child.poll()!, 'desktop quit reaped')!
		println('PASS complete controlled desktop: ' + kind)
	}
}

fn logged_children(work string) ! {
	baseline := fd_count()
	for index in 0 .. 64 {
		mut child := fixturehost.spawn_logged(['/usr/bin/printf', r'a\000b'], policyhost.environment(), policyhost.caller_arch(), '', work + '/binary.log')!
		need(child.wait_for(5, policyhost.command_interrupted)! == 0, 'logged child status')!
		child.close(); child.close()
		need(os.read_bytes(work + '/binary.log')! == [u8(`a`), 0, `b`], 'merged raw log')!
		if index % 8 == 0 { need(fd_count() == baseline, 'logged child retirement')! }
	}
	mut child := fixturehost.spawn_logged(['/bin/sh', '-c', 'sleep 120 & echo $!; wait'], policyhost.environment(), policyhost.caller_arch(), '', work + '/descendant.log')!
	for os.file_size(work + '/descendant.log') == 0 { time.sleep(10 * time.millisecond) }
	descendant := os.read_file(work + '/descendant.log')!.trim_space().int()
	child.close()
	need(C.kill(child.pid, 0) != 0 && C.errno == C.ESRCH, 'direct child still live')!
	// The descendant may be an init-owned zombie briefly on Linux.
	for _ in 0 .. 100 { if C.kill(descendant, 0) != 0 { break }; time.sleep(10 * time.millisecond) }
	need(C.kill(descendant, 0) != 0 && C.errno == C.ESRCH, 'descendant still live')!
	println('PASS 64 logged children, binary output, repeated close and private descendant retirement')
	for mode in 0 .. 27 { stdio_layout(work, mode)! }
	need(fd_count() == baseline, 'stdio layout descriptor retirement')!
	println('PASS all 27 open/CLOEXEC/closed standard descriptor layouts')
}

fn checked() ! {
	if os.args.len == 2 && os.args[1] == '--stdio-child' { stdio_child()!; return }
	if os.args.len == 3 && os.args[1] == '--cancel-client' {
		guard := policyhost.own_commands(); defer { guard.close() }
		mut q := e.qmp_connect(os.args[2])!; defer { q.close() }
		q.call('waiting', {})!
		return
	}
	if os.args.len == 5 && os.args[1] == '--server' { server(os.args[2], os.args[3], os.args[4])!; return }
	guard := policyhost.own_commands()
	defer { guard.close() }
	work := hosttest.work_dir('', 'vinix-emulator-check-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	staging(work)!
	pixels()!
	qmp_cases(work)!
	logged_children(work)!
	scenarios(work)!
	println('Emulator controller checks PASS')
}
fn main() { checked() or { eprintln(err.msg()); exit(if err.code() == 130 { 130 } else { 1 }) } }
