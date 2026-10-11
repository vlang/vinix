// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Login sessions and the seat on a booted kernel: every session is a login
// the kernel knows and that cannot be relabelled, and the display, the
// pointer and the console can be used by the session at the machine, by the
// system, and by nobody else -- including through a descriptor that was
// opened while its session still had the seat.
module main

import os

// The devices of the seat a test machine has.
const seat_devices = ['/dev/fb0', '/dev/pointer', '/dev/console']

fn try_device(path string) string {
	if !os.exists(path) {
		return 'absent'
	}
	// The console is written; the others are read.
	flags := if path == '/dev/console' { C.O_WRONLY } else { C.O_RDONLY | C.O_NONBLOCK }
	fd := C.open(&char(path.str), flags)
	if fd < 0 {
		return 'errno ${C.errno}'
	}
	C.close(fd)
	return 'ok'
}

fn probe_seat_try() int {
	for path in seat_devices {
		println('try ${path} ${try_device(path)}')
	}
	return 0
}

fn wait_for_file(path string) {
	for _ in 0 .. 600 {
		if os.exists(path) {
			return
		}
		C.usleep(50_000)
	}
}

fn read_some(fd int) string {
	mut buffer := [16]u8{}
	got := C.read(fd, &buffer[0], 16)
	// Nothing to read from a device that would otherwise wait is not a
	// refusal.
	if got < 0 && C.errno != 11 {
		return 'errno ${C.errno}'
	}
	return 'ok'
}

// Open the display, then use that same descriptor again each time the
// scenario says the seat has moved.
fn probe_seat_hold() int {
	fd := C.open(c'/dev/fb0', C.O_RDONLY | C.O_NONBLOCK)
	println('open ${if fd >= 0 { 'ok' } else { 'errno ${C.errno}' }}')
	println('read1 ${read_some(fd)}')
	os.write_file('/tmp/seat-ready-1', '') or {}
	wait_for_file('/tmp/seat-step-1')
	println('read2 ${read_some(fd)}')
	println('reopen ${try_device('/dev/fb0')}')
	os.write_file('/tmp/seat-ready-2', '') or {}
	wait_for_file('/tmp/seat-step-2')
	println('read3 ${read_some(fd)}')
	println('reopen2 ${try_device('/dev/fb0')}')
	return 0
}

// One write() and whether the kernel took it.
fn write_once(path string, text string) bool {
	fd := C.open(&char(path.str), C.O_WRONLY)
	if fd < 0 {
		return false
	}
	put := C.write(fd, text.str, usize(text.len))
	C.close(fd)
	return put == text.len
}

fn seat_now() string {
	return read_text('/proc/sys/kernel/seat_session').trim_space()
}

fn scenario_seat(mut t Test) {
	db := t.make_accounts()
	alex := must_user(db, 'alex')
	sam := must_user(db, 'sam')
	os.chmod('/tmp', 0o1777) or {}

	// Which of the seat's devices this machine has. Without the display the
	// rest of the scenario would test nothing.
	system := run(['/sbin/init', 'probe', 'seat-try'], '', none, none).output
	t.info('as the system: ${system.trim_space().replace('\n', ', ')}')
	t.check(system.contains('try /dev/fb0 ok'), 'the system cannot open the display: ${system}')
	t.check(!system.contains('errno'), 'the system is refused a device of the seat: ${system}')
	t.check(seat_now() == '0', 'the seat is held by ${seat_now()} before anyone logged in')

	// The system itself has no login.
	t.check(read_text('/proc/self/loginuid').trim_space() == '4294967295'
		&& read_text('/proc/self/sessionid').trim_space() == '0', 'init has a login: ${read_text('/proc/self/loginuid').trim_space()}/${read_text('/proc/self/sessionid').trim_space()}')

	// A process that is not root and has no login: a service gone astray.
	stray := run(['/sbin/init', 'probe', 'seat-try'], '', db, sam).output
	t.check(!stray.contains(' ok'), 'a process without a login and without root opened a device of the seat: ${stray}')

	// A login session that is not at the machine.
	away := run(['/usr/sbin/vinix-session', 'run', 'sam', '/sbin/init', 'probe', 'seat-try'],
		'', none, none).output
	t.check(!away.contains(' ok') && away.contains('try /dev/fb0 errno 13'), 'a session that does not hold the seat opened its devices: ${away.trim_space().replace('\n', ', ')}')
	ids := run(['/usr/sbin/vinix-session', 'run', 'sam', '/sbin/init', 'probe', 'ids'],
		'', none, none).output
	first := ids.all_after(' login=').trim_space()
	t.check(first.starts_with('${sam.uid}/') && first != '${sam.uid}/0', 'a session\'s login is ${first}')
	again := run(['/usr/sbin/vinix-session', 'run', 'sam', '/sbin/init', 'probe', 'ids'],
		'', none, none).output.all_after(' login=').trim_space()
	t.check(again.starts_with('${sam.uid}/') && again != first, 'two logins have the same session: ${first} and ${again}')
	// It cannot make itself another login, or give itself the seat.
	for path in ['/proc/self/loginuid', '/proc/sys/kernel/seat_session'] {
		got := run(['/usr/sbin/vinix-session', 'run', 'sam', '/sbin/init', 'probe', 'write', path],
			'', none, none).output.trim_space()
		t.check(got == 'errno 13' || got == 'errno 1', 'sam writing ${path}: ${got}')
	}
	t.check(seat_now() == '0', 'the seat moved to ${seat_now()}')

	// Root labels itself once.
	child := C.fork()
	if child == 0 {
		mut code := 0
		if !write_once('/proc/self/loginuid', '1234') {
			code |= 1
		}
		if read_text('/proc/self/loginuid').trim_space() != '1234'
			|| read_text('/proc/self/sessionid').trim_space() == '0' {
			code |= 2
		}
		if !write_once('/proc/self/loginuid', '0') {
			code |= 4
		}
		if read_text('/proc/self/loginuid').trim_space() != '1234' {
			code |= 8
		}
		C._exit(code)
	}
	mut status := i32(0)
	C.waitpid(child, &status, 0)
	t.check((status >> 8) & 0xff == 4, 'labelling a login once: result ${(status >> 8) & 0xff} (4 is: set, read back, refused the second time)')
	t.check(read_text('/proc/self/sessionid').trim_space() == '0', 'a child\'s login became init\'s')

	// Sam at the machine, holding the display open.
	holder := C.fork()
	if holder == 0 {
		result := run(['/usr/sbin/vinix-session', 'run', '--seat', 'sam', '/sbin/init', 'probe',
			'seat-hold'], '', none, none)
		os.write_file('/tmp/seat-sam.out', result.output) or {}
		C._exit(0)
	}
	wait_for_file('/tmp/seat-ready-1')
	sam_session := seat_now()
	t.check(sam_session != '0', 'sam\'s session at the machine does not hold the seat')
	t.check(read_text('/run/vinix/session/active').trim_space() == sam.uid.str(), 'the person at the machine is "${read_text('/run/vinix/session/active').trim_space()}"')

	// Alex sits down. Alex's session has the devices; when it ends, nobody
	// does.
	alex_at := run(['/usr/sbin/vinix-session', 'run', '--seat', 'alex', '/sbin/init', 'probe',
		'seat-try'], '', none, none).output
	// The console's node is root's by its mode, seat or no seat: a session
	// reaches the keyboard through the descriptors it was started with.
	t.check(alex_at.contains('try /dev/fb0 ok') && alex_at.contains('try /dev/pointer ok'), 'the session at the machine is refused its devices: ${alex_at.trim_space().replace('\n', ', ')}')
	t.check(seat_now() == '0', 'the seat was not given up when alex\'s session ended: ${seat_now()}')
	os.write_file('/tmp/seat-step-1', '') or {}
	wait_for_file('/tmp/seat-ready-2')
	// The seat goes back to Sam's session, which never ended.
	t.check(write_once('/proc/sys/kernel/seat_session', sam_session), 'root cannot give the seat')
	os.write_file('/tmp/seat-step-2', '') or {}
	C.waitpid(holder, &status, 0)
	held := read_text('/tmp/seat-sam.out')
	want := 'open ok\nread1 ok\nread2 errno 13\nreopen errno 13\nread3 ok\nreopen2 ok\n'
	t.check(held == want, 'a descriptor held across two changes of seat: ${held.trim_space().replace('\n', ', ')}')
	t.check(seat_now() == '0', 'the seat was not given up when sam\'s session ended: ${seat_now()}')
	_ = alex
}
