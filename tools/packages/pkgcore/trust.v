// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256

pub struct RepositoryFloor {
pub:
	id           string
	public_key   string
	sequence     u64
	index_sha256 string
}

pub struct TrustHistory {
pub:
	format       int = 1
	repositories []RepositoryFloor
}

fn floor_order(a &RepositoryFloor, b &RepositoryFloor) int {
	if a.id != b.id { return if a.id < b.id { -1 } else { 1 } }
	return if a.public_key < b.public_key {
		-1
	} else if a.public_key == b.public_key {
		0
	} else {
		1
	}
}

fn read_history(directory string) !TrustHistory {
	path := directory + '/trust-history.json'
	defer { unsafe { path.free() } }
	if history_file_missing(path) { return TrustHistory{} }
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	if history := decode_history(text, false) { return history } else {
		// The interface is consumed synchronously; an implicit address boxes it.
		message := unsafe { (&err).msg() }
		diagnostic := 'invalid repository trust history: ' + message
		unsafe { message.free(); (&err).free() }
		return error(diagnostic)
	}
}

// Only a missing pathname permits initial history. Capture no-follow stack
// scratch so an absent file does not retain os.is_link's failed-stat error.
fn history_file_missing(path string) bool {
	mut info := C.stat{}
	return C.lstat(path.str, unsafe { &info }) != 0 && C.errno == C.ENOENT
}

fn index_digest(text string) string {
	bytes := text.bytes()
	mut hash := sha256.new()
	mut sum := []u8{len: sha256.size}
	defer { unsafe { bytes.free(); sum.free(); hash.free(); free(hash) } }
	hash.write(bytes) or { panic(err) }
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn check_floor(history TrustHistory, repository Repository, index Index, digest string) ! {
	for floor in history.repositories {
		if floor.id != repository.id || floor.public_key != repository.public_key { continue }
		if index.sequence < floor.sequence || (index.sequence == floor.sequence && digest != floor.index_sha256) {
			return error('${repository.id}: repository rollback or sequence equivocation refused by retained trust history')
		}
	}
}

fn remember_index(history TrustHistory, repository Repository, index Index, text string) !TrustHistory {
	digest := index_digest(text)
	defer { unsafe { digest.free() } }
	check_floor(history, repository, index, digest)!
	mut count := 1
	for floor in history.repositories {
		if floor.id != repository.id || floor.public_key != repository.public_key { count++ }
	}
	if count > 4096 {
		return error('repository trust history exceeds its supported identity limit')
	}
	// Both retained and new records own their strings. Callers may retire the
	// previous history and the snapshot/configuration that supplied this identity.
	mut records := []RepositoryFloor{cap: count}
	unsafe { records.flags |= .noslices }
	for floor in history.repositories {
		if floor.id != repository.id || floor.public_key != repository.public_key { append_owned_floor(mut records, floor) }
	}
	append_owned_floor(mut records, RepositoryFloor{ id: repository.id, public_key: repository.public_key,
		sequence: index.sequence, index_sha256: digest })
	records.sort_with_compare(floor_order)
	return TrustHistory{ repositories: records }
}

fn append_owned_floor(mut records []RepositoryFloor, floor RepositoryFloor) {
	owned := RepositoryFloor{ id: floor.id.clone(), public_key: floor.public_key.clone(),
		sequence: floor.sequence, index_sha256: floor.index_sha256.clone() }
	pointer := unsafe { &owned }
	unsafe { records.push_many(pointer, 1) }
}

// An explicitly revoked/replaced key may fail newer curve admission rules.
// Its cache can be superseded only when retained history already pins that
// exact identity, sequence and text. Never infer a floor from ineligible trust,
// and never apply this exception to a valid key with a bad signature.
fn recorded_retired_snapshot(config Config, history TrustHistory, snapshot Snapshot) bool {
	repository := snapshot.repository
	if config.repositories.any(it.id == repository.id && it.public_key == repository.public_key) {
		return false
	}
	for floor in history.repositories {
		if floor.id != repository.id || floor.public_key != repository.public_key { continue }
		digest := index_digest(snapshot.text)
		defer { unsafe { digest.free() } }
		if floor.index_sha256 != digest { return false }
		if key := admitted_publisher_key(repository.public_key) {
			unsafe { key.free() }
			return false
		} else {
			unsafe { err.free() }
		}
		// History binds these bytes; decoding only checks their complete shape
		// and sequence. It does not authenticate or admit this publisher again.
		index := decode_signed_index(repository.id, snapshot.text, 0) or {
			message := err.msg()
			unsafe { message.free(); err.free() }
			return false
		}
		defer { close_decoded_index(index) }
		return index.sequence == floor.sequence
	}
	return false
}

// Migrate authenticated legacy snapshots, including expired/revoked ones. A
// history written before a torn catalog publication may already be newer.
// Recorded retired snapshots add no trust and leave every existing floor intact.
fn history_with_snapshots(config Config, directory string, snapshots []Snapshot) !TrustHistory {
	mut history := read_history(directory)!
	mut accepted := false
	defer { if !accepted { close_decoded_history(history) } }
	for snapshot in snapshots {
		if recorded_retired_snapshot(config, history, snapshot) { continue }
		index := verify_index(snapshot.repository, snapshot.text, snapshot.signature, 0)!
		defer { close_decoded_index(index) }
		if history.repositories.any(it.id == snapshot.repository.id && it.public_key == snapshot.repository.public_key
			&& it.sequence > index.sequence) {
			continue
		}
		next := remember_index(history, snapshot.repository, index, snapshot.text)!
		close_decoded_history(history)
		history = next
	}
	accepted = true
	return history
}

fn save_history(directory string, history TrustHistory) ! {
	path := directory + '/trust-history.json'
	defer { unsafe { path.free() } }
	write_administration_document(path, history, 'repository trust history exceeds metadata limit')!
}
