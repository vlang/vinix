// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module authcore

import accountcore
import authproto
import os

const cheap = accountcore.Cost{
	ln: 10
	r:  8
	p:  1
}

fn scratch() string {
	return os.join_path(os.temp_dir(), 'vinix-authcore-${os.getpid()}')
}

// The test's clock: what the test last put in the environment.
fn clock_of_test() i64 {
	return os.getenv('VINIX_TEST_NOW').i64()
}

fn set_now(now i64) {
	os.setenv('VINIX_TEST_NOW', now.str(), true)
}

// Stands in for starting a program: writes down what would have run.
fn fake_runner(action Action, argv []string, input []u8, peer Peer, user string) RunResult {
	os.write_file(os.join_path(scratch(), 'ran'), '${user}|${peer.uid}|${argv.join(' ')}|${input.bytestr()}') or {}
	return RunResult{
		started: true
		status:  if action.name == 'fails' { 3 } else { 0 }
		output:  'done'.bytes()
	}
}

fn ran() string {
	path := os.join_path(scratch(), 'ran')
	text := os.read_file(path) or { return '' }
	os.rm(path) or {}
	return text
}

struct World {
	env   Env
	root  Peer
	alex  Peer // an administrator
	sam   Peer // not one
	greet Peer
}

fn new_world() !World {
	dir := scratch()
	os.rmdir_all(dir) or {}
	os.mkdir_all(os.join_path(dir, 'etc'))!
	os.mkdir_all(os.join_path(dir, 'actions'))!
	os.chmod(os.join_path(dir, 'actions'), 0o755)!
	store := accountcore.Store{
		etc:   os.join_path(dir, 'etc')
		owned: false
	}
	os.write_file(store.passwd_path(), 'root:x:0:0:root:/root:/bin/sh\n')!
	os.write_file(store.group_path(), 'root:x:0:\n')!
	os.chmod(store.passwd_path(), 0o644)!
	os.chmod(store.group_path(), 0o644)!
	mut db := store.load()!
	db.ensure_system_accounts()!
	db.add_user(name: 'alex', admin: true, hash: accountcore.hash_password('alex password'.bytes(),
		cheap)!)!
	db.add_user(name: 'sam', hash: accountcore.hash_password('sam password'.bytes(), cheap)!)!
	store.save(db)!
	for name, text in {
		'restart':          'description = Restart the computer\nauth = session\nexec = /usr/sbin/vinix-system\narg = power\narg = restart\n'
		'account-password': 'description = Change a password\nauth = admin\nexec = /usr/sbin/vinix-account\narg = passwd\nparam = name\ninput = secret\n'
		'own-thing':        'description = Something of one\'s own\nauth = self\nexec = /bin/true\n'
		'own-launch':       'description = Launch as the caller\nauth = account\nexec = /usr/sbin/vinix-session\narg = package-launch\ninput = secret\n'
		'profile':          'description = Power profile\nauth = admin\nexec = /bin/true\nparam = choice:fast,quiet\nparam = number\n'
		'fails':            'description = Fails\nauth = admin\nexec = /bin/false\n'
		'broken':           'description = Broken\nauth = admin\nexec = /bin/true\nshell = yes\n'
	} {
		path := os.join_path(dir, 'actions', name)
		os.write_file(path, text)!
		os.chmod(path, 0o644)!
	}
	set_now(1_800_000_000)
	greeter := db.user('greeter') or { return error('no greeter') }
	return World{
		env:   Env{
			store:    store
			throttle: accountcore.Throttle{
				directory: os.join_path(dir, 'failures')
			}
			actions:  os.join_path(dir, 'actions')
			session:  os.join_path(dir, 'active')
			log:      os.join_path(dir, 'log', 'auth.log')
			events:   os.join_path(dir, 'events')
			cost:     cheap
			clock:    clock_of_test
			runner:   fake_runner
		}
		root:  Peer{
			pid: 1
		}
		alex:  Peer{
			pid: 10
			uid: 1000
			gid: 1000
		}
		sam:   Peer{
			pid: 11
			uid: 1001
			gid: 1001
		}
		greet: Peer{
			pid: 12
			uid: greeter.uid
			gid: greeter.gid
		}
	}
}

fn ask(w World, peer Peer, code u16, fields ...string) authproto.Frame {
	mut request := authproto.text_frame(code, ...fields)
	return handle(w.env, peer, mut request)
}

fn test_action_files() ! {
	action := parse_action('account-add', '# add someone\ndescription = Add an account\nauth = admin\nexec = /usr/sbin/vinix-account\narg = add\narg = --password-stdin\nparam = name\nparam = text\nparam = choice:admin,standard\ninput = secret\n')!
	assert action.auth == .admin && action.input && action.params.len == 3
	assert action.arguments(['sam', 'Sam Smith', 'standard'])! == ['/usr/sbin/vinix-account', 'add',
		'--password-stdin', 'sam', 'Sam Smith', 'standard']
	for bad in [
		['sam', 'Sam'], // too few
		['sam', 'Sam', 'standard', 'more'],
		['Sam', 'Sam', 'standard'], // not a name
		['sam', '-rf', 'standard'], // would read as an option
		['sam', 'two\nlines', 'standard'],
		['sam', '', 'standard'],
		['sam', 'Sam', 'root'], // not one of the choices
		['../etc', 'Sam', 'standard'],
	] {
		action.arguments(bad) or { continue }
		assert false, bad.str()
	}
	for bad in [
		'description = x\nexec = /bin/true\n', // no auth
		'description = x\nauth = admin\n', // no exec
		'auth = admin\nexec = /bin/true\n', // no description
		'description = x\nauth = anyone\nexec = /bin/true\n',
		'description = x\nauth = admin\nexec = true\n',
		'description = x\nauth = admin\nexec = /bin/../bin/sh\n',
		'description = x\nauth = admin\nexec = /bin/true\nexec = /bin/sh\n',
		'description = x\nauth = admin\nauth = self\nexec = /bin/true\n',
		'description = x\nauth = admin\nexec = /bin/true\nparam = anything\n',
		'description = x\nauth = admin\nexec = /bin/true\nparam = choice:one\n',
		'description = x\nauth = admin\nexec = /bin/true\ninput = file\n',
		'description = x\nauth = admin\nexec = /bin/true\nsetuid = 0\n',
		'description = x\nauth = admin\nexec = /bin/true\njunk\n',
	] {
		parse_action('x', bad) or { continue }
		assert false, bad
	}
	assert !valid_action_name('Restart') && !valid_action_name('../x') && !valid_action_name('')
	assert Param{ kind: .hostname }.accepts('my-mac') && !Param{ kind: .hostname }.accepts('-x')
	assert !Param{ kind: .hostname }.accepts('a.b') && !Param{ kind: .number }.accepts('1e3')
	assert Param{ kind: .text }.accepts('Zoë: the 2nd') && !Param{ kind: .text }.accepts('a\tb')
}

fn test_info() ! {
	w := new_world()!
	reply := ask(w, w.alex, authproto.op_info)
	assert reply.code == authproto.status_ok
	assert reply.text(0) == 'alex' && reply.text(1) == '1' && reply.text(2) == '0'
	assert ask(w, w.sam, authproto.op_info).text(1) == '0'
	assert ask(w, Peer{ uid: 4242 }, authproto.op_info).code == authproto.status_denied
	os.write_file(w.env.session, '1001\n')!
	os.chmod(w.env.session, 0o644)!
	assert ask(w, w.sam, authproto.op_info).text(2) == '1'
	assert ask(w, w.alex, authproto.op_info).text(2) == '0'
}

fn test_account_action_needs_only_a_known_ordinary_peer() ! {
	w := new_world()!
	for peer in [w.alex, w.sam] {
		description := ask(w, peer, authproto.op_describe, 'own-launch')
		assert description.code == authproto.status_ok && description.text(1) == '1' && description.text(2) == '0'
		assert ask(w, peer, authproto.op_run, 'own-launch', '', 'nonce').code == authproto.status_ok
		assert ran().contains('|${peer.uid}|/usr/sbin/vinix-session package-launch|nonce')
	}
	for peer in [w.greet, Peer{ uid: 4242 }] {
		assert ask(w, peer, authproto.op_run, 'own-launch', '', 'nonce').code == authproto.status_denied
		assert ran() == ''
	}
	assert ask(w, w.sam, authproto.op_run, 'own-launch', '', 'nonce', 'alex').code == authproto.status_invalid
	assert ran() == ''
	assert ask(w, w.sam, authproto.op_run, 'account-password', '', 'nonce', 'alex').code == authproto.status_denied
}

fn test_verify_rules() ! {
	w := new_world()!
	assert ask(w, w.alex, authproto.op_verify, 'alex', 'alex password').code == authproto.status_ok
	assert ask(w, w.alex, authproto.op_verify, 'alex', 'wrong').code == authproto.status_denied
	// Not someone else's, right or wrong, and without it counting against
	// them.
	assert ask(w, w.sam, authproto.op_verify, 'alex', 'alex password').code == authproto.status_denied
	assert ask(w, w.sam, authproto.op_verify, 'alex', 'guess').code == authproto.status_denied
	assert w.env.throttle.read('alex', clock_of_test()).count == 1
	// Root may check anyone: the session manager, for a login. The login
	// screen's own account may not.
	assert ask(w, w.root, authproto.op_verify, 'sam', 'sam password').code == authproto.status_ok
	assert ask(w, w.greet, authproto.op_verify, 'sam', 'sam password').code == authproto.status_denied
	assert ask(w, w.root, authproto.op_verify, 'nobody-here', 'x').code == authproto.status_denied
	// Accounts without a password match nothing.
	assert ask(w, w.root, authproto.op_verify, 'root', '').code == authproto.status_denied
	assert ask(w, w.root, authproto.op_verify, 'greeter', '*').code == authproto.status_denied
	assert ask(w, w.root, authproto.op_verify, 'Alex', 'alex password').code == authproto.status_invalid
	assert ask(w, w.root, authproto.op_verify, 'alex').code == authproto.status_invalid
	assert ask(w, w.root, 99).code == authproto.status_invalid
}

fn test_throttle() ! {
	w := new_world()!
	for _ in 0 .. 3 {
		assert ask(w, w.root, authproto.op_verify, 'sam', 'guess').code == authproto.status_denied
	}
	// Now even the right password has to wait.
	blocked := ask(w, w.root, authproto.op_verify, 'sam', 'sam password')
	assert blocked.code == authproto.status_wait && blocked.text(0) == '2'
	// Sam's own unlock waits too; Alex is not affected.
	assert ask(w, w.sam, authproto.op_verify, 'sam', 'sam password').code == authproto.status_wait
	assert ask(w, w.alex, authproto.op_verify, 'alex', 'alex password').code == authproto.status_ok
	set_now(clock_of_test() + 2)
	assert ask(w, w.root, authproto.op_verify, 'sam', 'guess').code == authproto.status_denied
	assert ask(w, w.root, authproto.op_verify, 'sam', 'sam password').text(0) == '4'
	set_now(clock_of_test() + 4)
	assert ask(w, w.root, authproto.op_verify, 'sam', 'sam password').code == authproto.status_ok
	assert w.env.throttle.read('sam', clock_of_test()).count == 0
}

fn test_rehash_on_login() ! {
	w := new_world()!
	stronger := Env{
		...w.env
		cost: accountcore.Cost{
			ln: 11
			r:  8
			p:  1
		}
	}
	before := stronger.store.load()!.shadow('alex') or { return error('no record') }
	mut request := authproto.text_frame(authproto.op_verify, 'alex', 'alex password')
	assert handle(stronger, w.alex, mut request).code == authproto.status_ok
	after := stronger.store.load()!.shadow('alex') or { return error('no record') }
	assert after.hash != before.hash && after.hash.contains('ln=11')
	assert accountcore.verify_password(after.hash, 'alex password'.bytes())
}

fn test_change_password() ! {
	w := new_world()!
	assert ask(w, w.sam, authproto.op_change_password, 'sam', 'wrong', 'a new password').code == authproto.status_denied
	assert ask(w, w.sam, authproto.op_change_password, 'sam', 'sam password', 'short').code == authproto.status_invalid
	assert ask(w, w.sam, authproto.op_change_password, 'sam', 'sam password', 'sam password').code == authproto.status_invalid
	// Not someone else's -- an administrator neither, by this route.
	assert ask(w, w.alex, authproto.op_change_password, 'sam', 'alex password', 'a new password').code == authproto.status_denied
	assert ask(w, w.sam, authproto.op_change_password, 'sam', 'sam password', 'a new password').code == authproto.status_ok
	assert ask(w, w.sam, authproto.op_verify, 'sam', 'sam password').code == authproto.status_denied
	assert ask(w, w.sam, authproto.op_verify, 'sam', 'a new password').code == authproto.status_ok
	// Root needs no old password, and a lock survives a change.
	held := w.env.store.lock(true)!
	mut db := w.env.store.load()!
	db.set_locked('sam', true)!
	w.env.store.save(db)!
	held.release()
	assert ask(w, w.root, authproto.op_change_password, 'sam', '', 'another password').code == authproto.status_ok
	assert ask(w, w.root, authproto.op_verify, 'sam', 'another password').code == authproto.status_denied
	record := w.env.store.load()!.shadow('sam') or { return error('no record') }
	assert accountcore.is_locked(record.hash)
	assert accountcore.verify_password(record.hash[1..], 'another password'.bytes())
}

fn test_run_rules() ! {
	w := new_world()!
	// An administrator, with their own password.
	needed := ask(w, w.alex, authproto.op_run, 'account-password', '', 'new secret', 'sam')
	assert needed.code == authproto.status_password_needed && needed.text(0) == 'Change a password'
	assert ran() == ''
	done := ask(w, w.alex, authproto.op_run, 'account-password', 'alex password', 'new secret',
		'sam')
	assert done.code == authproto.status_ok && done.text(0) == '0' && done.text(1) == 'done'
	assert ran() == 'alex|1000|/usr/sbin/vinix-account passwd sam|new secret'
	assert ask(w, w.alex, authproto.op_run, 'account-password', 'wrong', 'x', 'sam').code == authproto.status_denied
	assert ran() == ''
	// Someone who is not one: no password makes it allowed, their own
	// included, and it is not even asked for.
	assert ask(w, w.sam, authproto.op_run, 'account-password', '', 'x', 'alex').code == authproto.status_denied
	assert ask(w, w.sam, authproto.op_run, 'account-password', 'sam password', 'x', 'alex').code == authproto.status_denied
	assert ask(w, w.sam, authproto.op_run, 'account-password', 'alex password', 'x', 'alex').code == authproto.status_denied
	assert ran() == ''
	// A `self` action: anyone, with their own password.
	assert ask(w, w.sam, authproto.op_run, 'own-thing', 'sam password', '').code == authproto.status_ok
	assert ran() == 'sam|1001|/bin/true|'
	// Root is not asked.
	assert ask(w, w.root, authproto.op_run, 'fails', '', '').code == authproto.status_failed
	assert ran() == 'root|0|/bin/false|'
	// The login screen's account and an unknown uid get nothing.
	assert ask(w, w.greet, authproto.op_run, 'own-thing', 'x', '').code == authproto.status_denied
	assert ask(w, Peer{ uid: 4242 }, authproto.op_run, 'own-thing', 'x', '').code == authproto.status_denied
	assert ran() == ''
}

fn test_session_rule() ! {
	w := new_world()!
	// Nobody at the machine: Sam may not, Alex may with a password.
	assert ask(w, w.sam, authproto.op_run, 'restart', '', '').code == authproto.status_denied
	assert ask(w, w.alex, authproto.op_run, 'restart', '', '').code == authproto.status_password_needed
	os.write_file(w.env.session, '1001\n')!
	os.chmod(w.env.session, 0o644)!
	assert ask(w, w.sam, authproto.op_run, 'restart', '', '').code == authproto.status_ok
	assert ran() == 'sam|1001|/usr/sbin/vinix-system power restart|'
	described := ask(w, w.sam, authproto.op_describe, 'restart')
	assert described.text(0) == 'Restart the computer' && described.text(1) == '1'
		&& described.text(2) == '0'
	assert ask(w, w.sam, authproto.op_describe, 'account-password').text(1) == '0'
	assert ask(w, w.alex, authproto.op_describe, 'account-password').text(2) == '1'
	// A session file that others could have written says nothing.
	os.chmod(w.env.session, 0o666)!
	assert ask(w, w.sam, authproto.op_run, 'restart', '', '').code == authproto.status_denied
	os.chmod(w.env.session, 0o644)!
	os.write_file(w.env.session, '1001 0\n')!
	assert ask(w, w.sam, authproto.op_run, 'restart', '', '').code == authproto.status_denied
}

fn test_run_refuses_what_is_not_listed() ! {
	w := new_world()!
	for request in [
		['no-such-action', 'alex password', ''],
		['../../bin/sh', 'alex password', ''],
		['broken', 'alex password', ''], // a file with a line nobody understands
		['profile', 'alex password', '', 'fast'], // an argument short
		['profile', 'alex password', '', 'loud', '3'],
		['profile', 'alex password', '', 'fast', '-3'],
		['profile', 'alex password', 'unexpected input', 'fast', '3'],
		['restart', 'alex password', '', 'extra'],
	] {
		reply := ask(w, w.alex, authproto.op_run, ...request)
		assert reply.code == authproto.status_invalid, request.str()
		assert ran() == ''
	}
	assert ask(w, w.alex, authproto.op_run, 'profile', 'alex password', '', 'quiet', '3').code == authproto.status_ok
	assert ran() == 'alex|1000|/bin/true quiet 3|'
	assert ask(w, w.alex, authproto.op_run, 'restart').code == authproto.status_invalid
	// An action directory, or an action, that someone else can write.
	os.chmod(os.join_path(w.env.actions, 'profile'), 0o666)!
	assert ask(w, w.alex, authproto.op_run, 'profile', 'alex password', '', 'quiet', '3').code == authproto.status_invalid
	os.chmod(os.join_path(w.env.actions, 'profile'), 0o644)!
	os.chmod(w.env.actions, 0o777)!
	assert ask(w, w.alex, authproto.op_run, 'profile', 'alex password', '', 'quiet', '3').code == authproto.status_invalid
	assert ran() == ''
}

fn test_run_is_throttled_and_logged() ! {
	w := new_world()!
	for _ in 0 .. 3 {
		assert ask(w, w.alex, authproto.op_run, 'fails', 'guess', '').code == authproto.status_denied
	}
	assert ask(w, w.alex, authproto.op_run, 'fails', 'alex password', '').code == authproto.status_wait
	assert ran() == ''
	ask(w, w.root, authproto.op_verify, 'evil\nname', 'x')
	log := os.read_file(w.env.log)!
	lines := log.split_into_lines()
	assert lines.len == 4
	assert lines[0] == '1800000000 pid=10 uid=1000 run fails: denied: wrong password'
	assert lines[3] == '1800000000 pid=10 uid=1000 run fails: wait 2s'
	assert os.stat(w.env.log)!.mode & 0o777 == 0o600
}

// What the service reports to the kernel's stream: one write per decision,
// naming the caller's process, with 1 for anything that was not done.
fn test_reports_to_the_kernel() ! {
	w := new_world()!
	os.write_file(w.env.events, '')!
	ask(w, w.alex, authproto.op_verify, 'alex', 'wrong')
	assert os.read_file(w.env.events)! == '10 1 auth:verify alex:denied'
	os.write_file(w.env.events, '')!
	ask(w, w.alex, authproto.op_verify, 'alex', 'alex password')
	assert os.read_file(w.env.events)! == '10 0 auth:verify alex:ok'
	os.write_file(w.env.events, '')!
	ask(w, w.alex, authproto.op_run, 'profile', 'alex password', '', 'quiet', '3')
	assert os.read_file(w.env.events)! == '10 0 auth:run profile as alex:exit 0'
}
