// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os
import tools.packages.pkgcore

fn valid_asset_name(name string) bool {
	if name == '' || name[0] in [u8(`.`), `-`]! { return false }
	if name in ['SHA256SUMS', 'RELEASE_NOTES.md']! { return false }
	for byte in name {
		if !byte.is_alnum() && byte !in [u8(`.`), `-`, `_`]! { return false }
	}
	return true
}

fn read_manifest(path string) !map[string]string {
	text := pkgcore.read_metadata(path)!
	mut entries := map[string]string{}
	if text == '' { return entries }
	if !text.ends_with('\n') { return error('invalid release checksum manifest: ' + path) }
	for line in text[..text.len - 1].split('\n') {
		if line.len <= 66 || line[64..66] != '  ' || !pkgcore.digest_valid(line[..64]) {
			return error('invalid release checksum manifest: ' + path)
		}
		name := line[66..]
		if !valid_asset_name(name) || name in entries {
			return error('invalid or repeated release asset name: ' + name)
		}
		entries[name] = line[..64]
	}
	return entries
}

fn record_assets(directory string, pinned_path string, names []string) ! {
	pinned := read_manifest(pinned_path)!
	mut entries := map[string]string{}
	for name in names {
		if !valid_asset_name(name) || name in entries {
			return error('invalid or repeated release asset name: ' + name)
		}
		// ISO package verification has already captured these exact bytes.
		entries[name] = pinned[name] or { pkgcore.hash_file(os.join_path(directory, name))! }
	}
	for name, _ in pinned {
		if name !in entries { return error('verified package asset is missing from the release: ' + name) }
	}
	for name in names {
		if !name.ends_with('.sha256') { continue }
		payload := name[..name.len - '.sha256'.len]
		digest := entries[payload] or { return error('release checksum has no matching asset: ' + name) }
		text := pkgcore.read_metadata(os.join_path(directory, name))!
		if text != '${digest}  ${payload}\n' || sha256.hexhash(text) != entries[name] {
			return error('release bundle checksum differs from its payload: ' + name)
		}
	}
	for name in names { println('${entries[name]}  ${name}') }
}

fn check_assets(directory string, manifest string) ! {
	entries := read_manifest(manifest)!
	if entries.len == 0 { return error('release checksum manifest is empty') }
	for name, digest in entries {
		if pkgcore.hash_file(os.join_path(directory, name))! != digest {
			return error('release asset changed after verification: ' + name)
		}
	}
}

fn copy_asset(directory string, destination string, name string) !string {
	path := os.join_path(destination, name)
	pkgcore.copy_file(os.join_path(directory, name), path, 0, ~u64(0))!
	os.chmod(path, 0o400)!
	return path
}

fn capture_assets(directory string, destination string, names []string) ! {
	os.mkdir(destination, mode: 0o700)!
	mut seen := map[string]bool{}
	for name in names {
		if !valid_asset_name(name) || name in seen {
			return error('invalid or repeated release asset name: ' + name)
		}
		seen[name] = true
		copy_asset(directory, destination, name)!
	}
}

fn stage_assets(directory string, manifest string, destination string) ! {
	entries := read_manifest(manifest)!
	if entries.len == 0 { return error('release checksum manifest is empty') }
	os.mkdir(destination, mode: 0o700)!
	for name, digest in entries {
		path := copy_asset(directory, destination, name)!
		if pkgcore.hash_file(path)! != digest {
			return error('release asset changed after verification: ' + name)
		}
	}
}

fn run() ! {
	if os.args.len >= 5 && os.args[1] == 'record' {
		return record_assets(os.args[2], os.args[3], os.args[4..])
	}
	if os.args.len >= 5 && os.args[1] == 'capture' {
		return capture_assets(os.args[2], os.args[3], os.args[4..])
	}
	if os.args.len == 4 && os.args[1] == 'check' {
		return check_assets(os.args[2], os.args[3])
	}
	if os.args.len == 5 && os.args[1] == 'stage' {
		return stage_assets(os.args[2], os.args[3], os.args[4])
	}
	return error('usage: release-assets record DIRECTORY PACKAGE-PINS ASSET... | capture DIRECTORY NEW_DESTINATION ASSET... | check DIRECTORY MANIFEST | stage DIRECTORY MANIFEST NEW_DESTINATION')
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
