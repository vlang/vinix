// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256

// Installed permissions are canonical, independent of the object's cache mode
// and the administrator's umask. Verification never changes an existing inode.
fn verified_installed_file(path string, payload Payload) bool {
	return verified_file_with(path, payload, HashReadOptions{ mode: if payload.executable { 0o755 } else { 0o644 } })
}

fn verified_registration(generation string, p Package) bool {
	if p.kind in ['data', 'runtime'] { return true }
	text := desktop_entry(p)
	bytes := text.bytes()
	mut hash := sha256.new()
	hash.write(bytes) or { panic(err) }
	mut sum := []u8{len: sha256.size}
	hash.checksum_into(mut sum)
	digest := sum.hex()
	path := '${generation}/share/applications/vinix-${p.id}.desktop'
	defer { unsafe { path.free(); digest.free(); sum.free(); hash.free(); free(hash); bytes.free(); text.free() } }
	return verified_file_with(path, Payload{ bytes: u64(text.len), sha256: digest }, HashReadOptions{ mode: 0o644 })
}
