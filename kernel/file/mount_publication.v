// SPDX-License-Identifier: GPL-2.0-or-later
module file

__global (
	mount_publication_allowed fn (&Handle) bool
	mount_description_released fn (voidptr)
)

// Installed by the VFS module initializer, before descriptors can be published.
pub fn on_mount_publication(f fn (&Handle) bool, released fn (voidptr)) {
	mount_publication_allowed = f
	mount_description_released = released
}

// The caller holds the destination's fds_lock until after slot publication.
// Unmount closes admission before trying that lock; it either observes the
// published descriptor or refuses on contention. Do not call this unlocked.
fn descriptor_mount_admitted(fd &FD) bool {
	return mount_publication_allowed == unsafe { nil }
		|| mount_publication_allowed(fd.handle)
}
