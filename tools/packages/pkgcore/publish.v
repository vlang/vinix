// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.signing as ed25519
import encoding.hex
import json2
import os
import time

fn source_files(directory string, prefix string, mut files []Payload, repository string) ! {
	mut names := os.ls(directory)!
	names.sort()
	for name in names {
		path := directory + '/' + name
		relative := if prefix == '' { name } else { prefix + '/' + name }
		if !relative_path(relative) || os.is_link(path) {
			return error('package source contains an unsafe path or symlink: ${path}')
		}
		if os.is_dir(path) {
			source_files(path, relative, mut files, repository)!
			continue
		}
		if !os.is_file(path) { return error('package source contains a special file: ${path}') }
		if files.len >= max_files { return error('package source exceeds file limit') }
		size := os.file_size(path)
		if size > u64(4) * 1024 * 1024 * 1024 {
			return error('package source file is too large: ${path}')
		}
		digest := hash_file(path)!
		payload := Payload{ path: relative, bytes: size, sha256: digest, executable: os.is_executable(path) }
		target := repository + '/objects/' + digest
		if !verified_file(target, payload) {
			copy_file(path, target + '.new', 0, size)!
			if !verified_file(target + '.new', payload) {
				return error('package source changed while packing: ${path}')
			}
			os.rename(target + '.new', target)!
		}
		files << payload
	}
}

pub fn pack(manifest string, source string, repository string) !Package {
	if os.is_link(source) || !os.is_dir(source) {
		return error('package source must be a directory')
	}
	template := json2.decode[Package](read_metadata(manifest)!)!
	os.mkdir_all(repository + '/objects')!
	mut files := []Payload{}
	source_files(source, '', mut files, repository)!
	p := Package{ ...template, files: files }
	p.validate()!
	os.mkdir_all(repository + '/manifests')!
	atomic_write(repository + '/manifests/${p.id}-${p.architecture}-${p.version}.json', json2.encode(p) + '\n')!
	sync_directory(repository + '/objects')!
	return p
}

pub fn keygen(path string) !string {
	if os.exists(path) || os.is_link(path) { return error('signing seed file already exists') }
	public_key, private_key := ed25519.generate_key()!
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot exclusively create signing seed') }
	defer { C.close(fd) }
	text := private_key.seed().hex() + '\n'
	if C.write(fd, text.str, usize(text.len)) != text.len || C.fsync(fd) != 0 {
		return error('cannot write/flush signing seed')
	}
	return public_key.hex()
}

fn publication(repository string, id string, seed_path string, sequence u64, expires i64) !(Index, string, string, string) {
	if !identifier(id) || sequence == 0 || expires <= time.now().unix() {
		return error('publishing requires a repository ID, positive sequence and future expiry')
	}
	seed := hex.decode(read_metadata(seed_path)!.trim_space())!
	if seed.len != 32 { return error('signing seed must contain exactly 32 bytes of hex') }
	private_key := ed25519.new_key_from_seed(seed)
	mut packages := []Package{}
	for name in os.ls(repository + '/manifests')! {
		if !name.ends_with('.json') { continue }
		p := json2.decode[Package](read_metadata(repository + '/manifests/' + name)!)!
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
