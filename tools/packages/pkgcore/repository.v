// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.signing as ed25519
import encoding.hex
import os
import time
import tools.packages.pkgprotocol

pub struct Snapshot {
pub:
	repository Repository
	text       string
	signature  string
}

// Keep syntax-only configuration/history readers compatible with revocation of
// old keys. New trust and every authenticated index must pass curve admission.
fn admitted_publisher_key(encoded string) ![]u8 {
	if encoded.len != 64 { return error('invalid repository publisher key: expected 32 lowercase hex bytes') }
	// Decode directly into the owned key. The pinned hex decoder and bytes().all
	// validation keep temporary byte arrays under -gc none -manualfree.
	mut key := []u8{len: 32}
	for i, byte in encoded {
		digit := if byte >= `0` && byte <= `9` { byte - `0` } else if byte >= `a` && byte <= `f` { byte - `a` + 10 } else {
			unsafe { key.free() }
			return error('invalid repository publisher key: expected 32 lowercase hex bytes')
		}
		key[i / 2] = (key[i / 2] << 4) | digit
	}
	if !ed25519.publisher_key_valid(ed25519.PublicKey(key)) {
		unsafe { key.free() }
		return error('invalid repository publisher key: expected a canonical non-identity Ed25519 point in the prime-order subgroup')
	}
	return key
}

fn require_publisher_keys(packages []Installed) ! {
	mut checked := map[string]bool{}
	defer { unsafe { checked.free() } }
	for installed in packages {
		if installed.public_key in checked { continue }
		key := admitted_publisher_key(installed.public_key)!
		unsafe { key.free() }
		checked[installed.public_key] = true
	}
}

pub fn verify_index(repository Repository, text string, signature string, now i64) !Index {
	if text.len > max_metadata { return error('${repository.id}: repository index too large') }
	key := admitted_publisher_key(repository.public_key)!
	defer { unsafe { key.free() } }
	trimmed := signature.trim_space()
	defer { unsafe { trimmed.free() } }
	sig := hex.decode(trimmed)!
	defer { unsafe { sig.free() } }
	bytes := text.bytes()
	defer { unsafe { bytes.free() } }
	if key.len != 32 || sig.len != 64 || !ed25519.verify(ed25519.PublicKey(key), bytes, sig)! {
		return error('${repository.id}: repository signature verification failed; check administrator key enrollment')
	}
	return decode_signed_index(repository.id, text, now)
}

pub fn snapshots_catalog(config Config, snapshots []Snapshot, now i64) !Catalog {
	return catalog_from_snapshots(config, snapshots, TrustHistory{}, now)
}

// Returned manifests own their decoded fields; publisher identities continue
// to borrow configuration. No returned field borrows snapshot/history scratch.
fn catalog_from_snapshots(config Config, snapshots []Snapshot, history TrustHistory, now i64) !Catalog {
	mut packages := []Installed{}
	unsafe { packages.flags |= .noslices }
	mut owners := map[string]string{}
	mut accepted := false
	defer {
		unsafe { owners.free() }
		if !accepted { close_authenticated_catalog(Catalog{ packages: packages }) }
	}
	for repository in config.repositories {
		mut position := -1
		mut count := 0
		for index, snapshot in snapshots {
			if snapshot.repository == repository { position = index; count++ }
		}
		if count != 1 {
			return error('${repository.id}: no authenticated cached index; run update')
		}
		append_authenticated_index(repository, snapshots[position], history, now, mut packages, mut owners)!
	}
	accepted = true
	return Catalog{ packages: packages }
}

fn append_authenticated_index(repository Repository, snapshot Snapshot, history TrustHistory, now i64,
	mut packages []Installed, mut owners map[string]string) ! {
	index := verify_index(repository, snapshot.text, snapshot.signature, now)!
	mut transferred := false
	defer {
		if transferred {
			// Only the envelope retires: manifests now belong to the catalog.
			unsafe { index.repository.free(); (&array(&index.packages)).free() }
		} else { close_decoded_index(index) }
	}
	if history.repositories.len > 0 {
		digest := index_digest(snapshot.text)
		defer { unsafe { digest.free() } }
		check_floor(history, repository, index, digest)!
	}
	// Admit the complete index before transferring any of its manifests. A
	// later repository failure retires every earlier transfer in the caller.
	for p in index.packages {
		if p.id in owners && owners[p.id] != repository.id {
			return error('ambiguous package ${p.id} published by multiple repositories')
		}
	}
	for p in index.packages {
		owners[p.id] = repository.id
		record := Installed{ package: p, repository: repository.id, public_key: repository.public_key, sequence: index.sequence }
		pointer := unsafe { &record }
		unsafe { packages.push_many(pointer, 1) }
	}
	transferred = true
}

// Independently decoded catalog manifests only; plans and synthetic catalogs
// can borrow package fields. Configured publisher strings are always borrowed.
fn close_authenticated_catalog(catalog Catalog) {
	for installed in catalog.packages { close_decoded_package(installed.package) }
	unsafe { (&array(&catalog.packages)).free() }
}

pub fn read_snapshots(directory string) ![]Snapshot {
	path := directory + '/catalog.json'
	defer { unsafe { path.free() } }
	if !os.exists(path) && !os.is_link(path) { return []Snapshot{} }
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	return decode_snapshots(text) or { return error('invalid cached repository metadata: ${err}') }
}

pub fn load_catalog(config Config, directory string) !Catalog {
	config.validate()!
	snapshots := read_snapshots(directory)!
	defer { close_decoded_snapshots(snapshots) }
	history := read_history(directory)!
	defer { close_decoded_history(history) }
	return catalog_from_snapshots(config, snapshots, history, time.now().unix())
}

pub fn refresh(config Config, directory string) !Catalog {
	config.validate()!
	guard := acquire(directory)!
	defer { guard.release() }
	return refresh_locked(config, directory)
}

fn refresh_locked(config Config, directory string) !Catalog {
	return refresh_progress(config, directory, no_progress)
}

fn refresh_progress(config Config, directory string, report fn (pkgprotocol.Progress)) !Catalog {
	previous := read_snapshots(directory)!
	defer { close_decoded_snapshots(previous) }
	mut history := history_with_snapshots(config, directory, previous)!
	mut snapshots := []Snapshot{}
	unsafe { snapshots.flags |= .noslices }
	defer {
		// These records own fetched text/signatures and borrow Config identities.
		unsafe {
			for snapshot in snapshots { snapshot.text.free(); snapshot.signature.free() }
			snapshots.free()
		}
	}
	mut encoding := new_snapshot_encoding()
	defer { unsafe { encoding.free() } }
	work := directory + '/refresh'
	if os.exists(work) { os.rmdir_all(work)! }
	owned_directory(work, 0o700)!
	defer { os.rmdir_all(work) or {} }
	for repository in config.repositories {
		println('Updating trusted repository ${repository.id}')
		index_path := work + '/index.json'
		sig_path := work + '/index.sig'
		fetch_progress(repository.url.trim_right('/') + '/index.json', index_path, max_metadata, false, config.policy.offline,
			pkgprotocol.Progress{ phase: 'metadata', repository: repository.id, path: 'index.json' }, report)!
		fetch_progress(repository.url.trim_right('/') + '/index.sig', sig_path, 256, false, config.policy.offline,
			pkgprotocol.Progress{ phase: 'metadata', repository: repository.id, path: 'index.sig' }, report)!
		text := read_metadata(index_path)!
		raw_signature := read_metadata(sig_path) or { unsafe { text.free() }; return err }
		signature := raw_signature.trim_space()
		unsafe { raw_signature.free() }
		snapshot := Snapshot{ repository: repository, text: text, signature: signature }
		pointer := unsafe { &snapshot }
		unsafe { snapshots.push_many(pointer, 1) }
		report(pkgprotocol.Progress{ phase: 'verify', repository: repository.id, path: 'index.json' })
		index := verify_index(repository, text, signature, time.now().unix())!
		defer { close_decoded_index(index) }
		history = remember_index(history, repository, index, text)!
		// Authenticate and check replay first. Refuse this prefix before fetching
		// another repository or constructing the independently decoded catalog.
		append_snapshot_metadata(snapshot, mut encoding)!
	}
	encoded := finish_snapshot_encoding(mut encoding)
	defer { unsafe { encoded.free() } }
	catalog := snapshots_catalog(config, snapshots, time.now().unix())!
	mut published := false
	defer { if !published { close_authenticated_catalog(catalog) } }
	// Record authenticated sequence/digest floors before exposing the new cache.
	// Revocation and empty refreshes never discard identities from this history.
	save_history(directory, history)!
	atomic_write(directory + '/catalog.json', encoded)!
	report(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
	published = true
	return catalog
}
