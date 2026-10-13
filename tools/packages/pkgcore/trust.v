// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os

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
	if !os.exists(path) && !os.is_link(path) { return TrustHistory{} }
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	return decode_history(text, false) or { return error('invalid repository trust history: ${err}') }
}

fn index_digest(text string) string {
	bytes := text.bytes()
	digest := sha256.sum(bytes).hex()
	unsafe { bytes.free() }
	return digest
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
	check_floor(history, repository, index, digest)!
	mut records := history.repositories.filter(it.id != repository.id || it.public_key != repository.public_key)
	records << RepositoryFloor{
		id:           repository.id
		public_key:   repository.public_key
		sequence:     index.sequence
		index_sha256: digest
	}
	if records.len > 4096 {
		return error('repository trust history exceeds its supported identity limit')
	}
	records.sort_with_compare(floor_order)
	return TrustHistory{ repositories: records }
}

// Migrate authenticated legacy snapshots, including expired/revoked ones. A
// history written before a torn catalog publication may already be newer.
fn history_with_snapshots(directory string, snapshots []Snapshot) !TrustHistory {
	mut history := read_history(directory)!
	for snapshot in snapshots {
		index := verify_index(snapshot.repository, snapshot.text, snapshot.signature, 0)!
		if history.repositories.any(it.id == snapshot.repository.id && it.public_key == snapshot.repository.public_key
			&& it.sequence > index.sequence) {
			continue
		}
		history = remember_index(history, snapshot.repository, index, snapshot.text)!
	}
	return history
}

fn save_history(directory string, history TrustHistory) ! {
	text := json2.encode(history) + '\n'
	if text.len > max_metadata { return error('repository trust history exceeds metadata limit') }
	write_administration_metadata(directory + '/trust-history.json', text)!
}
