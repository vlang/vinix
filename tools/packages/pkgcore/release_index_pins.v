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
	origin     string // Optional HTTPS origin whose signed bytes must match.
}

// Verify complete signed releases and save their exact authenticated index
// digests in the format consumed by image staging. A supplied origin must
// match its local export before the file can be published.
pub fn write_release_index_pins(destination string, sources []ReleaseIndexSource) ! {
	if sources.len == 0 || sources.len > max_image_repository_indexes {
		return error('release index pins require 1 to 4096 signed releases')
	}
	mut sorted := sources.clone()
	defer { unsafe { sorted.free() } }
	sorted.sort(a.id < b.id)
	mut bytes := 0
	for i, source in sorted {
		if !identifier(source.id) { return error('invalid release repository ID') }
		if i > 0 && source.id == sorted[i - 1].id { return error('duplicate release repository ID: ${source.id}') }
		bytes += source.id.len + 1 + 64 + 1 // ID, space, SHA-256 and newline
		if source.origin != '' {
			if !valid_release_origin(source.origin) { return error('release origin requires a valid HTTPS repository URL') }
			bytes += 1 + source.origin.len
		}
	}
	if bytes > max_metadata { return error('release index pins exceed the image metadata limit') }

	if destination == '' || !printable(destination, 4096) || destination.contains('\\') {
		return error('release index pins require a valid new-file path')
	}
	name := os.file_name(destination)
	parent := os.dir(destination)
	defer { unsafe { name.free(); parent.free() } }
	if name in ['', '.', '..']! { return error('release index pins require a new file name') }
	physical := publisher_real_path(parent)!
	defer { unsafe { physical.free() } }
	directory := capture_prepared_root(physical, 'release index pins parent')!
	defer { C.close(directory) }
	check_export_parent(physical, 'release index pins')!
	base := physical.trim_right('/')
	defer { unsafe { base.free() } }
	path := base + '/' + name
	defer { unsafe { path.free() } }
	check_new_atomic_destination(directory, name)!

	mut pins := strings.new_builder(bytes)
	defer { unsafe { pins.free() } }
	mut first_expiry := i64(0)
	for source in sorted {
		mut release := check_signed_release(source.directory, source.id, source.public_key,
			SignedReleaseCheck{ origin: source.origin, pin_parent_fd: directory })!
		defer { release.close() }
		pins.write_string(release.repository)
		pins.write_u8(` `)
		pins.write_string(release.index_sha256)
		if source.origin != '' {
			pins.write_u8(` `)
			pins.write_string(source.origin)
		}
		pins.write_u8(`\n`)
		if first_expiry == 0 || release.expires < first_expiry { first_expiry = release.expires }
	}
	if first_expiry <= time.now().unix() { return error('signed release expired while preparing index pins') }
	text := pins.str()
	defer { unsafe { text.free() } }
	atomic_write_with(path, text, AtomicWriteOptions{ exclusive: true, parent_fd: directory })!
}
