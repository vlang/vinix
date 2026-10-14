// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.signing as ed25519
import json2
import os
import time

pub fn pack(manifest string, source string, repository string) !Package {
	return pack_with(manifest, source, repository, PackSourceOptions{})
}

fn pack_with(manifest string, source string, repository string, options PackSourceOptions) !Package {
	root := capture_prepared_root(source, 'package source')!
	defer { C.close(root) }
	options.checkpoint('root', source)!
	text := read_metadata(manifest)!
	defer { unsafe { text.free() } }
	template := decode_manifest(text, false)!
	os.mkdir_all(repository + '/objects')!
	mut input := PackSource{ repository: repository, options: options }
	input.walk(root, '', 0)!
	p := Package{ ...template, files: input.files }
	p.validate()!
	os.mkdir_all(repository + '/manifests')!
	atomic_write(repository + '/manifests/${p.id}-${p.architecture}-${p.version}.json', json2.encode(p) + '\n')!
	sync_directory(repository + '/objects')!
	return p
}

fn publication(repository string, id string, seed_path string, sequence u64, expires i64) !(Index, string, string, string) {
	seed := read_signing_seed(seed_path, SigningSeedOptions{})!
	defer { seed.close() }
	return publication_with_seed(repository, id, seed, sequence, expires)
}

fn publication_with_seed(repository string, id string, seed SigningSeed, sequence u64, expires i64) !(Index, string, string, string) {
	if !identifier(id) || sequence == 0 || expires <= time.now().unix() {
		return error('publishing requires a repository ID, positive sequence and future expiry')
	}
	mut private_key := ed25519.new_key_from_seed(seed.bytes)
	defer { retire_signing_bytes(mut private_key) }
	mut packages := []Package{}
	for name in os.ls(repository + '/manifests')! {
		if !name.ends_with('.json') { continue }
		manifest := read_metadata(repository + '/manifests/' + name)!
		p := decode_manifest(manifest, true) or { unsafe { manifest.free() }; return err }
		unsafe { manifest.free() }
		p.validate()!
		for file in p.files {
			if !verified_file(repository + '/objects/' + file.sha256, file) {
				return error('publisher payload verification failed: ${p.id}/${file.path}')
			}
		}
		packages << p
	}
	index := Index{ repository: id, sequence: sequence, expires: expires, packages: packages }
	text := canonical_index(index)!
	sig := ed25519.sign(private_key, text.bytes())!.hex()
	// Run the consumer validation before emitting a signed publication.
	public_key := private_key.public_key().hex()
	verified := verify_index(Repository{ id: id, public_key: public_key }, text, sig, time.now().unix())!
	return verified, text, sig, public_key
}

pub fn publish(repository string, id string, seed_path string, sequence u64, expires i64) ! {
	_, text, sig, _ := publication(repository, id, seed_path, sequence, expires)!
	// Publish in a new repository directory, then switch the server's release
	// directory. Clients reject a torn index/signature pair without changing state.
	atomic_write(repository + '/index.sig', sig + '\n')!
	atomic_write(repository + '/index.json', text)!
}
