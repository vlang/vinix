// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module accountcore

import os

const cheap = Cost{
	ln: 10
	r:  8
	p:  1
}

const base_passwd = 'root:x:0:0:root:/root:/bin/sh\n'
const base_group = 'root:x:0:\n'

fn test_names() ! {
	assert valid_name('alex')
	assert valid_name('_svc')
	assert valid_name('a-b_c9')
	assert !valid_name('')
	assert !valid_name('Alex')
	assert !valid_name('9lives')
	assert !valid_name('-x')
	assert !valid_name('a b')
	assert !valid_name('a:b')
	assert !valid_name('a/b')
	assert !valid_name('a.b')
	assert !valid_name('a\nb')
	assert !valid_name('a'.repeat(33))
	assert valid_name('a'.repeat(32))
}

fn test_paths_and_fields() ! {
	assert valid_path('/home/alex')
	assert valid_path('/')
	assert !valid_path('home/alex')
	assert !valid_path('/home/../etc')
	assert !valid_path('/home//alex')
	assert !valid_path('/home/alex/')
	assert !valid_path('/home/./alex')
	assert !valid_path('/home/a:b')
	assert valid_field('Алекс Медведников', max_gecos)
	assert !valid_field('a:b', max_gecos)
	assert !valid_field('a\nb', max_gecos)
	assert !valid_field('a\x00b', max_gecos)
	assert !valid_field([u8(0xff), 0xfe].bytestr(), max_gecos)
	assert !valid_field([u8(0xc3)].bytestr(), max_gecos)
	assert !valid_field([u8(0xc0), 0x80].bytestr(), max_gecos)
}

fn test_parse_passwd_strict() ! {
	users := parse_passwd('root:x:0:0:root:/root:/bin/sh\nalex:x:1000:1000:Alex:/home/alex:/bin/zsh\n')!
	assert users.len == 2
	assert users[1].name == 'alex' && users[1].uid == 1000 && users[1].shell == '/bin/zsh'
	assert format_passwd(users) == 'root:x:0:0:root:/root:/bin/sh\nalex:x:1000:1000:Alex:/home/alex:/bin/zsh\n'
	// Every way a line could be read as something it is not.
	for bad in [
		'root:x:0:0:root:/root\n', // a field short
		'root:x:0:0:root:/root:/bin/sh:extra\n',
		'root::0:0:root:/root:/bin/sh\n', // an empty password in passwd
		'root:secret:0:0:root:/root:/bin/sh\n',
		'evil:x:00:0::/:/bin/sh\n', // another spelling of 0
		'evil:x:+0:0::/:/bin/sh\n',
		'evil:x:-1:0::/:/bin/sh\n',
		'evil:x:0x0:0::/:/bin/sh\n',
		'evil:x: 0:0::/:/bin/sh\n',
		'evil:x:4294967295:0::/:/bin/sh\n', // (uid_t)-1
		'evil:x:4294967296:0::/:/bin/sh\n',
		'evil:x:99999999999:0::/:/bin/sh\n',
		'evil:x::0::/:/bin/sh\n',
		'root:x:0:0:root:/root:/bin/sh', // no final line break
		'root:x:0:0:root:/root:/bin/sh\r\n',
		'root:x:0:0:ro\x00ot:/root:/bin/sh\n',
	] {
		parse_passwd(bad) or { continue }
		assert false, 'accepted ${bad.bytes()}'
	}
}

fn test_parse_group_and_shadow() ! {
	groups := parse_group('root:x:0:\nwheel:x:10:alex,sam\n')!
	assert groups[1].members == ['alex', 'sam']
	assert format_group(groups) == 'root:x:0:\nwheel:x:10:alex,sam\n'
	// A group password is refused, like a password in passwd.
	parse_group('wheel:secret:10:alex\n') or {
		assert err.msg().contains('password field')
	}
	parse_group('wheel:x:10\n') or {
		shadows := parse_shadow('root:*:19000:0:99999:7:::\nalex:!x:1::::::\n')!
		assert shadows[0].ageing == ['0', '99999', '7', '', '', '']
		assert format_shadow(shadows) == 'root:*:19000:0:99999:7:::\nalex:!x:1::::::\n'
		parse_shadow('root:*:19000:0:99999:7::\n') or { return }
		assert false
		return
	}
	assert false
}

fn test_validate_refuses_duplicates() ! {
	mut db := Database{
		users:  parse_passwd('root:x:0:0:root:/root:/bin/sh\ntoor:x:0:0:root:/root:/bin/sh\n')!
		groups: parse_group(base_group)!
	}
	db.validate() or {
		assert err.msg().contains('uid 0 is used twice')
		db.users = parse_passwd('root:x:0:0:root:/root:/bin/sh\nroot:x:1:0:root:/root:/bin/sh\n')!
		db.validate() or {
			assert err.msg().contains('listed twice')
			db.users = parse_passwd('root:x:0:5:root:/root:/bin/sh\n')!
			db.validate() or {
				assert err.msg().contains('does not exist')
				return
			}
		}
	}
	assert false
}

fn test_ab64_round_trip() ! {
	for length in 0 .. 40 {
		mut data := []u8{len: length}
		for i in 0 .. length {
			data[i] = u8(i * 37 + length)
		}
		assert ab64_decode(ab64_encode(data))! == data
	}
	// passlib's own example for 16 zero bytes and for "password".
	assert ab64_encode('password'.bytes()) == 'cGFzc3dvcmQ'
	ab64_decode('cGFzc3dvcmR') or {
		ab64_decode('c') or {
			ab64_decode('cG+z') or { return }
		}
	}
	assert false
}

fn test_password_records() ! {
	password := 'correct horse battery'.bytes()
	hash := hash_password(password, cheap)!
	assert hash.starts_with(r'$scrypt$ln=10,r=8,p=1$')
	assert has_password(hash)
	assert verify_password(hash, password)
	assert !verify_password(hash, 'correct horse batterz'.bytes())
	assert !verify_password(hash, []u8{})
	// Two records of one password do not look alike.
	assert hash_password(password, cheap)! != hash
	// Locked, absent and foreign records match nothing -- not even nothing.
	assert !verify_password('!' + hash, password)
	assert !verify_password('*', password)
	assert !verify_password('', []u8{})
	assert !verify_password('', password)
	assert !verify_password(r'$6$salt$hash', password)
	assert !has_password('!' + hash) && is_locked('!' + hash)
	assert needs_rehash(hash, default_cost)
	assert !needs_rehash(hash, cheap)
	// A record asking for more work than is allowed is not run.
	assert !has_password(r'$scrypt$ln=30,r=8,p=1$AAAAAAAAAAAAAAAAAAAAAA$' + 'A'.repeat(43))
	assert !has_password(r'$scrypt$ln=14,r=8,p=1$AAAA$' + 'A'.repeat(43))
	assert !has_password(r'$scrypt$ln=014,r=8,p=1$AAAAAAAAAAAAAAAAAAAAAA$' + 'A'.repeat(43))
}

// RFC 7914's second test vector (the first 32 bytes of its 64), to tie the
// record format to the algorithm everyone else means by the name.
fn test_scrypt_known_answer() ! {
	cost := Cost{
		ln: 10
		r:  8
		p:  16
	}
	key := scrypt_key('password'.bytes(), 'NaCl'.bytes(), cost)!
	assert key.hex() == 'fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162'
	// A salt that short is not accepted in a record, though.
	assert !has_password(format_record(cost, 'NaCl'.bytes(), key))
	longer := scrypt_key('password'.bytes(), 'NaClNaCl'.bytes(), cost)!
	assert verify_password(format_record(cost, 'NaClNaCl'.bytes(), longer), 'password'.bytes())
}

fn test_password_policy() ! {
	check_new_password('alex', 'longenough1'.bytes())!
	for bad in ['short', 'aaaaaaaaaa', 'alexander', 'has\nnewline!', 'x'.repeat(300)] {
		check_new_password('alexander', bad.bytes()) or { continue }
		assert false, bad
	}
	check_new_password('alex', 'ALEXANDER'.bytes())!
	check_new_password('alexander', 'ALEXANDER'.bytes()) or { return }
	assert false
}

fn test_import_registration() ! {
	// A record as desktop/registration_store.v writes it, for "Alex M" with
	// a 16-byte salt of 01.. and a key computed here at the same cost.
	salt := []u8{len: 16, init: u8(index + 1)}
	key := scrypt_key('hunter22'.bytes(), salt, Cost{ ln: 14, r: 8, p: 1 })!
	record := 'version=1\nname=416c6578204d\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=' +
		salt.hex() + '\nhash=' + key.hex() + '\n'
	name, hash := import_registration(record)!
	assert name == 'Alex M'
	assert login_name_for(name) == 'alex-m'
	assert verify_password(hash, 'hunter22'.bytes())
	assert !verify_password(hash, 'hunter23'.bytes())
	assert needs_rehash(hash, default_cost)
	import_registration(record.replace('n=16384', 'n=2')) or {
		import_registration('') or { return }
	}
	assert false
}

fn test_login_names() ! {
	assert login_name_for('Alexander Medvednikov') == 'alexander-medvednikov'
	assert login_name_for('  --Sam!!  ') == 'sam'
	assert login_name_for('42') == 'u42'
	assert login_name_for('Ünï') == 'n'
	assert login_name_for('Юзер') == 'user'
	assert valid_name(login_name_for('A'.repeat(48)))
	assert valid_name(login_name_for('9' + 'a b'.repeat(16)))
}

fn new_db() Database {
	mut db := Database{
		users:  parse_passwd(base_passwd) or { panic(err) }
		groups: parse_group(base_group) or { panic(err) }
	}
	db.ensure_system_accounts() or { panic(err) }
	return db
}

fn test_system_accounts() ! {
	mut db := new_db()
	assert must_group(db, 'wheel').gid == 10
	assert must_group(db, 'users').gid == 100
	assert must_user(db, 'nobody').uid == 65534
	greeter := must_user(db, 'greeter')
	assert greeter.uid >= first_system_id && greeter.uid <= last_system_id
	assert !db.is_admin(greeter)
	assert must_shadow(db, 'root').hash == '*'
	assert must_shadow(db, 'greeter').hash == '*'
	// Doing it again changes nothing.
	before := format_passwd(db.users) + format_group(db.groups) + format_shadow(db.shadows)
	db.ensure_system_accounts()!
	assert before == format_passwd(db.users) + format_group(db.groups) + format_shadow(db.shadows)
}

fn test_add_and_remove_users() ! {
	mut db := new_db()
	hash := hash_password('first password'.bytes(), cheap)!
	alex := db.add_user(name: 'alex', gecos: 'Alex', admin: true, hash: hash)!
	assert alex.uid == 1000 && alex.gid == 1000 && alex.home == '/home/alex'
	assert db.is_admin(alex)
	assert db.in_group(alex, 'users')
	assert must_group(db, 'alex').gid == 1000
	sam := db.add_user(name: 'sam', gecos: 'Sam', hash: hash)!
	assert sam.uid == 1001
	assert !db.is_admin(sam)
	assert db.supplementary_gids(sam) == [u32(100)]
	assert db.supplementary_gids(alex) == [u32(10), 100]
	assert db.people().map(it.name) == ['alex', 'sam']
	// Refusals leave the database as it was.
	before := format_passwd(db.users) + format_group(db.groups) + format_shadow(db.shadows)
	for bad in [
		NewUser{ name: 'alex' },
		NewUser{ name: 'root' },
		NewUser{ name: 'wheel' },
		NewUser{ name: 'Bad' },
		NewUser{ name: 'ok', gecos: 'a:b' },
		NewUser{ name: 'ok', gecos: 'a,b' },
		NewUser{ name: 'ok', home: '/home/../root' },
		NewUser{ name: 'ok', shell: 'sh' },
		NewUser{ name: 'ok', hash: 'plain' },
	] {
		db.add_user(bad) or { continue }
		assert false, bad.name
	}
	assert before == format_passwd(db.users) + format_group(db.groups) + format_shadow(db.shadows)
	// The only administrator stays.
	db.remove_user('alex') or {
		assert err.msg().contains('only administrator')
		db.set_locked('alex', true) or {
			db.set_admin('alex', false) or {
				db.set_admin('sam', true)!
				db.remove_user('alex')!
				assert gone_user(db, 'alex')
				assert gone_group(db, 'alex')
				assert gone_shadow(db, 'alex')
				assert must_group(db, 'wheel').members == ['sam']
				assert must_group(db, 'users').members == ['sam']
				db.validate()!
				// A new account under an old name gets none of the old
				// one's password.
				db.shadows << Shadow{
					name:    'ghost'
					hash:    hash
					changed: '1'
					ageing:  ['', '', '', '', '', '']
				}
				ghost := db.add_user(name: 'ghost')!
				assert must_shadow(db, 'ghost').hash == '*'
				assert ghost.uid == 1000
				return
			}
		}
	}
	assert false
}

fn test_lock_and_unlock() ! {
	mut db := new_db()
	hash := hash_password('first password'.bytes(), cheap)!
	db.add_user(name: 'alex', admin: true, hash: hash)!
	db.add_user(name: 'sam', hash: hash)!
	db.set_locked('sam', true)!
	db.set_locked('sam', true)!
	assert must_shadow(db, 'sam').hash == '!' + hash
	assert !verify_password(must_shadow(db, 'sam').hash, 'first password'.bytes())
	db.set_locked('sam', false)!
	assert must_shadow(db, 'sam').hash == hash
	// An administrator whose account is locked does not count as one who
	// could still administer.
	db.set_admin('sam', true)!
	db.set_locked('sam', true)!
	db.remove_user('alex') or { return }
	assert false
}

fn test_store_round_trip() ! {
	dir := os.join_path(os.temp_dir(), 'vinix-accountcore-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	store := Store{
		etc:   dir
		owned: false
	}
	os.write_file(store.passwd_path(), base_passwd)!
	os.write_file(store.group_path(), base_group)!
	os.chmod(store.passwd_path(), 0o644)!
	os.chmod(store.group_path(), 0o644)!
	held := store.lock(true)!
	mut db := store.load()!
	db.ensure_system_accounts()!
	db.add_user(name: 'alex', admin: true, hash: hash_password('first password'.bytes(),
		cheap)!)!
	store.save(db)!
	held.release()
	again := store.load()!
	assert must_user(again, 'alex').uid == 1000
	assert verify_password(must_shadow(again, 'alex').hash, 'first password'.bytes())
	assert os.stat(store.shadow_path())!.mode & 0o777 == 0o600
	assert os.stat(store.passwd_path())!.mode & 0o777 == 0o644
	assert !os.exists(store.passwd_path() + '.new')
	public := store.load_public()!
	assert public.shadows.len == 0 && public.users.len == again.users.len
	// A password file others can read, or any file others can write, is
	// not believed.
	os.chmod(store.shadow_path(), 0o644)!
	store.load() or {
		assert err.msg().contains('readable by others')
		os.chmod(store.shadow_path(), 0o600)!
		os.chmod(store.passwd_path(), 0o666)!
		store.load() or {
			assert err.msg().contains('writable by others')
			os.chmod(store.passwd_path(), 0o644)!
			// Nor is a link standing in for one.
			os.rename(store.group_path(), store.group_path() + '.real')!
			os.symlink(store.group_path() + '.real', store.group_path())!
			store.load() or { return }
		}
	}
	assert false
}

fn test_throttle_schedule() ! {
	now := i64(1_800_000_000)
	assert wait_for(Failures{ count: 0 }, now) == 0
	assert wait_for(Failures{ count: 2, last: now }, now) == 0
	assert wait_for(Failures{ count: 3, last: now }, now) == 2
	assert wait_for(Failures{ count: 4, last: now }, now) == 4
	assert wait_for(Failures{ count: 5, last: now }, now) == 8
	assert wait_for(Failures{ count: 5, last: now - 3 }, now) == 5
	assert wait_for(Failures{ count: 5, last: now - 8 }, now) == 0
	assert wait_for(Failures{ count: 40, last: now }, now) == 300
	assert wait_for(Failures{ count: 1_000_000, last: now }, now) == 300
	// A clock set back does not lengthen the wait, and an hour clears it.
	assert wait_for(Failures{ count: 5, last: now + 10_000 }, now) == 8
	assert wait_for(Failures{ count: 40, last: now - 3600 }, now) == 0
}

fn test_throttle_files() ! {
	dir := os.join_path(os.temp_dir(), 'vinix-throttle-${os.getpid()}')
	os.rmdir_all(dir) or {}
	defer { os.rmdir_all(dir) or {} }
	throttle := Throttle{
		directory: dir
	}
	now := i64(1_800_000_000)
	assert throttle.read('alex', now).count == 0
	for i in 0 .. 4 {
		throttle.record_failure('alex', now + i)
	}
	failures := throttle.read('alex', now + 3)
	assert failures.count == 4 && failures.last == now + 3
	assert wait_for(failures, now + 3) == 4
	assert os.stat(dir)!.mode & 0o777 == 0o700
	// A name that could not be an account never becomes a path.
	throttle.record_failure('../../etc/cron', now)
	throttle.record_failure('a/b', now)
	assert os.ls(dir)! == ['alex']
	throttle.record_success('alex')
	assert throttle.read('alex', now).count == 0
	// Garbage in a record is no record.
	os.write_file(os.join_path(dir, 'sam'), 'many recently\n')!
	assert throttle.read('sam', now).count == 0
	os.write_file(os.join_path(dir, 'sam'), '-5 ${now}\n')!
	assert throttle.read('sam', now).count == 0
}

fn must_user(db Database, name string) User {
	return db.user(name) or { panic('no user ${name}') }
}

fn must_group(db Database, name string) Group {
	return db.group(name) or { panic('no group ${name}') }
}

fn must_shadow(db Database, name string) Shadow {
	return db.shadow(name) or { panic('no password record of ${name}') }
}

fn gone_user(db Database, name string) bool {
	db.user(name) or { return true }
	return false
}

fn gone_group(db Database, name string) bool {
	db.group(name) or { return true }
	return false
}

fn gone_shadow(db Database, name string) bool {
	db.shadow(name) or { return true }
	return false
}

fn test_configured_cost() ! {
	dir := os.join_path(os.temp_dir(), 'vinix-cost-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	path := os.join_path(dir, 'auth.conf')
	assert configured_cost(path, false)! == default_cost
	os.write_file(path, '# more work\nscrypt_ln = 16\nscrypt_p = 2\n')!
	os.chmod(path, 0o644)!
	cost := configured_cost(path, false)!
	assert cost.ln == 16 && cost.r == 8 && cost.p == 2
	for bad in ['scrypt_ln = 9\n', 'scrypt_ln = 19\n', 'scrypt_p = 0\n', 'scrypt_ln = many\n',
		'scrypt_ln 16\n', 'kdf = md5\n', 'scrypt_ln = 16 = 17\n'] {
		os.write_file(path, bad)!
		configured_cost(path, false) or { continue }
		assert false, bad
	}
	// A settings file anyone can write decides nothing.
	os.write_file(path, 'scrypt_ln = 10\n')!
	os.chmod(path, 0o666)!
	configured_cost(path, false) or { return }
	assert false
}
