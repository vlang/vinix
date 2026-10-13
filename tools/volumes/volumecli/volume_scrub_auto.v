// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Called only after authentication, secret erasure and operation-specific
// geometry/reference validation.
// Discovery returns its existing read-only pin; no path is reopened afterward.
@[direct_array_access]
fn ciphertext_scrub_parent(device &char, disk &DiskKey, mut status Status) i32 {
	if device != unsafe { nil } { return C.open(device, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK) }
	mut name := [256]char{}
	return discover_disk_key(disk, c'/dev', false, &name[0], mut status)
}

// Automatic scans retain the physical ID/mode selected by discovery. The
// first recheck must not replace that baseline before comparing it.
fn check_ciphertext_scrub_parent(fd i32, device &char, mut work VolumeSealFiles) bool {
	if device == unsafe { nil } { return volume_seal_recheck(fd, mut work) }
	return probe_disk(fd, mut work.after, mut work.status) && key_matches(&work.disk, &work.after)
}
