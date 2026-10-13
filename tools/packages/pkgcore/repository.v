// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.signing as ed25519
import encoding.hex
import json2
import os
import time
import tools.packages.pkgprotocol

pub struct Snapshot {
pub:
	repository Repository
	text       string
	signature  string
}

pub fn verify_index(repository Repository, text string, signature string, now i64) !Index {
	if text.len > max_metadata { return error('${repository.id}: repository index too large') }
	key := hex.decode(repository.public_key)!
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
	mut packages := []Installed{}
	mut owners := map[string]string{}
	for repository in config.repositories {
		matches := snapshots.filter(it.repository == repository)
		if matches.len != 1 {
			return error('${repository.id}: no authenticated cached index; run update')
		}
		index := verify_index(repository, matches[0].text, matches[0].signature, now)!
		for p in index.packages {
			if p.id in owners && owners[p.id] != repository.id {
				return error('ambiguous package ${p.id} published by multiple repositories')
			}
			owners[p.id] = repository.id
			packages << Installed{ package: p, repository: repository.id, public_key: repository.public_key, sequence: index.sequence }
		}
	}
	return Catalog{ packages: packages }
}

pub fn read_snapshots(directory string) ![]Snapshot {
	path := directory + '/catalog.json'
	if !os.exists(path) { return []Snapshot{} }
	return json2.decode[[]Snapshot](read_metadata(path)!)!
}

pub fn load_catalog(config Config, directory string) !Catalog {
	config.validate()!
	snapshots := read_snapshots(directory)!
	history := read_history(directory)!
	for snapshot in snapshots {
		if !config.repositories.any(it == snapshot.repository) { continue }
		index := verify_index(snapshot.repository, snapshot.text, snapshot.signature, time.now().unix())!
		check_floor(history, snapshot.repository, index, index_digest(snapshot.text))!
	}
	return snapshots_catalog(config, snapshots, time.now().unix())
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
	mut history := history_with_snapshots(directory, previous)!
	mut snapshots := []Snapshot{}
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
		signature := read_metadata(sig_path)!.trim_space()
		report(pkgprotocol.Progress{ phase: 'verify', repository: repository.id, path: 'index.json' })
		index := verify_index(repository, text, signature, time.now().unix())!
		history = remember_index(history, repository, index, text)!
		snapshots << Snapshot{ repository: repository, text: text, signature: signature }
	}
	catalog := snapshots_catalog(config, snapshots, time.now().unix())!
	encoded := json2.encode(snapshots)
	if encoded.len > max_metadata {
		return error('combined repository metadata exceeds cache limit')
	}
	// Record authenticated sequence/digest floors before exposing the new cache.
	// Revocation and empty refreshes never discard identities from this history.
	save_history(directory, history)!
	atomic_write(directory + '/catalog.json', encoded)!
	report(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
	return catalog
}
