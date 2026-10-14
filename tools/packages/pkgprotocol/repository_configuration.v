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
	if configuration.scope != 'configuration' { return error('unsupported repository configuration scope') }
	validate_configured_repositories(configuration.format, configuration.architecture, configuration.repositories)!
}

pub fn (mut configuration RepositoryConfiguration) close() {
	unsafe {
		configuration.scope.free()
		configuration.architecture.free()
		for repository in configuration.repositories { close_repository(repository) }
		(&array(&configuration.repositories)).free()
	}
	configuration = RepositoryConfiguration{}
}

const repository_configuration_keys = ['format', 'scope', 'architecture', 'repositories']

fn (mut r MetadataReader) parse_repository_configuration() !RepositoryConfiguration {
	r.expect(`{`)!
	mut value := RepositoryConfiguration{}
	mut accepted := false
	defer { if !accepted { value.close() } }
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
	value.validate()!
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
