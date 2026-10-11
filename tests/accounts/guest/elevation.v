// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The authentication service on a booted kernel, asked by real processes
// of real accounts: whose password it will check, what it will run as root
// for whom, and that it tells callers apart by what the kernel says of
// them.
module main

import accountcore
import os

fn auth(what []string, input string, db accountcore.Database, user accountcore.User) Ran {
	mut argv := ['/usr/bin/vinix-auth']
	argv << what
	return run(argv, input, db, user)
}

fn scenario_elevation(mut t Test) {
	mut db := t.make_accounts()
	alex := must_user(db, 'alex')
	sam := must_user(db, 'sam')
	t.start_authd()
	t.check(mode_of('/run/vinix/auth.sock') & 0o777 == 0o666, 'the socket is mode ${mode_of('/run/vinix/auth.sock'):o}')

	// Who the service takes a caller for is not the caller's to say.
	info_sam := auth(['info'], '', db, sam)
	t.check(info_sam.output.contains('user: sam') && info_sam.output.contains('administrator: no'),
		'info as sam: ${info_sam.output}')
	info_alex := auth(['info'], '', db, alex)
	t.check(info_alex.output.contains('user: alex') && info_alex.output.contains('administrator: yes'),
		'info as alex: ${info_alex.output}')

	// One's own password, and nobody else's.
	t.check(auth(['verify'], sam_password + '\n', db, sam).status == 0, 'sam\'s own password was refused')
	t.check(auth(['verify'], 'not it at all\n', db, sam).status == 1, 'a wrong password was accepted')
	t.check(auth(['verify', 'alex'], alex_password + '\n', db, sam).status == 1, 'sam could check alex\'s password')
	t.check(auth(['verify', 'sam'], sam_password + '\n', db, alex).status == 1, 'an administrator could check sam\'s password')
	t.check(run(['/usr/bin/vinix-auth', 'verify', 'sam'], sam_password + '\n', none, none).status == 0, 'root could not check a password')

	// An action for administrators.
	before := os.hostname() or { '' }
	refused := auth(['run', 'hostname-set', 'planted'], sam_password + '\n', db, sam)
	t.check(refused.status == 1 && (os.hostname() or { '' }) == before, 'sam changed the host name: ${refused.output}')
	wrong := auth(['run', 'hostname-set', 'planted'], 'not it at all\n', db, alex)
	t.check(wrong.status == 1 && (os.hostname() or { '' }) == before, 'a wrong password changed the host name')
	done := auth(['run', 'hostname-set', 'testbox'], alex_password + '\n', db, alex)
	t.check(done.status == 0 && (os.hostname() or { '' }) == 'testbox', 'alex could not change the host name: ${done.status} ${done.output}')
	t.check(read_text('/etc/hostname') == 'testbox\n', '/etc/hostname is "${read_text('/etc/hostname').trim_space()}"')
	bad := auth(['run', 'hostname-set', 'bad name; reboot'], alex_password + '\n', db, alex)
	t.check(bad.status == 2 && (os.hostname() or { '' }) == 'testbox', 'an argument that is not a host name was run: ${bad.output}')
	unknown := auth(['run', 'no-such-action'], alex_password + '\n', db, alex)
	t.check(unknown.status == 2, 'an action that is not listed: ${unknown.status} ${unknown.output}')

	// What the action is given: root, a fixed environment, the asker's name.
	who := auth(['run', 'test-self'], sam_password + '\n', db, sam)
	t.check(who.output.contains('asked by sam (${sam.uid}) as uid=0 path=/usr/sbin:/usr/bin:/sbin:/bin home=/root'),
		'a self action as sam: ${who.status} ${who.output}')
	input := auth(['run', '--input', 'test-input'], alex_password + '\nfor the action only\n',
		db, alex)
	t.check(input.output.contains('input=for the action only'), 'input to an action: ${input.status} ${input.output}')

	// The person at the machine needs no password for a `session` action;
	// anyone else needs to be an administrator.
	away := auth(['run', 'test-session', 'hello'], '', db, sam)
	t.check(away.status == 1 && !away.output.contains('hello as'), 'sam, not at the machine, ran a session action: ${away.output}')
	os.mkdir_all('/run/vinix/session') or {}
	os.write_file('/run/vinix/session/active', '${sam.uid}\n') or {}
	os.chmod('/run/vinix/session/active', 0o644) or {}
	here := auth(['run', 'test-session', 'hello'], '', db, sam)
	t.check(here.status == 0 && here.output.contains('hello as uid=0'), 'sam, at the machine, could not run a session action: ${here.status} ${here.output}')
	// The file says who is; a file Sam could have written says nothing.
	os.chmod('/run/vinix/session/active', 0o666) or {}
	t.check(auth(['run', 'test-session', 'hello'], '', db, sam).status == 1, 'a session file anyone can write was believed')
	os.rm('/run/vinix/session/active') or {}
	planted := probe(['write', '/run/vinix/session/active'], db, sam)
	t.check(planted.output.starts_with('errno'), 'sam could write the session file: ${planted.output}')

	// Accounts, through the service.
	added := auth(['run', '--input', 'account-add', 'kim', 'Kim Example', 'standard'],
		alex_password + '\nkim picked this one\n', db, alex)
	db = load_db()
	kim := must_user(db, 'kim')
	t.check(added.status == 0 && kim.uid > sam.uid && !db.is_admin(kim), 'adding kim through the service: ${added.status} ${added.output}')
	t.check(mode_of('/home/kim') == 0o700 && owner_of('/home/kim') == int(kim.uid), '/home/kim is mode ${mode_of('/home/kim'):o}, owner ${owner_of('/home/kim')}')
	t.check(auth(['verify'], 'kim picked this one\n', db, kim).status == 0, 'kim\'s password does not work')
	by_sam := auth(['run', '--input', 'account-add', 'mallory', 'M', 'admin'], sam_password +
		'\nmallory password\n', db, sam)
	t.check(by_sam.status == 1 && !has_user(load_db(), 'mallory'), 'sam added an administrator: ${by_sam.output}')

	// One's own password, changed with the old one.
	changed := auth(['passwd'], sam_password + '\nsam chose a new one\n', db, sam)
	t.check(changed.status == 0, 'sam could not change sam\'s password: ${changed.output}')
	t.check(auth(['verify'], 'sam chose a new one\n', db, sam).status == 0, 'the new password does not work')
	t.check(auth(['verify'], sam_password + '\n', db, sam).status == 1, 'the old password still works')
	t.check(auth(['passwd', 'alex'], 'sam chose a new one\nplanted password\n', db, sam).status == 1,
		'sam changed alex\'s password')
	t.check(auth(['verify'], alex_password + '\n', db, alex).status == 0, 'alex\'s password is gone')

	// Guessing gets slower, for the account guessed at and nobody else.
	for _ in 0 .. 3 {
		auth(['verify'], 'a guess, wrong\n', db, kim)
	}
	slowed := auth(['verify'], 'kim picked this one\n', db, kim)
	t.check(slowed.status == 3, 'after three wrong passwords the right one was taken at once: ${slowed.status} ${slowed.output}')
	t.check(auth(['verify'], alex_password + '\n', db, alex).status == 0, 'kim\'s failures slowed alex down')
	C.usleep(2_500_000)
	t.check(auth(['verify'], 'kim picked this one\n', db, kim).status == 0, 'the wait did not end')

	// What the service keeps is root's.
	for path in ['/var/log/vinix/auth.log', '/etc/shadow'] {
		got := probe(['read', path], db, sam).output.trim_space()
		t.check(got == 'errno 13', 'sam reading ${path}: ${got}')
	}
	listing := probe(['list', '/run/vinix/auth/failures'], db, sam).output.trim_space()
	t.check(listing == 'errno 13', 'sam listing the failure counts: ${listing}')
	log := read_text('/var/log/vinix/auth.log')
	t.check(log.contains('uid=${alex.uid} run hostname-set as alex: exit 0'), 'the log does not say alex changed the host name')
	// vinix-auth asks first whether an action is open to the caller, so Sam's
	// attempts never became requests to run anything.
	t.check(!log.contains('run hostname-set as sam') && !log.contains('run account-add as sam'), 'the log says an action for administrators ran for sam')
	t.check(log.contains('uid=${sam.uid} verify alex: denied: not the caller\'s account'), 'the log does not say sam asked about alex')
	t.check(!log.contains(alex_password) && !log.contains('kim picked'), 'a password is in the log')

	// What is not a request does not take the service down, and a caller
	// who connects and says nothing does not keep others out.
	for kind in ['noise', 'huge-count', 'huge-field', 'half'] {
		probe(['garbage', kind], db, sam)
	}
	t.check(auth(['info'], '', db, alex).status == 0, 'the service did not survive malformed requests')
	mut silent := []int{}
	for _ in 0 .. 6 {
		child := C.fork()
		if child == 0 {
			result := probe(['garbage', 'hold'], db, sam)
			C._exit(result.status)
		}
		silent << child
	}
	C.usleep(1_000_000)
	t.check(auth(['verify'], alex_password + '\n', db, alex).status == 0, 'six silent connections from sam kept alex out')
	for child in silent {
		mut status := i32(0)
		C.waitpid(child, &status, 0)
	}
	t.check(auth(['info'], '', db, sam).status == 0, 'sam is still kept out after the silent connections ended')

	// A login on the console: a wrong password, then the right one, then
	// the end of input.
	held := accountcore.Store{}.lock(true) or { accountcore.Lock{} }
	mut with_shell := load_db()
	for mut user in with_shell.users {
		if user.name == 'sam' {
			user.shell = '/sbin/init'
		}
	}
	accountcore.Store{}.save(with_shell) or { t.check(false, 'cannot set sam\'s shell: ${err.msg()}') }
	held.release()
	login := run(['/usr/sbin/vinix-session', 'console'], 'sam\nnot it at all\nsam\nsam chose a new one\n',
		none, none)
	t.check(login.output.contains('Login incorrect.'), 'a wrong password at the console: ${login.output}')
	t.check(login.output.contains('uid=${sam.uid} euid=${sam.uid} ') && login.output.contains(' caps=0000000000000000 ')
		&& login.output.contains(' user=sam cwd=/home/sam active=${sam.uid}'), 'a login at the console: ${login.output}')
	t.check(!os.exists('/run/vinix/session/active'), 'the session file outlived the session')
	root_login := run(['/usr/sbin/vinix-session', 'console'], 'root\n\nroot\nroot\n', none,
		none)
	t.check(!root_login.output.contains('uid=0'), 'root logged in at the console: ${root_login.output}')
}
