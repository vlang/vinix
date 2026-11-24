// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import strings
import time

pub struct ReleaseIndexSource {
pub:
	directory  string
	id         string
	public_key string
}

// Verify complete signed releases and save their exact authenticated index
// digests in the format consumed by image staging.
pub fn write_release_index_pins(destination string, sources []ReleaseIndexSource) ! {
	if sources.len == 0 || sources.len > max_image_repository_indexes {
		return error('release index pins require 1 to 4096 signed releases')
	}
	mut sorted := sources.clone()
	defer { unsafe { sorted.free() } }
	sorted.sort(a.id < b.id)
	for i, source in sorted {
		if !identifier(source.id) { return error('invalid release repository ID') }
		if i > 0 && source.id == sorted[i - 1].id { return error('duplicate release repository ID: ${source.id}') }
	}

	if destination == '' || !printable(destination, 4096) || destination.contains('\\') {
		return error('release index pins require a valid new-file path')
	}
	name := os.file_name(destination)
	parent := os.dir(destination)
	defer { unsafe { name.free(); parent.free() } }
	if name in ['', '.', '..']! { return error('release index pins require a new file name') }
	physical := publisher_real_path(parent)!
	defer { unsafe { physical.free() } }
	check_export_parent(physical, 'release index pins')!
	base := physical.trim_right('/')
	defer { unsafe { base.free() } }
	path := base + '/' + name
	defer { unsafe { path.free() } }
	if publisher_entry_exists(path) { return error('release index pins destination already exists; choose a new file name') }

	mut pins := strings.new_builder(sorted.len * 194)
	defer { unsafe { pins.free() } }
	mut first_expiry := i64(0)
	for source in sorted {
		mut release := check_signed_release(source.directory, source.id, source.public_key, '', physical)!
		defer { release.close() }
		pins.write_string(release.repository)
		pins.write_u8(` `)
		pins.write_string(release.index_sha256)
		pins.write_u8(`\n`)
		if first_expiry == 0 || release.expires < first_expiry { first_expiry = release.expires }
	}
	if first_expiry <= time.now().unix() { return error('signed release expired while preparing index pins') }
	text := pins.str()
	defer { unsafe { text.free() } }
	atomic_write_new(path, text)!
}
