// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The session manager on a booted kernel, with stand-ins for the login
// screen and the desktop: this program again, following a plan the scenario
// wrote and writing down what it saw.
//
// The stand-ins speak to the manager as the real ones will -- frames on
// descriptor 3 -- and run as what the real ones will run as: the login
// screen as `greeter`, a desktop as the person who logged in.
module main

import authproto
import os
import sessioncore

fn C.setsid() int

const session_log = '/tmp/sessions.log'

fn note(text string) {
	mut file := os.open_file(session_log, 'a', 0o666) or { return }
	file.write_string(text + '\n') or {}
	file.close()
}

// The next line of a plan, and one step further in it. The place is kept in
// `counter`, which only the account running the plan can write.
fn next_step(plan string, counter string) string {
	lines := read_text(plan).split_into_lines()
	at := read_text(counter).trim_space().int()
	os.write_file(counter, (at + 1).str()) or {}
	return if at < lines.len { lines[at] } else { 'idle' }
}

fn whoami() string {
	return 'login=${read_text('/proc/self/loginuid').trim_space()}/${read_text('/proc/self/sessionid').trim_space()} seat=${seat_now()} fb=${try_device('/dev/fb0')} active=${read_text('/run/vinix/session/active').trim_space()}'
}

fn ask_manager(code u16, fields ...string) string {
	authproto.write_frame(3, authproto.text_frame(code, ...fields)) or { return 'unsent' }
	answer := authproto.read_frame(3) or { return 'unanswered' }
	return '${answer.code}${if answer.fields.len > 0 { ' ' + answer.text(0) } else { '' }}'
}

// The login screen's stand-in.
fn probe_greeter() int {
	note('greeter: uid=${C.getuid()} ${whoami()}')
	for {
		step := next_step('/etc/greeter-plan', '/tmp/greeter-step').split(' ')
		match step[0] {
			'login' {
				password := step[2..].join(' ')
				answer := ask_manager(sessioncore.op_login, step[1], password)
				note('greeter: login ${step[1]} -> ${answer}')
				if answer == '0' {
					// Logged in: the manager ends the login screen now.
					idle()
				}
			}
			'bogus' {
				note('greeter: bogus -> ${ask_manager(999)}')
			}
			else {
				idle()
			}
		}
	}
	return 0
}

// A desktop's stand-in.
fn probe_desktop() int {
	user := os.getenv('USER')
	os.write_file('/tmp/desktop-${user}.pid', os.getpid().str()) or {}
	note('desktop ${user}: start uid=${C.getuid()} ${whoami()}')
	for {
		step := next_step('/etc/desktop-plan-${user}', os.getenv('HOME') + '/.plan-step').split(' ')
		match step[0] {
			'stray' {
				// Something the session leaves behind: out of its process
				// group and its terminal session, still in its login.
				child := C.fork()
				if child == 0 {
					C.setsid()
					C.close(3)
					C.usleep(120_000_000)
					C._exit(0)
				}
				os.write_file('/tmp/stray-${user}.pid', child.str()) or {}
			}
			'switch' {
				answer := ask_manager(sessioncore.op_switch)
				// Stopped about here, and continued when its owner logs in
				// again: the seat is this session's once more.
				mine := read_text('/proc/self/sessionid').trim_space()
				for _ in 0 .. 1200 {
					if seat_now() == mine {
						break
					}
					C.usleep(50_000)
				}
				note('desktop ${user}: switch -> ${answer}; resumed ${whoami()}')
			}
			'wait' {
				os.write_file('/tmp/${user}-ready', '') or {}
				wait_for_file('/tmp/${user}-go')
			}
			'logout' {
				note('desktop ${user}: logout -> ${ask_manager(sessioncore.op_logout)}')
				idle()
			}
			'exit' {
				note('desktop ${user}: exit')
				return 0
			}
			else {
				idle()
			}
		}
	}
	return 0
}

// The state letter of a process, as /proc/<pid>/stat has it after the name.
fn process_state(pid string) string {
	text := read_text('/proc/${pid.trim_space()}/stat')
	if text == '' {
		return 'gone'
	}
	return text.all_after_last(') ').all_before(' ')
}

fn log_line(prefix string) string {
	for text in read_text(session_log).split_into_lines() {
		if text.starts_with(prefix) {
			return text
		}
	}
	return ''
}

fn field(text string, name string) string {
	return text.all_after(' ${name}=').all_before(' ')
}

fn scenario_sessions(mut t Test) {
	db := t.make_accounts()
	alex := must_user(db, 'alex')
	sam := must_user(db, 'sam')
	greeter := must_user(db, 'greeter')
	os.chmod('/tmp', 0o1777) or {}
	t.start_authd()

	// One log for stand-ins of three accounts.
	os.write_file(session_log, '') or {}
	os.chmod(session_log, 0o666) or {}
	os.write_file('/etc/greeter-plan', 'bogus\nlogin sam not the password\nlogin greeter x\nlogin root\nlogin sam ${sam_password}\nlogin alex ${alex_password}\nlogin sam ${sam_password}\nidle\n') or {}
	os.write_file('/etc/desktop-plan-sam', 'stray\nswitch\nexit\n') or {}
	os.write_file('/etc/desktop-plan-alex', 'wait\nlogout\n') or {}

	manager := C.fork()
	if manager == 0 {
		argv := ['/usr/sbin/vinix-session', 'manager', '--greeter', '/sbin/init', 'probe', 'greeter',
			'--desktop', '/sbin/init', 'probe', 'desktop']
		mut c_argv := []&char{}
		for argument in argv {
			c_argv << &char(argument.str)
		}
		c_argv << &char(unsafe { nil })
		envp := [&char(c'PATH=/usr/sbin:/usr/bin:/sbin:/bin'), &char(unsafe { nil })]
		C.execve(c_argv[0], &c_argv[0], &envp[0])
		C._exit(127)
	}

	// Sam logs in, steps aside; Alex logs in and waits for us.
	wait_for_file('/tmp/alex-ready')
	// What the stand-ins wrote down so far, for whoever reads a failure.
	for text in read_text(session_log).split_into_lines() {
		t.info('so far: ${text}')
	}
	t.check(os.exists('/tmp/alex-ready'), 'alex\'s session never started: ${read_text(session_log).replace('\n', ' | ')}')
	first := log_line('greeter: uid=')
	t.check(first.starts_with('greeter: uid=${greeter.uid} login=${greeter.uid}/') && field(first, 'fb') == 'ok'
		&& field(first, 'seat') == field(first, 'login').all_after('/'), 'the login screen ran as: ${first}')
	t.check(log_line('greeter: bogus') == 'greeter: bogus -> 3 unknown request', 'a request that is none: ${log_line('greeter: bogus')}')
	t.check(log_line('greeter: login sam') == 'greeter: login sam -> 1', 'a wrong password at the login screen: ${log_line('greeter: login sam')}')
	t.check(log_line('greeter: login greeter') == 'greeter: login greeter -> 1', 'the login screen logging itself in: ${log_line('greeter: login greeter')}')
	t.check(log_line('greeter: login root').starts_with('greeter: login root -> ')
		&& log_line('greeter: login root') != 'greeter: login root -> 0', 'root at the login screen: ${log_line('greeter: login root')}')

	sam_start := log_line('desktop sam: start')
	sam_login := field(sam_start, 'login')
	t.check(sam_start.contains(' uid=${sam.uid} ') && sam_login.starts_with('${sam.uid}/')
		&& field(sam_start, 'seat') == sam_login.all_after('/') && field(sam_start, 'fb') == 'ok'
		&& sam_start.ends_with('active=${sam.uid}'), 'sam\'s session started as: ${sam_start}')
	alex_start := log_line('desktop alex: start')
	alex_login := field(alex_start, 'login')
	t.check(alex_login.starts_with('${alex.uid}/') && alex_login.all_after('/') != sam_login.all_after('/')
		&& field(alex_start, 'seat') == alex_login.all_after('/') && field(alex_start, 'fb') == 'ok'
		&& alex_start.ends_with('active=${alex.uid}'), 'alex\'s session started as: ${alex_start}')

	// While Alex is at the machine, everything of Sam's is stopped -- the
	// part that left its process group too -- and none of it is gone.
	sam_pid := read_text('/tmp/desktop-sam.pid')
	stray_pid := read_text('/tmp/stray-sam.pid')
	t.check(process_state(sam_pid) == 'T', 'sam\'s desktop, in the background, is in state ${process_state(sam_pid)}')
	t.check(process_state(stray_pid) == 'T', 'what sam\'s session left running is in state ${process_state(stray_pid)}')
	t.check(seat_now() == alex_login.all_after('/'), 'the seat is ${seat_now()} while alex is at the machine')
	t.check(read_text('/run/vinix/session/active').trim_space() == alex.uid.str(), 'the person at the machine is "${read_text('/run/vinix/session/active').trim_space()}"')

	// Alex logs out; Sam logs in again and is where Sam was.
	os.write_file('/tmp/alex-go', '') or {}
	for _ in 0 .. 600 {
		if log_line('desktop sam: exit') != '' {
			break
		}
		C.usleep(50_000)
	}
	t.check(log_line('desktop alex: logout') == 'desktop alex: logout -> 0', 'alex logging out: ${log_line('desktop alex: logout')}')
	resumed := log_line('desktop sam: switch')
	t.check(resumed.starts_with('desktop sam: switch -> 0; resumed login=${sam_login} seat=${sam_login.all_after('/')} fb=ok active=${sam.uid}'),
		'sam\'s session after logging in again: ${resumed}')
	t.check(read_text('/tmp/desktop-sam.pid') == sam_pid, 'sam got a new session instead of the old one')

	// Sam's session ends. What it left running ends with it, and the login
	// screen is back with the seat.
	// A process that has ended and has nobody to collect it shows as Z:
	// its parent is gone, and this test's init is not one that reaps.
	ended := ['gone', 'Z']
	// The seat is given to the next login screen a moment before that
	// screen has written its first line: wait for the line.
	for _ in 0 .. 300 {
		shown := read_text(session_log).split_into_lines().filter(it.starts_with('greeter: uid=')).len
		if process_state(stray_pid) in ended && shown >= 4 {
			break
		}
		C.usleep(50_000)
	}
	t.check(process_state(stray_pid) in ended, 'what sam\'s session left running is still there: ${process_state(stray_pid)}')
	t.check(process_state(sam_pid) in ended, 'sam\'s desktop is still there: ${process_state(sam_pid)}')
	t.check(!os.exists('/run/vinix/session/active'), 'someone is still marked as at the machine')
	greeters := read_text(session_log).split_into_lines().filter(it.starts_with('greeter: uid='))
	t.check(greeters.len == 4, 'the login screen was shown ${greeters.len} times, not 4: ${read_text(session_log).replace('\n', ' | ')}')
	if greeters.len > 0 {
		last := greeters[greeters.len - 1]
		t.check(field(last, 'fb') == 'ok' && field(last, 'seat') == seat_now(), 'the last login screen: ${last}, seat now ${seat_now()}')
	}
	C.kill(manager, C.SIGKILL)
}
