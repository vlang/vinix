// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The targets: each a parser that reads bytes someone else chose, with what
// must hold of anything it accepts.
module main

import accountcore
import authcore
import authproto
import eventcore
import fdtstrings
import fuzzcore
import posix_acl

const passwd_seed = 'root:x:0:0:root:/root:/bin/sh\nalex:x:1000:1000:Alex Example:/home/alex:/bin/zsh\nnobody:x:65534:65534:nobody:/:/sbin/nologin\n'
const group_seed = 'root:x:0:\nwheel:x:10:alex,sam\nusers:x:100:alex,sam,kim\nalex:x:1000:\n'
const shadow_seed = 'root:*:19000:0:99999:7:::\nalex:\$scrypt\$ln=15,r=8,p=1\$AAECAwQFBgcICQoLDA0ODw\$AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8:20000::::::\nsam:!x:1::::::\n'
const record_seed = '\$scrypt\$ln=15,r=8,p=1\$AAECAwQFBgcICQoLDA0ODw\$AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8'
const registration_seed = 'version=1\nname=416c6578204d\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=000102030405060708090a0b0c0d0e0f\nhash=000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\n'
const action_seed = '# add someone\ndescription = Add a user account\nauth = admin\nexec = /usr/sbin/vinix-account\narg = add\nparam = name\nparam = text\nparam = choice:admin,standard\ninput = secret\n'
const snapshot_seed = 'version=1 capacity=256 total=3 retained=2 dropped=0 boot=00112233445566778899aabbccddeeff\n# sequence ns kind denied pid tid uid euid loginuid session arg label\n2 2000 1 1 42 42 1001 1001 1001 3 0 system/hostname/set\n3 3000 7 1 43 43 1001 1001 4294967295 0 80 bind\n'
const log_seed = 'boundary boot=00112233445566778899aabbccddeeff previous=none collected=1\nloss boot=00112233445566778899aabbccddeeff first=1 last=44 count=44 collected=1\nevent boot=00112233445566778899aabbccddeeff seq=45 ns=5 collected=1 kind=network result=denied pid=42 tid=42 uid=1001 euid=1001 login=1001 session=3 arg=80 label=bind\n'

fn frame_seed() string {
	data := authproto.encode(authproto.text_frame(authproto.op_run, 'hostname-set', 'a password',
		'', 'testbox')) or { return '' }
	return data.bytestr()
}

// A version 2 access list as Linux's userspace writes it: owner, a named
// user, owning group, mask, other.
fn acl_seed() string {
	mut data := [u8(2), 0, 0, 0]
	for entry in [[u32(1), 6, 0xffffffff], [u32(2), 4, 1000], [u32(4), 4, 0xffffffff],
		[u32(16), 4, 0xffffffff], [u32(32), 0, 0xffffffff]] {
		data << u8(entry[0])
		data << u8(0)
		data << u8(entry[1])
		data << u8(0)
		data << u8(entry[2])
		data << u8(entry[2] >> 8)
		data << u8(entry[2] >> 16)
		data << u8(entry[2] >> 24)
	}
	return data.bytestr()
}

fn fuzz_passwd(data []u8) ! {
	text := data.bytestr()
	users := accountcore.parse_passwd(text) or { return }
	// What is accepted writes back as the same bytes: there is one
	// spelling of a file, so two readers cannot disagree about it.
	if accountcore.format_passwd(users) != text {
		return error('accepted text does not format back to itself')
	}
	for user in users {
		if user.name.contains(':') || user.name.contains('\n') {
			return error('a name with a separator in it was accepted')
		}
	}
	db := accountcore.Database{
		users: users
	}
	db.validate() or { return }
	// A database that passes has exactly one account per uid.
	mut uids := map[u32]bool{}
	for user in db.users {
		if user.uid in uids {
			return error('two accounts with uid ${user.uid} passed validation')
		}
		uids[user.uid] = true
	}
}

fn fuzz_group(data []u8) ! {
	text := data.bytestr()
	groups := accountcore.parse_group(text) or { return }
	if accountcore.format_group(groups) != text {
		return error('accepted text does not format back to itself')
	}
}

fn fuzz_shadow(data []u8) ! {
	text := data.bytestr()
	shadows := accountcore.parse_shadow(text) or { return }
	if accountcore.format_shadow(shadows) != text {
		return error('accepted text does not format back to itself')
	}
	for shadow in shadows {
		// Never the comparison itself here: that is half a second of scrypt.
		if accountcore.has_password(shadow.hash) && accountcore.is_locked(shadow.hash) {
			return error('a locked record counts as having a password')
		}
	}
}

fn fuzz_record(data []u8) ! {
	hash := data.bytestr()
	if accountcore.has_password(hash) {
		if !hash.starts_with('\$scrypt\$') || hash.len > accountcore.max_hash {
			return error('something that is not a scrypt record was accepted')
		}
		// Accepted means bounded: nothing here may ask for gigabytes.
		if hash.contains('ln=19') || hash.contains('ln=2') || hash.contains('ln=3') {
			return error('a record asking for too much work was accepted')
		}
	}
	accountcore.needs_rehash(hash, accountcore.default_cost)
}

fn fuzz_registration(data []u8) ! {
	name, hash := accountcore.import_registration(data.bytestr()) or { return }
	if name.len == 0 || name.len > 48 || !accountcore.has_password(hash) {
		return error('an import produced a name or a record that is not one')
	}
	if !accountcore.valid_name(accountcore.login_name_for(name)) {
		return error('a display name gave an invalid login name')
	}
}

fn fuzz_action(data []u8) ! {
	action := authcore.parse_action('fuzzed', data.bytestr()) or { return }
	if action.exec == '' || action.exec[0] != `/` || action.exec.contains('..')
		|| action.description == '' {
		return error('an action without an absolute program or a description was accepted')
	}
	for argument in action.args {
		if argument.contains('\n') || argument.len == 0 {
			return error('a fixed argument with a line break, or an empty one, was accepted')
		}
	}
	// Whatever a caller supplies, the vector starts with the program and
	// the fixed arguments and nothing supplied starts with a hyphen unless
	// it is one of the action's own choices.
	supplied := []string{len: action.params.len, init: '-rf'}
	argv := action.arguments(supplied) or { return }
	for index, param in action.params {
		if param.kind != .choice {
			return error('"-rf" was accepted for parameter ${index}')
		}
	}
	if argv[0] != action.exec {
		return error('the vector does not start with the program')
	}
}

fn fuzz_frame(data []u8) ! {
	frame := authproto.decode(data) or { return }
	again := authproto.encode(frame) or { return error('a decoded frame does not encode') }
	if again != data {
		return error('a decoded frame encodes to other bytes')
	}
	if frame.fields.len > authproto.max_fields {
		return error('too many fields were accepted')
	}
}

fn fuzz_snapshot(data []u8) ! {
	snapshot := eventcore.parse_snapshot(data.bytestr()) or { return }
	if u64(snapshot.events.len) != snapshot.retained || snapshot.retained > snapshot.total {
		return error('the header and the records disagree')
	}
	for index, event in snapshot.events {
		if event.sequence != snapshot.total - snapshot.retained + 1 + u64(index) {
			return error('records do not count up')
		}
	}
	// And what the collector makes of it: every record once, in order.
	lines, cursor := eventcore.advance(eventcore.Cursor{}, snapshot, 1)
	if cursor.last != snapshot.total {
		return error('the collector did not reach the end of the snapshot')
	}
	mut events := 0
	for line in lines {
		if line.contains('\n') {
			return error('a log line with a line break in it')
		}
		if line.starts_with('event ') {
			events++
		}
	}
	if events != snapshot.events.len {
		return error('${snapshot.events.len} records gave ${events} lines')
	}
	again, _ := eventcore.advance(cursor, snapshot, 2)
	if again.len != 0 {
		return error('a second pass over the same snapshot wrote something')
	}
}

fn fuzz_log_tail(data []u8) ! {
	cursor := eventcore.cursor_from_log(data.bytestr())
	if cursor.boot.contains(' ') || cursor.boot.contains('\n') {
		return error('a boot identity with white space in it')
	}
	eventcore.parse_retention(data.bytestr()) or { return }
}

fn fuzz_acl(data []u8) ! {
	if !posix_acl.valid(data) {
		// The on-disk form is a parser of its own.
		mut converted := []u8{}
		if posix_acl.from_disk(data, mut converted) && !posix_acl.valid(converted) {
			return error('a disk list converted to an invalid list')
		}
		return
	}
	if data.len == 4 {
		return
	}
	mode, _ := posix_acl.mode(data, 0o100644)
	if mode & ~u32(0o177777) != 0 {
		return error('a mode with bits outside a mode')
	}
	// Nobody gets more than was asked about, and asking for nothing is
	// always allowed.
	for uid in [u32(0), 1000, 65534] {
		posix_acl.permits(data, 0, 0, uid, uid, [u32(10), 100], 7)
		if !posix_acl.permits(data, 0, 0, uid, uid, []u32{}, 0) {
			return error('access to nothing was refused')
		}
	}
	mut disk := []u8{}
	if !posix_acl.to_disk(data, mut disk) {
		return error('a valid list does not convert to disk')
	}
	mut back := []u8{}
	if !posix_acl.from_disk(disk, mut back) || back != data {
		return error('a valid list does not survive the disk and back')
	}
}

fn fuzz_fdt_strings(data []u8) ! {
	if data.len == 0 {
		return
	}
	values := fdtstrings.clone_nul_list(data.data, u32(data.len)) or { return }
	mut total := 0
	for value in values {
		if value.len == 0 || value.contains('\x00') {
			return error('an empty string or one with a NUL in it')
		}
		total += value.len
	}
	if total > data.len {
		return error('more characters out than bytes in')
	}
}

const targets = [
	fuzzcore.Target{
		name:  'passwd'
		about: 'accountcore: /etc/passwd, and the database check on what it accepts'
		seeds: [passwd_seed, 'root:x:0:0::/:\n']
		run:   fuzz_passwd
	},
	fuzzcore.Target{
		name:  'group'
		about: 'accountcore: /etc/group'
		seeds: [group_seed]
		run:   fuzz_group
	},
	fuzzcore.Target{
		name:  'shadow'
		about: 'accountcore: /etc/shadow'
		seeds: [shadow_seed]
		run:   fuzz_shadow
	},
	fuzzcore.Target{
		name:  'password-record'
		about: 'accountcore: one scrypt record, without running scrypt'
		seeds: [record_seed, '*', '!' + record_seed]
		run:   fuzz_record
	},
	fuzzcore.Target{
		name:  'registration'
		about: 'accountcore: the desktop\'s old registration record'
		seeds: [registration_seed]
		run:   fuzz_registration
	},
	fuzzcore.Target{
		name:  'action'
		about: 'authcore: an action file, and the argument vector made from it'
		seeds: [action_seed, 'description = x\nauth = session\nexec = /bin/true\n']
		run:   fuzz_action
	},
	fuzzcore.Target{
		name:  'auth-frame'
		about: 'authproto: a request or reply on the service\'s socket'
		seeds: [frame_seed()]
		run:   fuzz_frame
	},
	fuzzcore.Target{
		name:  'event-snapshot'
		about: 'eventcore: /proc/security_events, and what the collector writes for it'
		seeds: [snapshot_seed]
		run:   fuzz_snapshot
	},
	fuzzcore.Target{
		name:  'event-log'
		about: 'eventcore: the end of a log a collector resumes from, and its settings'
		seeds: [log_seed, 'max_bytes = 65536\nkeep_files = 2\nmax_age_days = 0\n']
		run:   fuzz_log_tail
	},
	fuzzcore.Target{
		name:  'posix-acl'
		about: 'kernel/posix_acl: an access list from userspace or from an ext2 disk'
		seeds: [acl_seed()]
		run:   fuzz_acl
	},
	fuzzcore.Target{
		name:  'fdt-strings'
		about: 'kernel/fdtstrings: a string list from a device tree'
		seeds: ['apple,j313\x00apple,t8103\x00apple,arm-platform\x00', 'x\x00']
		run:   fuzz_fdt_strings
	},
]
