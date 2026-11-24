// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

pub struct RepositoryConfiguration {
pub:
	format       int
	scope        string
	architecture string
	repositories []Repository
}

pub fn (configuration &RepositoryConfiguration) validate() ! {
	validate_repository_configuration(configuration)!
}

fn validate_repository_configuration(configuration RepositoryConfiguration) ! {
	if configuration.scope != 'configuration' { return error('unsupported repository configuration scope') }
	validate_configured_repositories(configuration.format, configuration.architecture, configuration.repositories)!
}

fn close_repository_configuration(configuration RepositoryConfiguration) {
	unsafe {
		configuration.scope.free()
		configuration.architecture.free()
	}
	close_repositories(configuration.repositories)
}

pub fn (mut configuration RepositoryConfiguration) close() {
	close_repository_configuration(configuration)
	configuration = RepositoryConfiguration{}
}

const repository_configuration_keys = ['format', 'scope', 'architecture', 'repositories']

fn (mut r MetadataReader) parse_repository_configuration() !RepositoryConfiguration {
	r.expect(`{`)!
	mut value := RepositoryConfiguration{}
	mut accepted := false
	defer { if !accepted { close_repository_configuration(value) } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.member(repository_configuration_keys, seen)!
		seen |= u16(1) << member
		match member {
			0 { r.expect(`1`)!; value = RepositoryConfiguration{ ...value, format: 1 } }
			1 { value = RepositoryConfiguration{ ...value, scope: r.quoted(16)! } }
			2 { value = RepositoryConfiguration{ ...value, architecture: r.quoted(16)! } }
			3 { value = RepositoryConfiguration{ ...value, repositories: r.parse_repositories()! } }
			else {}
		}
	}
	if seen != 15 { return error('missing repository configuration field') }
	validate_repository_configuration(value)!
	accepted = true
	return value
}

pub fn decode_repository_configuration(text string) !RepositoryConfiguration {
	if text.len > 8 * 1024 * 1024 { return error('repository configuration exceeds reply limit') }
	mut r := &MetadataReader{ text: text }
	defer { unsafe { free(r) } }
	mut value := r.parse_repository_configuration()!
	r.spaces()
	if r.position != text.len { value.close(); return error('trailing repository configuration metadata') }
	return value
}
