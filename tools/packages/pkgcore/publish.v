// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.signing as ed25519
import time

// Only independently owned pack/pack_root replies. Package records inside a
// state, catalog or plan borrow their owner's storage and must not close it.
// Published manifests and payload objects are independent of reply metadata.
pub fn (mut p Package) close() {
	close_decoded_package(p)
	p = Package{}
}

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
	mut input := PackSource{ options: options }
	mut transferred := false
	defer {
		if !transferred { close_decoded_package(template); input.close() }
	}
	publisher_outside_source(root, repository)!
	workspace := publisher_workspace(repository, true)!
	defer { unsafe { workspace.free() } }
	guard := publisher_lock(workspace)!
	defer { guard.release() }
	options.checkpoint('locked', workspace)!
	objects := workspace + '/objects'
	manifests := workspace + '/manifests'
	defer { unsafe { objects.free(); manifests.free() } }
	owned_directory(objects, 0o755)!
	input = PackSource{ repository: workspace, options: options }
	input.walk(root, '', 0)!
	p := Package{ ...template, files: input.files }
	p.validate()!
	owned_directory(manifests, 0o755)!
	path := '${manifests}/${p.id}-${p.architecture}-${p.version}.json'
	encoded := publisher_json(p)
	defer { unsafe { path.free(); encoded.free() } }
	atomic_write(path, encoded)!
	sync_directory(objects)!
	// Supplied template inventories are replaced by the captured walk. Retire
	// them separately before moving declarations and the new inventory to p.
	close_pack_files(template.files)
	transferred = true
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
	for name in ['objects', 'manifests']! {
		path := repository + '/' + name
		defer { unsafe { path.free() } }
		directory := publisher_workspace(path, false)!
		unsafe { directory.free() }
	}
	mut private_key := ed25519.new_key_from_seed(seed.bytes)
	defer { retire_signing_bytes(mut private_key) }
	mut packages := []Package{}
	unsafe { packages.flags |= .noslices }
	defer {
		for p in packages { close_decoded_package(p) }
		unsafe { (&array(&packages)).free() }
	}
	manifests := repository + '/manifests'
	objects := repository + '/objects'
	defer { unsafe { manifests.free(); objects.free() } }
	names := publisher_flush_names(manifests)!
	defer { unsafe { names.free() } }
	for name in names {
		if !name.ends_with('.json') { continue }
		path := manifests + '/' + name
		defer { unsafe { path.free() } }
		manifest := read_metadata(path)!
		p := decode_manifest(manifest, true) or { unsafe { manifest.free() }; return err }
		unsafe { manifest.free() }
		// Transfer decoded fields before any validation or payload refusal.
		pointer := unsafe { &p }
		unsafe { packages.push_many(pointer, 1) }
		p.validate()!
		for file in p.files {
			object := objects + '/' + file.sha256
			defer { unsafe { object.free() } }
			if !verified_file(object, file) {
				return error('publisher payload verification failed: ${p.id}/${file.path}')
			}
		}
	}
	index := Index{ repository: id, sequence: sequence, expires: expires, packages: packages }
	text := canonical_index(index)!
	mut accepted := false
	mut sig := ''
	mut public_key := ''
	defer { if !accepted { unsafe { text.free(); sig.free(); public_key.free() } } }
	bytes := text.bytes()
	defer { unsafe { bytes.free() } }
	signed := ed25519.sign(private_key, bytes)!
	defer { unsafe { signed.free() } }
	sig = signed.hex()
	// Run the consumer validation before emitting a signed publication.
	key := private_key.public_key()
	defer { unsafe { key.free() } }
	public_key = key.hex()
	verified := verify_index(Repository{ id: id, public_key: public_key }, text, sig, time.now().unix())!
	accepted = true
	return verified, text, sig, public_key
}

pub fn publish(repository string, id string, seed_path string, sequence u64, expires i64) ! {
	workspace := publisher_workspace(repository, false)!
	defer { unsafe { workspace.free() } }
	guard := publisher_lock(workspace)!
	defer { guard.release() }
	index, text, sig, key := publication(workspace, id, seed_path, sequence, expires)!
	defer { close_decoded_index(index); unsafe { text.free(); sig.free(); key.free() } }
	// Publish in a new repository directory, then switch the server's release
	// directory. Clients reject a torn index/signature pair without changing state.
	signature_path := workspace + '/index.sig'; index_path := workspace + '/index.json'; signed_text := sig + '\n'
	defer { unsafe { signature_path.free(); index_path.free(); signed_text.free() } }
	atomic_write(signature_path, signed_text)!
	atomic_write(index_path, text)!
}
