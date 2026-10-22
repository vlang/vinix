// SPDX-License-Identifier: GPL-2.0-or-later
module accountcore

import os

$if track_heap ? {
	#include "heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

const owned_passwd = 'root:x:0:0:root:/root:/bin/sh\nalex:x:1000:1000:Alex:/home/alex:/bin/zsh\n'
const owned_group = 'root:x:0:\nwheel:x:10:alex\nalex:x:1000:\n'
const owned_shadow = 'root:*:19000:0:99999:7:::\nalex:!x:1::::::\n'
const owned_bad_uid = owned_passwd + 'bad:x:not-a-number:1::/:/bin/sh\n'
const owned_bad_group = owned_group + 'broken:x:2\n'
const owned_bad_shadow = owned_shadow + 'broken:*:1::\n'
const owned_duplicate_uid = owned_passwd + 'duplicate:x:1000:1000::/:/bin/sh\n'
const owned_duplicate_gid = owned_group + 'duplicate:x:1000:\n'
const owned_duplicate_member = owned_group + 'repeat:x:44:alex,alex\n'

fn ownership_error(err IError) {
	message := err.msg()
	assert message.len > 0
	unsafe { message.free(); err.free() }
}

fn owned_cycle(passwd string, group string, shadow string, refused bool) {
	mut db := Database{}
	defer { db.close(); db.close() }
	db.users = parse_passwd(passwd) or { ownership_error(err); assert refused; return }
	db.groups = parse_group(group) or { ownership_error(err); assert refused; return }
	db.shadows = parse_shadow(shadow) or { ownership_error(err); assert refused; return }
	db.validate() or { ownership_error(err); assert refused; return }
	assert !refused
	mut independent := (db.user('alex') or { panic('missing person') }).owned_copy()
	db.close()
	assert independent.name == 'alex' && independent.home == '/home/alex'
	assert independent.shell == '/bin/zsh' && independent.uid == 1000
	independent.close(); independent.close()
}

fn test_owned_snapshots_and_partial_refusals() {
	for _ in 0 .. 1000 {
		$if track_heap ? { C.vinix_heap_begin() }
		owned_cycle(owned_passwd, owned_group, owned_shadow, false)
		owned_cycle(owned_bad_uid, owned_group, '', true)
		owned_cycle(owned_passwd, owned_bad_group, '', true)
		owned_cycle(owned_passwd, owned_group, owned_bad_shadow, true)
		owned_cycle(owned_duplicate_uid, owned_group, '', true)
		owned_cycle(owned_passwd, owned_duplicate_gid, '', true)
		owned_cycle(owned_passwd, owned_duplicate_member, '', true)
		owned_cycle('bad name:x:1:1::/:/bin/sh\n', owned_group, '', true)
		owned_cycle('alex:x:1000:77::/:/bin/sh\n', owned_group, '', true)
		owned_cycle('root:x:0:0:root:/root:/bin/sh\r\n', owned_group, '', true)
		owned_cycle('root:x:0:0:root:/root:/bin/sh', owned_group, '', true)
		$if track_heap ? { assert C.vinix_heap_end() == 0 }
	}
}

fn test_store_snapshots_release_file_buffers_and_lookup_borrows() ! {
	pid := os.getpid().str()
	directory := os.temp_dir() + '/vinix-account-owned-' + pid
	defer { os.rmdir_all(directory) or {}; unsafe { pid.free(); directory.free() } }
	os.mkdir_all(directory)!
	passwd := directory + '/passwd'; group := directory + '/group'; shadow := directory + '/shadow'
	defer { unsafe { passwd.free(); group.free(); shadow.free() } }
	os.write_file(passwd, owned_passwd)!; os.write_file(group, owned_group)!; os.write_file(shadow, owned_shadow)!
	os.chmod(shadow, 0o600)!
	store := Store{etc: directory, owned: false}
	for _ in 0 .. 1000 {
		$if track_heap ? { C.vinix_heap_begin() }
		mut db := store.load_public()!
		assert db.shadows.len == 0 && db.users.len == 2 && db.groups.len == 3
		mut user := (db.user('alex') or { panic('missing account') }).owned_copy()
		db.close(); db.close()
		assert user.name == 'alex'
		user.close()
		$if track_heap ? {
			remaining := C.vinix_heap_end()
			assert remaining == 0
			C.vinix_heap_begin()
		}
		mut complete := store.load()!
		assert complete.shadows.len == 2
		complete.close()
		$if track_heap ? { assert C.vinix_heap_end() == 0 }
	}
	for bad in [owned_bad_uid, owned_duplicate_uid]! {
		os.write_file(passwd, bad)!
		for _ in 0 .. 100 {
			$if track_heap ? { C.vinix_heap_begin() }
			if _ := store.load_public() { assert false } else { ownership_error(err) }
			$if track_heap ? { assert C.vinix_heap_end() == 0 }
		}
	}
}
