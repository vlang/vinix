// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The account database on a booted kernel: the person registered before
// there were accounts becomes one, homes are their owners' alone, and a
// session is the account's and nothing of root's.
module main

import accountcore
import crypto.scrypt
import os

const registered_password = 'registered long ago'

// A record as the desktop's registration wrote it, and the folders it kept
// for that person under /root.
fn write_registration() ! {
	salt := []u8{len: 16, init: u8(index * 3 + 1)}
	key := scrypt.scrypt(registered_password.bytes(), salt, 16384, 8, 1, 32)!
	record := 'version=1\nname=${'First User'.bytes().hex()}\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=${salt.hex()}\nhash=${key.hex()}\n'
	os.write_file('/root/.vinix-user', record)!
	os.chmod('/root/.vinix-user', 0o600)!
	os.mkdir_all('/root/home/first-user/Documents')!
	os.write_file('/root/home/first-user/Documents/kept.txt', 'from before\n')!
	// What the desktop left in /home: a link into root's home.
	os.symlink('/root/home/first-user', '/home/first-user')!
}

fn scenario_accounts(mut t Test) {
	write_registration() or { t.check(false, 'cannot write the registration: ${err.msg()}') }
	db := t.make_accounts()

	// The files.
	t.check(mode_of('/etc/shadow') == 0o600 && owner_of('/etc/shadow') == 0, '/etc/shadow is mode ${mode_of('/etc/shadow'):o}, owner ${owner_of('/etc/shadow')}')
	t.check(mode_of('/etc/passwd') == 0o644, '/etc/passwd is mode ${mode_of('/etc/passwd'):o}')
	t.check(!read_text('/etc/passwd').contains('$scrypt$'), 'a password record is in /etc/passwd')
	check := run(['/usr/sbin/vinix-account', 'check'], '', none, none)
	t.check(check.status == 0, 'vinix-account check: ${check.output}')

	// The registered person is the first account and an administrator, with
	// the password and the files they had.
	first := must_user(db, 'first-user')
	t.check(first.uid == 1000 && first.gecos == 'First User', 'the registered person became ${first}')
	t.check(db.is_admin(first), 'the registered person is not an administrator')
	first_shadow := db.shadow('first-user') or { accountcore.Shadow{} }
	t.check(accountcore.verify_password(first_shadow.hash, registered_password.bytes()),
		'the registered password does not match the imported record')
	t.check(!accountcore.verify_password(first_shadow.hash, 'something else!'.bytes()),
		'any password matches the imported record')
	t.check(read_text('/home/first-user/Documents/kept.txt') == 'from before\n', 'the registered person\'s files are not in their home')
	t.check(owner_of('/home/first-user/Documents/kept.txt') == 1000, 'their files belong to uid ${owner_of('/home/first-user/Documents/kept.txt')}')
	t.check(!os.is_link('/home/first-user'), '/home/first-user is still a link into /root')
	// Homes made after that land beside it, where they persist.
	t.check(os.is_dir('/root/home/alex'), 'a new home is not kept with the old ones')

	alex := must_user(db, 'alex')
	sam := must_user(db, 'sam')
	t.check(alex.uid == 1001 && sam.uid == 1002, 'uids: alex ${alex.uid}, sam ${sam.uid}')
	t.check(db.is_admin(alex) && !db.is_admin(sam), 'who is an administrator is wrong')
	for user in [alex, sam] {
		t.check(mode_of(user.home) == 0o700 && owner_of(user.home) == int(user.uid), '${user.home} is mode ${mode_of(user.home):o}, owner ${owner_of(user.home)}')
		t.check(os.is_dir(user.home + '/Documents') && owner_of(user.home + '/Documents') == int(user.uid),
			'${user.home}/Documents is missing or not the user\'s')
	}
	listed := run(['/usr/sbin/vinix-account', 'list'], '', none, none)
	t.check(listed.output.contains('alex\t1001\tadmin\tactive\tAlex Example')
		&& listed.output.contains('sam\t1002\tstandard\tactive\tSam Example'), 'vinix-account list: ${listed.output}')

	// A file anyone could read, were it anywhere else.
	os.write_file('/home/alex/Documents/diary.txt', 'private\n') or {}
	os.chown('/home/alex/Documents/diary.txt', int(alex.uid), int(alex.gid)) or {}
	os.chmod('/home/alex/Documents/diary.txt', 0o644) or {}

	expect := fn (mut t Test, db accountcore.Database, user accountcore.User, what []string, wanted string) {
		got := probe(what, db, user).output.trim_space()
		t.check(got.starts_with(wanted), '${user.name}: ${what.join(' ')}: wanted ${wanted}, got ${got}')
	}
	// Sam and what is not Sam's.
	expect(mut t, db, sam, ['read', '/home/alex/Documents/diary.txt'], 'errno 13')
	expect(mut t, db, sam, ['list', '/home/alex'], 'errno 13')
	expect(mut t, db, sam, ['write', '/home/alex/planted'], 'errno 13')
	expect(mut t, db, sam, ['read', '/root/home/alex/Documents/diary.txt'], 'errno 13')
	expect(mut t, db, sam, ['list', '/root'], 'errno 13')
	expect(mut t, db, sam, ['read', '/root/.vinix-user'], 'errno 13')
	expect(mut t, db, sam, ['read', '/etc/shadow'], 'errno 13')
	expect(mut t, db, sam, ['write', '/etc/shadow'], 'errno 13')
	expect(mut t, db, sam, ['write', '/etc/passwd'], 'errno 13')
	expect(mut t, db, sam, ['write', '/etc/group'], 'errno 13')
	expect(mut t, db, sam, ['write', '/etc/new-file'], 'errno 13')
	expect(mut t, db, sam, ['write', '/usr/share/vinix/actions/planted'], 'errno 13')
	expect(mut t, db, sam, ['write', '/usr/sbin/vinix-authd'], 'errno 13')
	expect(mut t, db, sam, ['write', '/sbin/init'], 'errno 13')
	expect(mut t, db, sam, ['write', '/home/planted'], 'errno 13')
	// Sam and what is Sam's or everyone's.
	expect(mut t, db, sam, ['write', '/home/sam/Documents/note.txt'], 'ok 1')
	expect(mut t, db, sam, ['read', '/home/sam/Documents/note.txt'], 'ok 1')
	expect(mut t, db, sam, ['read', '/etc/passwd'], 'ok')
	expect(mut t, db, sam, ['write', '/tmp/sam-was-here'], 'ok 1')
	// Alex is an administrator, which is not root: the same refusals.
	expect(mut t, db, alex, ['read', '/home/alex/Documents/diary.txt'], 'ok 8')
	expect(mut t, db, alex, ['read', '/home/sam/Documents/note.txt'], 'errno 13')
	expect(mut t, db, alex, ['read', '/etc/shadow'], 'errno 13')
	expect(mut t, db, alex, ['write', '/etc/passwd'], 'errno 13')
	// What Sam left in /tmp is Sam's to remove, not Alex's.
	t.check(owner_of('/tmp/sam-was-here') == int(sam.uid), '/tmp/sam-was-here belongs to ${owner_of('/tmp/sam-was-here')}')

	// A session.
	session := run(['/usr/sbin/vinix-session', 'run', 'sam', '/sbin/init', 'probe', 'ids'],
		'', none, none)
	want := 'uid=${sam.uid} euid=${sam.uid} gid=${sam.gid} groups=100 caps=0000000000000000 permitted=0000000000000000 bounding=0000000000000000 nnp=1 home=/home/sam runtime=/run/user/${sam.uid} user=sam cwd=/home/sam'
	t.check(session.status == 0 && session.output.trim_space().starts_with(want), 'a session as sam: ${session.output.trim_space()}')
	t.check(mode_of('/run/user/${sam.uid}') == 0o700 && owner_of('/run/user/${sam.uid}') == int(sam.uid),
		'/run/user/${sam.uid} is mode ${mode_of('/run/user/${sam.uid}'):o}, owner ${owner_of('/run/user/${sam.uid}')}')
	admin_session := run(['/usr/sbin/vinix-session', 'run', 'alex', '/sbin/init', 'probe', 'ids'],
		'', none, none)
	t.check(admin_session.output.contains('uid=${alex.uid} ') && admin_session.output.contains(' groups=10,100 ')
		&& admin_session.output.contains(' caps=0000000000000000 '), 'a session as alex: ${admin_session.output.trim_space()}')
	// Application sessions discard all account memberships before the user
	// loses permission to clear them. Normal login sessions retain theirs.
	isolated := run(['/usr/sbin/vinix-session', 'run', '--isolated', 'alex', '/sbin/init', 'probe', 'ids'], '', none, none)
	t.check(isolated.status == 0 && isolated.output.contains('uid=${alex.uid} euid=${alex.uid} gid=${alex.gid} groups= caps=0000000000000000 permitted=0000000000000000 bounding=0000000000000000 nnp=1')
		&& isolated.output.contains('home=/home/alex') && isolated.output.contains('login=${alex.uid}/'), 'isolated application session: ${isolated.status} ${isolated.output.trim_space()}')
	isolated_root := run(['/usr/sbin/vinix-session', 'run', '--isolated', 'root', '/sbin/init', 'probe', 'ids'], '', none, none)
	t.check(isolated_root.status == 126 && !isolated_root.output.contains('uid=0'), 'isolated root session was accepted')
	isolated_by_sam := run(['/usr/sbin/vinix-session', 'run', '--isolated', 'alex', '/sbin/init', 'probe', 'ids'], '', db, sam)
	t.check(isolated_by_sam.status == 1 && !isolated_by_sam.output.contains('uid='), 'an ordinary user created an isolated session')
	// Never root's, never the login screen's by this door, and only root
	// opens it.
	as_root := run(['/usr/sbin/vinix-session', 'run', 'root', '/sbin/init', 'probe', 'ids'],
		'', none, none)
	t.check(as_root.status == 126 && !as_root.output.contains('uid=0'), 'a session as root: ${as_root.status} ${as_root.output.trim_space()}')
	by_sam := run(['/usr/sbin/vinix-session', 'run', 'alex', '/sbin/init', 'probe', 'ids'],
		'', db, sam)
	t.check(by_sam.status == 1 && !by_sam.output.contains('uid='), 'sam starting a session as alex: ${by_sam.status} ${by_sam.output.trim_space()}')
	add_by_sam := run(['/usr/sbin/vinix-account', 'add', 'planted'], '', db, sam)
	t.check(add_by_sam.status != 0 && load_db().users.len == db.users.len, 'sam running vinix-account add: ${add_by_sam.status} ${add_by_sam.output.trim_space()}')

	// Changes through the tool, and what it refuses.
	locked := run(['/usr/sbin/vinix-account', 'lock', 'sam', 'on'], '', none, none)
	t.check(locked.status == 0, 'locking sam: ${locked.output}')
	sam_shadow := load_db().shadow('sam') or { accountcore.Shadow{} }
	t.check(accountcore.is_locked(sam_shadow.hash) && !accountcore.verify_password(sam_shadow.hash,
		sam_password.bytes()), 'a locked account still matches its password')
	run(['/usr/sbin/vinix-account', 'lock', 'sam', 'off'], '', none, none)
	unlocked := load_db().shadow('sam') or { accountcore.Shadow{} }
	t.check(accountcore.verify_password(unlocked.hash, sam_password.bytes()), 'unlocking did not give the password back')
	weak := run(['/usr/sbin/vinix-account', 'passwd', 'sam'], 'short\n', none, none)
	t.check(weak.status != 0, 'a five-letter password was accepted')
	run(['/usr/sbin/vinix-account', 'admin', 'alex', 'off'], '', none, none)
	last := run(['/usr/sbin/vinix-account', 'admin', 'first-user', 'off'], '', none, none)
	t.check(last.status != 0 && last.output.contains('only administrator'), 'the last administrator could be demoted: ${last.output}')
	removed := run(['/usr/sbin/vinix-account', 'remove', '--remove-home', 'sam'], '', none,
		none)
	after := load_db()
	t.check(removed.status == 0 && !has_user(after, 'sam') && !has_group(after, 'sam')
		&& !has_shadow(after, 'sam') && !os.exists('/home/sam'), 'removing sam: ${removed.output}')
	t.check(!read_text('/etc/group').contains('sam'), 'sam is still in a group')
	t.check(os.is_dir('/home/alex'), 'removing sam took alex\'s home')
}
