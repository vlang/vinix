// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The credential store on a booted kernel: an account's secrets through
// their whole life -- made, used, locked, a password changed, a password
// lost and the recovery key used -- then what other accounts and root can
// see of them, and a login that opens the store with what was typed at the
// login screen.
module main

import os

const store_secret = 'hunter2 is not a good one'

fn keyring(what []string, input string) Ran {
	mut argv := ['/usr/bin/vinix-keyring']
	argv << what
	return run(argv, input, none, none)
}

fn step(name string, ran Ran) {
	println('STEP ${name} ${ran.status} ${ran.output.trim_space().replace('\n', '|')}')
}

// Run as the account, in a login session: the service, then the commands.
fn probe_keyring_flow(login_password string) int {
	service := C.fork()
	if service == 0 {
		argv := [&char(c'/usr/bin/vinix-keyring'), &char(c'daemon'), &char(unsafe { nil })]
		mut environment := []&char{}
		for variable in ['HOME', 'XDG_RUNTIME_DIR'] {
			text := '${variable}=${os.getenv(variable)}'
			environment << &char(text.str)
		}
		environment << &char(c'VINIX_KEYRING_TEST_COST=1')
		environment << &char(unsafe { nil })
		C.execve(argv[0], &argv[0], &environment[0])
		C._exit(127)
	}
	socket := os.getenv('XDG_RUNTIME_DIR') + '/vinix-keyring.sock'
	wait_for_file(socket)
	step('status-absent', keyring(['status'], ''))
	made := keyring(['init'], 'first password\n')
	recovery := made.output.split_into_lines()[0] or { '' }
	println('STEP init ${made.status} ${recovery.len}')
	step('init-again', keyring(['init'], 'first password\n'))
	step('status-open', keyring(['status'], ''))
	step('set', keyring(['set', 'wifi', 'Home Network'], store_secret + '\n'))
	step('get', keyring(['get', 'wifi', 'Home Network'], ''))
	step('get-missing', keyring(['get', 'wifi', 'Other'], ''))
	step('list', keyring(['list'], ''))
	step('lock', keyring(['lock'], ''))
	step('get-locked', keyring(['get', 'wifi', 'Home Network'], ''))
	step('unlock-wrong', keyring(['unlock'], 'not the password\n'))
	step('unlock', keyring(['unlock'], 'first password\n'))
	step('change', keyring(['change-password'], 'first password\nsecond password\n'))
	step('change-wrong', keyring(['change-password'], 'first password\nthird password\n'))
	keyring(['lock'], '')
	step('unlock-old', keyring(['unlock'], 'first password\n'))
	// The password is lost. The recovery key opens the store, sets the
	// password the account logs in with, and is replaced.
	step('recover-wrong', keyring(['recover'], 'AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA\n${login_password}\n'))
	recovered := keyring(['recover'], '${recovery}\n${login_password}\n')
	fresh := recovered.output.split_into_lines()[0] or { '' }
	println('STEP recover ${recovered.status} ${fresh.len} ${if fresh == recovery { 'same' } else { 'new' }}')
	step('get-recovered', keyring(['get', 'wifi', 'Home Network'], ''))
	step('recover-used', keyring(['recover'], '${recovery}\n${login_password}\n'))
	println('STEP socket ${mode_of(socket) & 0o777:o} ${mode_of(os.getenv('XDG_RUNTIME_DIR')) & 0o777:o}')
	C.kill(service, C.SIGTERM)
	return 0
}

fn scenario_keyring(mut t Test) {
	db := t.make_accounts()
	alex := must_user(db, 'alex')
	sam := must_user(db, 'sam')
	os.chmod('/tmp', 0o1777) or {}
	t.start_authd()

	flow := run(['/usr/sbin/vinix-session', 'run', 'sam', '/sbin/init', 'probe', 'keyring-flow',
		sam_password], '', none, none)
	mut steps := map[string]string{}
	for line in flow.output.split_into_lines() {
		if line.starts_with('STEP ') {
			rest := line[5..]
			steps[rest.all_before(' ')] = rest.all_after(' ')
		}
	}
	for name, wanted in {
		'status-absent': '0 absent 0'
		'init':          '0 39'
		'init-again':    '1 vinix-keyring: there is a store already'
		'status-open':   '0 unlocked 0'
		'set':           '0 '
		'get':           '0 ${store_secret}'
		'get-missing':   '1 vinix-keyring: no such item'
		'list':          '0 wifi\tHome Network'
		'lock':          '0 '
		'get-locked':    '1 vinix-keyring: the store is locked'
		'unlock-wrong':  '1 vinix-keyring: wrong password'
		'unlock':        '0 '
		'change':        '0 '
		'change-wrong':  '1 vinix-keyring: wrong password'
		'unlock-old':    '1 vinix-keyring: wrong password'
		'recover-wrong': '1 vinix-keyring: wrong recovery key'
		'recover':       '0 39 new'
		'get-recovered': '0 ${store_secret}'
		'recover-used':  '1 vinix-keyring: wrong recovery key'
		'socket':        '600 700'
	} {
		got := steps[name].trim_space()
		t.check(got == wanted.trim_space(), 'the store, ${name}: wanted "${wanted}", got "${got}"')
	}

	// What is on the disk: Sam's alone, and nothing of what it holds.
	store := '/home/sam/.local/share/vinix/keyring'
	text := read_text(store)
	t.check(mode_of(store) == 0o600 && owner_of(store) == int(sam.uid), 'the store is mode ${mode_of(store):o}, owner ${owner_of(store)}')
	t.check(text.starts_with('vinix-keyring 1\n') && text.count('\nitem ') == 1, 'the store does not read as one: ${text.len} bytes')
	// (The word "password" is in it: "slot password" is how the format
	// names the wrapping it was unlocked through.)
	for word in ['hunter2', 'wifi', 'Home', 'Network', 'first', 'second', 'another'] {
		t.check(!text.contains(word), 'the store file contains "${word}"')
	}
	// Another account reaches neither the file nor the service.
	other := probe(['read', store], db, alex).output.trim_space()
	t.check(other == 'errno 13', 'alex reading sam\'s store: ${other}')
	// Root has no store and is told so, rather than given one that every
	// service would share.
	as_root := keyring(['status'], '')
	t.check(as_root.status == 1 && as_root.output.contains('root has no credential store'), 'root asking for a store: ${as_root.status} ${as_root.output}')

	// A login: the store is open by the time the session's first program
	// asks, opened with what was typed at the login screen.
	os.write_file(session_log, '') or {}
	os.chmod(session_log, 0o666) or {}
	os.write_file('/etc/greeter-plan', 'login sam ${sam_password}\nlogin alex ${alex_password}\nidle\n') or {}
	os.write_file('/etc/desktop-plan-sam', 'keyring\nexit\n') or {}
	os.write_file('/etc/desktop-plan-alex', 'keyring\nexit\n') or {}
	manager := C.fork()
	if manager == 0 {
		argv := ['/usr/sbin/vinix-session', 'manager', '--greeter', '/sbin/init', 'probe', 'greeter',
			'--desktop', '/sbin/init', 'probe', 'desktop']
		mut c_argv := []&char{}
		for argument in argv {
			c_argv << &char(argument.str)
		}
		c_argv << &char(unsafe { nil })
		envp := [&char(c'PATH=/usr/sbin:/usr/bin:/sbin:/bin'), &char(c'VINIX_KEYRING_TEST_COST=1'),
			&char(unsafe { nil })]
		C.execve(c_argv[0], &c_argv[0], &envp[0])
		C._exit(127)
	}
	for _ in 0 .. 600 {
		if log_line('desktop alex: exit') != '' {
			break
		}
		C.usleep(50_000)
	}
	sam_saw := log_line('desktop sam: keyring')
	t.check(sam_saw == 'desktop sam: keyring unlocked 1 | ${store_secret}', 'sam\'s session found the store: ${sam_saw}')
	// Alex never made one: there is nothing to open and nothing is made.
	alex_saw := log_line('desktop alex: keyring')
	t.check(alex_saw.starts_with('desktop alex: keyring absent 0'), 'alex\'s session found the store: ${alex_saw}')
	t.check(!os.exists('/home/alex/.local/share/vinix/keyring'), 'a store was made for alex at login')
	// The service ended with the session it belonged to; the manager is
	// given a moment to have finished ending Alex's.
	mut left := 0
	for _ in 0 .. 100 {
		left = 0
		for entry in os.ls('/proc') or { []string{} } {
			if read_text('/proc/${entry}/cmdline').contains('vinix-keyring') && process_state(entry) !in ['gone', 'Z'] {
				left++
			}
		}
		if left == 0 {
			break
		}
		C.usleep(50_000)
	}
	t.check(left == 0, '${left} keyring services outlived their sessions')
	C.kill(manager, C.SIGKILL)
}
