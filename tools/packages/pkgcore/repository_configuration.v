// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Configured identities remain available for reviewed revocation when cached
// indexes or replay history are damaged. This document makes no history claim.
pub struct RepositoryConfiguration {
pub:
	format       int = 1
	scope        string = 'configuration'
	architecture string
	repositories []Repository
}

fn read_repository_configuration(root string) !RepositoryConfiguration {
	config := load_config(root)!
	// Transfer the independently decoded architecture/repositories. The other
	// configuration fields are private scratch, never part of this observation.
	defer { close_owned_policy(config.policy); unsafe { config.launch_user.free() } }
	return RepositoryConfiguration{ architecture: config.architecture, repositories: config.repositories }
}

pub fn repository_configuration(root string) !RepositoryConfiguration {
	directory := state_directory(root)
	defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return read_repository_configuration(root)
	}
	return read_repository_configuration(root)
}

// Returned configuration observations own these fields; caller-built documents
// can borrow metadata and retain their caller's lifetime.
pub fn (mut document RepositoryConfiguration) close() {
	unsafe {
		document.scope.free(); document.architecture.free()
		for repository in document.repositories { repository.id.free(); repository.url.free(); repository.public_key.free() }
		(&array(&document.repositories)).free()
	}
	document = RepositoryConfiguration{}
}
