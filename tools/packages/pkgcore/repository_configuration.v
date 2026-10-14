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
	return RepositoryConfiguration{ architecture: config.architecture, repositories: config.repositories }
}

pub fn repository_configuration(root string) !RepositoryConfiguration {
	directory := state_directory(root)
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return read_repository_configuration(root)
	}
	return read_repository_configuration(root)
}
