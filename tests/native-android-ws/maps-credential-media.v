// SPDX-License-Identifier: GPL-2.0-or-later
// Pin the private pre-launch boot media without making a second image copy.
module main

import os
import crypto.sha256
import json2
import time

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn main() {
	$if prod {
		panic('build media verifier without -prod')
	}
	if os.args.len < 2 { panic('usage: maps-credential-media hash [253|254|255] | publish EXTERNAL-DIR [253|254|255]') }
	experiment := if os.args[1] == 'hash' && os.args.len == 3 {
		os.args[2]
	} else if os.args[1] == 'publish' && os.args.len == 4 {
		os.args[3]
	} else { '253' }
	if experiment !in ['253', '254', '255'] { panic('unsupported media experiment') }
	base := 'build/android-maps/maps' + experiment
	if os.args[1] == 'hash' && os.args.len in [2, 3] {
		mut hashes := map[string]string{}
		for name in ['boot.img', 'efivars.fd'] {
			path := base + '/vm/' + name
			before := os.stat(path)!
			hashes[path] = digest(path)!
			after := os.stat(path)!
			if before.size != after.size || before.mtime != after.mtime {
				panic('media changed while hashing: ' + path)
			}
		}
		os.write_file(base + '/prelaunch-media-sha256.json', json2.encode(hashes,
			prettify: true
		) + '\n')!
		os.write_file(base + '/prelaunch-media-time.txt', time.utc().str() + ' UTC\nQEMU not yet launched; media SHA256 streamed without copying the 4GiB boot image.\n')!
		println('MAPS${experiment} PRELAUNCH-MEDIA-HASHED')
		return
	}
	if os.args.len !in [3, 4] || os.args[1] != 'publish' {
		panic('usage: maps-credential-media hash [253|254|255] | publish EXTERNAL-DIR [253|254|255]')
	}
	root := os.args[2]
	mut hashes := json2.decode[map[string]string](os.read_file(root + '/frozen-inputs.json')!)!
	for path in ['tests/native-android-ws/maps-credential-media.v',
		'build/android-maps/maps-credential-media',
		base + '/prelaunch-media-sha256.json', base + '/prelaunch-media-time.txt'] {
		dest := root + '/inputs/' + path
		os.mkdir_all(os.dir(dest))!
		original := digest(path)!
		result := os.exec(['cp', '-c', path, dest])
		if result.exit_code != 0 || digest(dest)! != original || digest(path)! != original {
			panic('input freeze failed: ' + path)
		}
		hashes[path] = original
	}
	os.write_file(root + '/frozen-inputs.json', json2.encode(hashes, prettify: true) + '\n')!
	println('MAPS${experiment} COMPLETE-INPUT-PIN ' + root + ' manifest_sha256=' + digest(root + '/frozen-inputs.json')!)
}
