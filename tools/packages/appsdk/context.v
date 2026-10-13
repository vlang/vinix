// SPDX-License-Identifier: MIT
module appsdk

import os

pub const context_version = 1
const grants = ['audio', 'display', 'files', 'network', 'process']

// Fields are borrowed wire values. decode returns an independently owned Context.
pub struct Fields {
pub:
	sdk string
	id string
	version string
	architecture string
	kind string
	generation string
	repository string
	public_key string
	sequence string
	app_directory string
	data_directory string
	runtime_id string
	runtime_version string
	runtime_directory string
	permissions string
}

pub struct Context {
pub:
	sdk int = 1
	id string
	version string
	architecture string
	kind string
	generation u64
	repository string
	public_key string
	sequence u64
	app_directory string
	data_directory string
	runtime_id string
	runtime_version string
	runtime_directory string
	permissions []string
}

fn identifier(value string) bool {
	if value.len == 0 || value.len > 128 || value[0] < `a` || value[0] > `z` { return false }
	for byte in value { if !(byte >= `a` && byte <= `z`) && !(byte >= `0` && byte <= `9`) && byte != `.` && byte != `-` && byte != `_` { return false } }
	return true
}

fn version(value string) bool {
	if value.len < 5 || value.len > 29 { return false }
	mut start := 0
	mut components := 0
	for i in 0 .. value.len + 1 {
		if i < value.len && value[i] != `.` {
			if value[i] < `0` || value[i] > `9` { return false }
			continue
		}
		length := i - start
		if length == 0 || length > 9 || (length > 1 && value[start] == `0`) { return false }
		components++; start = i + 1
	}
	return components == 3
}

fn absolute_path(path string) bool {
	if path.len == 0 || path.len > 4096 || path[0] != `/` { return false }
	mut start := 1
	for i in 1 .. path.len + 1 {
		if i < path.len && path[i] != `/` {
			if path[i] < 32 || path[i] == 127 || path[i] == `\\` { return false }
			continue
		}
		length := i - start
		if length == 0 || (length == 1 && path[start] == `.`) || (length == 2 && path[start] == `.` && path[start + 1] == `.`) { return false }
		start = i + 1
	}
	return true
}

fn counter(value string) !u64 {
	if value.len == 0 || value.len > 20 || value[0] == `0` { return error('application context needs a canonical positive counter') }
	mut number := u64(0)
	for byte in value {
		if byte < `0` || byte > `9` || number > (~u64(0) - u64(byte - `0`)) / 10 { return error('application context counter is invalid or overflows') }
		number = number * 10 + u64(byte - `0`)
	}
	return number
}

pub fn (context &Context) validate() ! {
	if context.sdk != context_version || context.architecture !in ['aarch64', 'x86_64'] || context.kind !in ['native', 'linux', 'windows', 'apple'] {
		return error('unsupported application context SDK, architecture or kind')
	}
	if !identifier(context.id) || !identifier(context.repository) || !version(context.version) || !version(context.runtime_version)
		|| context.generation == 0 || context.sequence == 0 { return error('invalid application context identity, version or counters') }
	if context.public_key.len != 64 { return error('invalid application context publisher key') }
	for byte in context.public_key { if !(byte >= `0` && byte <= `9`) && !(byte >= `a` && byte <= `f`) { return error('invalid application context publisher key') } }
	if !absolute_path(context.app_directory) || !absolute_path(context.data_directory) || !absolute_path(context.runtime_directory)
		|| context.data_directory == context.app_directory || context.data_directory == context.runtime_directory { return error('invalid application context directories') }
	generation := context.generation.str()
	defer { unsafe { generation.free() } }
	app_suffix := '/generations/' + generation + '/apps/' + context.id
	defer { unsafe { app_suffix.free() } }
	if !context.app_directory.ends_with(app_suffix) { return error('application directory does not match the admitted generation and ID') }
	if context.runtime_id == '' {
		if context.runtime_directory != context.app_directory || context.runtime_version != context.version { return error('self-contained application runtime context must match the application') }
	} else {
		if !identifier(context.runtime_id) || context.runtime_id == context.id { return error('invalid application context runtime ID') }
		root_length := context.app_directory.len - context.id.len
		expected := unsafe { tos(context.app_directory.str, root_length) } + context.runtime_id
		defer { unsafe { expected.free() } }
		if context.runtime_directory != expected { return error('runtime directory must belong to the admitted generation') }
	}
	if context.permissions.len > grants.len { return error('application context has too many permissions') }
	for i, permission in context.permissions {
		if permission !in grants { return error('unknown application context permission') }
		for j in 0 .. i { if permission == context.permissions[j] { return error('duplicate application context permission') } }
	}
}

pub fn (context &Context) declares(permission string) bool { return permission in context.permissions }

pub fn free_values(mut values []string) {
	for value in values { unsafe { value.free() } }
	unsafe { (&array(&values)).free() }
	values = []string{}
}

pub fn (mut context Context) close() {
	unsafe {
		context.id.free(); context.version.free(); context.architecture.free(); context.kind.free()
		context.repository.free(); context.public_key.free(); context.app_directory.free(); context.data_directory.free()
		context.runtime_id.free(); context.runtime_version.free(); context.runtime_directory.free()
	}
	for value in context.permissions { unsafe { value.free() } }
	unsafe { (&array(&context.permissions)).free() }
	context = Context{}
}

pub fn decode(fields Fields) !Context {
	if fields.sdk != '1' || fields.permissions.len > 64 { return error('unsupported or oversized application context') }
	generation := counter(fields.generation)!
	sequence := counter(fields.sequence)!
	mut permissions := []string{cap: 5}
	unsafe { permissions.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { free_values(mut permissions) } }
	if fields.permissions != '' {
		mut start := 0
		for i in 0 .. fields.permissions.len + 1 {
			if i < fields.permissions.len && fields.permissions[i] != ` ` { continue }
			word := unsafe { tos(fields.permissions.str + start, i - start) }
			if word !in grants || word in permissions { return error('invalid or repeated application context permission') }
			permissions << word.clone(); start = i + 1
		}
	}
	candidate := Context{ id: fields.id, version: fields.version, architecture: fields.architecture, kind: fields.kind,
		generation: generation, repository: fields.repository, public_key: fields.public_key, sequence: sequence,
		app_directory: fields.app_directory, data_directory: fields.data_directory, runtime_id: fields.runtime_id,
		runtime_version: fields.runtime_version, runtime_directory: fields.runtime_directory, permissions: permissions }
	candidate.validate()!
	accepted = true
	return Context{ ...candidate, id: candidate.id.clone(), version: candidate.version.clone(), architecture: candidate.architecture.clone(),
		kind: candidate.kind.clone(), repository: candidate.repository.clone(), public_key: candidate.public_key.clone(),
		app_directory: candidate.app_directory.clone(), data_directory: candidate.data_directory.clone(), runtime_id: candidate.runtime_id.clone(),
		runtime_version: candidate.runtime_version.clone(), runtime_directory: candidate.runtime_directory.clone() }
}

// This reads the launch snapshot, without consulting a newer active generation.
pub fn load() !Context {
	fields := Fields{ sdk: os.getenv('VINIX_APP_SDK'), id: os.getenv('VINIX_APP_ID'), version: os.getenv('VINIX_APP_VERSION'),
		architecture: os.getenv('VINIX_APP_ARCHITECTURE'), kind: os.getenv('VINIX_APP_KIND'), generation: os.getenv('VINIX_APP_GENERATION'),
		repository: os.getenv('VINIX_APP_REPOSITORY'), public_key: os.getenv('VINIX_APP_PUBLIC_KEY'), sequence: os.getenv('VINIX_APP_SEQUENCE'),
		app_directory: os.getenv('VINIX_APP_DIR'), data_directory: os.getenv('VINIX_APP_DATA'), runtime_id: os.getenv('VINIX_APP_RUNTIME_ID'),
		runtime_version: os.getenv('VINIX_APP_RUNTIME_VERSION'), runtime_directory: os.getenv('VINIX_APP_RUNTIME_DIR'), permissions: os.getenv('VINIX_APP_PERMISSIONS') }
	defer { unsafe {
		fields.sdk.free(); fields.id.free(); fields.version.free(); fields.architecture.free(); fields.kind.free(); fields.generation.free()
		fields.repository.free(); fields.public_key.free(); fields.sequence.free(); fields.app_directory.free(); fields.data_directory.free()
		fields.runtime_id.free(); fields.runtime_version.free(); fields.runtime_directory.free(); fields.permissions.free()
	} }
	mut context := decode(fields)!
	home := os.getenv('HOME')
	tmp := os.getenv('TMPDIR')
	expected_tmp := context.data_directory + '/tmp'
	defer { unsafe { home.free(); tmp.free(); expected_tmp.free() } }
	if home != context.data_directory || tmp != expected_tmp {
		context.close(); return error('application context does not match HOME and TMPDIR')
	}
	return context
}

// Every returned NAME=VALUE string is owned. Release with free_values.
pub fn (context &Context) environment() ![]string {
	context.validate()!
	generation := context.generation.str()
	sequence := context.sequence.str()
	mut permission_text := []u8{cap: 64}
	defer { unsafe { generation.free(); sequence.free(); permission_text.free() } }
	for grant in grants {
		if !context.declares(grant) { continue }
		if permission_text.len > 0 { permission_text << u8(` `) }
		for byte in grant { permission_text << byte }
	}
	mut values := []string{cap: 15}
	unsafe { values.flags |= .noslices }
	values << 'VINIX_APP_SDK=1'.clone()
	values << 'VINIX_APP_ID=' + context.id
	values << 'VINIX_APP_VERSION=' + context.version
	values << 'VINIX_APP_ARCHITECTURE=' + context.architecture
	values << 'VINIX_APP_KIND=' + context.kind
	values << 'VINIX_APP_GENERATION=' + generation
	values << 'VINIX_APP_REPOSITORY=' + context.repository
	values << 'VINIX_APP_PUBLIC_KEY=' + context.public_key
	values << 'VINIX_APP_SEQUENCE=' + sequence
	values << 'VINIX_APP_DIR=' + context.app_directory
	values << 'VINIX_APP_DATA=' + context.data_directory
	values << 'VINIX_APP_RUNTIME_ID=' + context.runtime_id
	values << 'VINIX_APP_RUNTIME_VERSION=' + context.runtime_version
	values << 'VINIX_APP_RUNTIME_DIR=' + context.runtime_directory
	values << 'VINIX_APP_PERMISSIONS=' + unsafe { tos(permission_text.data, permission_text.len) }
	return values
}
