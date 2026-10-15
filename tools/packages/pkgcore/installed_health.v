// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Installed permissions are canonical, independent of the object's cache mode
// and the administrator's umask. Verification never changes an existing inode.
fn verified_installed_file(path string, payload Payload) bool {
	return verified_file_with(path, payload, HashReadOptions{ mode: if payload.executable { 0o755 } else { 0o644 } })
}

fn verified_registration(generation string, p Package) bool {
	return verified_registration_with(generation, p, RegistrationOptions{})
}
