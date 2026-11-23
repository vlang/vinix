// SPDX-License-Identifier: GPL-2.0-or-later
module imageinputs

pub const configuration = 'VINIX_PACKAGE_IMAGE_CONFIG'
pub const repositories = 'VINIX_PACKAGE_IMAGE_REPOSITORIES'
pub const applications = 'VINIX_PACKAGE_IMAGE_APPLICATIONS'

// Callers supply the package architecture used by the stager and its cache.
pub fn environment_path(env map[string]string, variable string, architecture string) string {
	selected := env[variable + '_' + architecture.to_upper()] or { '' }
	return if selected != '' { selected } else { env[variable] or { '' } }
}
