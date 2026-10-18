// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.appsdk

pub const format_version = 1
pub const max_metadata = 8 * 1024 * 1024
pub const max_files = 16384

pub struct Dependency {
pub:
	id      string
	minimum string
	before  string
}

pub struct Payload {
pub:
	path       string
	sha256     string
	bytes      u64
	executable bool
}

pub struct Package {
pub:
	id           string
	version      string
	architecture string
	name         string
	description  string
	homepage     string
	license      string
	proprietary  bool
	firmware     bool
	kind         string // native, linux, windows, apple, runtime, data
	runtime      string // dependency ID, never a host executable
	entrypoint   string // relative to this package (or its runtime)
	arguments    []string
	permissions  []string
	associations []string // MIME types; installation does not change user defaults
	dependencies []Dependency
	files        []Payload
	sdk          int = 1
	window_protocol int @[omitempty] // 0 preserves existing manifest bytes/digests
}

pub struct Index {
pub:
	format     int = 1
	repository string
	sequence   u64
	expires    i64
	packages   []Package
}

pub struct Repository {
pub:
	id         string
	url        string // https:// or file:///absolute/path
	public_key string // Ed25519 hex, enrolled by an administrator
}

pub struct Policy {
pub:
	offline        bool
	allowed        []string // empty allows any package in an enrolled repository
	pins           []Dependency
	permissions    []string = ['network', 'files', 'process', 'display', 'audio']
	licenses       []string // explicit acceptance of proprietary license identifiers
	allow_firmware bool
	reserve_bytes  u64 = 64 * 1024 * 1024
}

pub struct Config {
pub:
	format       int = 1
	architecture string
	repositories []Repository
	policy       Policy
	launch_user  string // administrator-selected account for root desktop launches
}

pub struct Installed {
pub:
	package    Package
	repository string
	public_key string
	sequence   u64
}

pub struct State {
pub:
	format       int = 1
	generation   u64
	previous     u64
	architecture string
	requested    []string
	packages     []Installed
}

pub struct Catalog {
pub:
	packages []Installed
}

pub fn identifier(value string) bool {
	if value.len == 0 || value.len > 128 || value[0] < `a` || value[0] > `z` { return false }
	for byte in value {
		if !((byte >= `a` && byte <= `z`) || (byte >= `0` && byte <= `9`) || byte in [u8(`.`), `-`, `_`]) { return false }
	}
	return true
}

pub fn relative_path(path string) bool {
	return relative_path_from(path, 0)
}

// A file:// URL uses the same byte rules without copying its relative suffix.
fn relative_path_from(path string, start int) bool {
	if path.len <= start || path.len - start > 1024 { return false }
	mut component := start
	for i := start; i <= path.len; i++ {
		if i == path.len || path[i] == `/` {
			length := i - component
			if length == 0 || (length == 1 && path[component] == `.`)
				|| (length == 2 && path[component] == `.` && path[component + 1] == `.`) { return false }
			component = i + 1
		} else if path[i] < 32 || path[i] == 127 || path[i] == `\\` { return false }
	}
	return true
}

pub fn digest_valid(value string) bool {
	if value.len != 64 { return false }
	for byte in value {
		if !((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`)) { return false }
	}
	return true
}

fn printable(value string, limit int) bool {
	if value.len > limit { return false }
	for byte in value { if byte < 32 || byte == 127 { return false } }
	return true
}

pub fn version_parts(version string) ![]u64 {
	values := validated_version(version)!
	return [values[0], values[1], values[2]]
}

// Admission needs no owned result. Keep the public version_parts array contract
// for callers that need components, and preserve its diagnostic precedence.
fn validated_version(version string) ![3]u64 {
	return version_values(version) or {
		if version.count('.') != 2 { return error('version must contain three numeric components: ${version}') }
		return error('invalid version: ${version}')
	}
}

// Sorting and constraint checks run repeatedly during dependency search. Keep
// canonical numeric components on the stack instead of allocating split arrays.
fn version_values(text string) ?[3]u64 {
	if text.len == 0 || text.len > 29 { return none }
	mut values := [3]u64{}
	mut component := 0
	mut digits := 0
	mut zero := false
	for byte in text {
		if byte == `.` {
			if component == 2 || digits == 0 { return none }
			component++; digits = 0; zero = false
		} else {
			if byte < `0` || byte > `9` || digits == 9 || (digits > 0 && zero) { return none }
			zero = digits == 0 && byte == `0`
			values[component] = values[component] * 10 + u64(byte - `0`)
			digits++
		}
	}
	if component != 2 || digits == 0 { return none }
	return values
}

pub fn compare_versions(left string, right string) int {
	a := version_values(left) or { return 0 }
	b := version_values(right) or { return 0 }
	for i in 0 .. 3 {
		if a[i] < b[i] { return -1 }
		if a[i] > b[i] { return 1 }
	}
	return 0
}

pub fn (d Dependency) accepts(p Package) bool {
	return d.id == p.id && (d.minimum == '' || compare_versions(p.version, d.minimum) >= 0)
		&& (d.before == '' || compare_versions(p.version, d.before) < 0)
}

pub fn (d Dependency) validate() ! {
	if !identifier(d.id) { return error('invalid dependency ID: ${d.id}') }
	if d.minimum != '' { validated_version(d.minimum)! }
	if d.before != '' { validated_version(d.before)! }
	if d.minimum != '' && d.before != '' && compare_versions(d.minimum, d.before) >= 0 {
		return error('empty dependency range for ${d.id}')
	}
}

fn check_package_permissions(p Package) ! {
	if !appsdk.valid_permissions(p.permissions) {
		return error('${p.id}: permissions must be distinct SDK 1 grants: audio, display, files, network, process')
	}
}

pub fn (p Package) validate() ! {
	if !identifier(p.id) { return error('invalid package ID: ${p.id}') }
	validated_version(p.version)!
	if p.architecture !in ['aarch64', 'x86_64', 'all'] {
		return error('unsupported architecture: ${p.architecture}')
	}
	if p.kind !in ['native', 'linux', 'windows', 'apple', 'runtime', 'data'] {
		return error('invalid package kind: ${p.kind}')
	}
	if p.sdk != 1 { return error('unsupported SDK for ${p.id}') }
	if p.window_protocol !in [0, 1, 2] || (p.window_protocol != 0 && (p.kind != 'native' || 'display' !in p.permissions)) {
		return error('${p.id}: native window protocol requires a native application with display permission')
	}
	if !printable(p.name, 256) || p.name == '' || !printable(p.description, 4096)
		|| !printable(p.homepage, 1024) || !printable(p.license, 256) || p.license == '' {
		return error('invalid descriptive metadata for ${p.id}')
	}
	if p.architecture == 'all' && p.kind != 'data' {
		return error('native binaries and runtimes must declare their target architecture')
	}
	if p.kind in ['linux', 'windows', 'apple'] && p.runtime == '' {
		return error('${p.id} must declare an isolated runtime dependency')
	}
	if p.runtime != '' && (!identifier(p.runtime) || !p.dependencies.any(it.id == p.runtime)) {
		return error('${p.id}: runtime must be a declared dependency')
	}
	if p.kind !in ['data', 'runtime'] && !relative_path(p.entrypoint) {
		return error('${p.id}: invalid entrypoint')
	}
	if p.arguments.len > 64 || p.arguments.any(!printable(it, 4096)) {
		return error('${p.id}: invalid launch arguments')
	}
	check_package_permissions(p)!
	if p.associations.len > 128 || p.associations.any(!printable(it, 128) || !it.contains('/') || it.contains(';') || it.contains('=')) {
		return error('${p.id}: invalid MIME association')
	}
	if p.dependencies.len > 128 { return error('${p.id}: too many dependencies') }
	for dependency in p.dependencies { dependency.validate()! }
	mut dependencies := map[string]bool{}
	defer { unsafe { dependencies.free() } }
	for dependency in p.dependencies {
		if dependency.id in dependencies { return error('${p.id}: duplicate dependency ID') }
		dependencies[dependency.id] = true
	}
	if p.files.len == 0 || p.files.len > max_files { return error('${p.id}: invalid file count') }
	mut paths := map[string]bool{}
	defer { unsafe { paths.free() } }
	mut size := u64(0)
	for file in p.files {
		if !relative_path(file.path) || !digest_valid(file.sha256) || file.path in paths
			|| file.bytes > u64(4) * 1024 * 1024 * 1024 {
			return error('${p.id}: invalid or duplicate payload path: ${file.path}')
		}
		paths[file.path] = true
		size += file.bytes
		if size > u64(64) * 1024 * 1024 * 1024 { return error('${p.id}: payload too large') }
	}
	for file in p.files {
		for i, byte in file.path {
			if byte != `/` { continue }
			// Membership only reads this bounded prefix; the map owns its keys
			// and never retains the temporary view into the caller's path.
			parent := unsafe { tos(file.path.str, i) }
			if parent in paths { return error('${p.id}: file/directory collision: ${file.path}') }
		}
	}
	if p.runtime == '' && p.kind !in ['runtime', 'data'] && !p.files.any(it.path == p.entrypoint && it.executable) {
		return error('${p.id}: executable entrypoint missing from payload')
	}
}

fn valid_repository(repository Repository) bool {
	return identifier(repository.id) && digest_valid(repository.public_key)
		&& printable(repository.url, 4096) && !repository.url.contains('?') && !repository.url.contains('#')
		&& (repository.url.starts_with('https://') || (repository.url.starts_with('file:///') && relative_path_from(repository.url, 8)))
}

pub fn (c Config) validate() ! {
	if c.format != 1 || c.architecture !in ['aarch64', 'x86_64'] {
		return error('unsupported package configuration')
	}
	if c.launch_user != '' && (!launch_account_name(c.launch_user) || c.launch_user in ['root', 'greeter', 'nobody']) {
		return error('package launch_user must name an ordinary account')
	}
	if c.repositories.len > 4096 { return error('package configuration exceeds the repository identity limit') }
	mut ids := map[string]bool{}
	defer { unsafe { ids.free() } }
	for repository in c.repositories {
		if !valid_repository(repository) || repository.id in ids {
			return error('invalid or duplicate repository: ${repository.id}')
		}
		ids[repository.id] = true
	}
	c.policy.validate()!
}

pub fn (policy Policy) validate() ! {
	if policy.allowed.len > 4096 || policy.pins.len > 4096 || policy.licenses.len > 4096
		|| policy.permissions.len > 5 || policy.reserve_bytes > u64(1024) * 1024 * 1024 * 1024 {
		return error('organization policy exceeds its supported limits')
	}
	validate_policy_entries('allowlist', policy.allowed)!
	validate_policy_entries('permissions', policy.permissions)!
	validate_policy_entries('licenses', policy.licenses)!
	mut pins := map[string]bool{}
	defer { unsafe { pins.free() } }
	for pin in policy.pins {
		pin.validate()!
		if pin.id in pins { return error('duplicate organization version pin: ${pin.id}') }
		pins[pin.id] = true
	}
}

fn validate_policy_entries(label string, values []string) ! {
	mut seen := map[string]bool{}
	defer { unsafe { seen.free() } }
	for value in values {
		if value in seen || value == '' || !printable(value, 256)
			|| (label == 'allowlist' && !identifier(value))
			|| (label == 'permissions' && value !in ['network', 'files', 'process', 'display', 'audio']) {
			return error('invalid or duplicate organization ${label} entry: ${value}')
		}
		seen[value] = true
	}
}

pub fn check_policy(p Package, policy Policy) ! {
	if policy.allowed.len > 0 && p.id !in policy.allowed {
		return error('${p.id}: blocked by organization allowlist')
	}
	for pin in policy.pins {
		if pin.id == p.id && !pin.accepts(p) {
			return error('${p.id}: version blocked by organization pin')
		}
	}
	if p.permissions.any(it !in policy.permissions) {
		return error('${p.id}: permissions blocked by organization policy')
	}
	if p.proprietary && p.license !in policy.licenses {
		return error('${p.id}: administrator must accept license ${p.license}')
	}
	if p.firmware && !policy.allow_firmware {
		return error('${p.id}: firmware installation requires explicit policy approval')
	}
}

// Publishing emits structs and sorted slices, never unordered JSON maps.
fn package_order(a &Package, b &Package) int {
	if a.id != b.id { return if a.id < b.id { -1 } else { 1 } }
	if a.architecture != b.architecture {
		return if a.architecture < b.architecture { -1 } else { 1 }
	}
	return compare_versions(a.version, b.version)
}

pub fn canonical_index(index Index) !string {
	mut packages := index.packages.clone()
	defer { unsafe { (&array(&packages)).free() } }
	packages.sort_with_compare(package_order)
	mut canonical := []Package{cap: packages.len}
	defer {
		for p in canonical { close_canonical_package(p) }
		unsafe { (&array(&canonical)).free() }
	}
	for p in packages {
		owned := canonical_package(p)!
		pointer := unsafe { &owned }
		unsafe { canonical.push_many(pointer, 1) }
	}
	return publisher_json(Index{ ...index, packages: canonical })
}

// Canonicalization borrows scalar strings and nested record fields; only its
// four independently sorted collection buffers belong to the temporary copy.
fn close_canonical_package(p Package) {
	unsafe {
		(&array(&p.files)).free(); (&array(&p.dependencies)).free()
		(&array(&p.permissions)).free(); (&array(&p.associations)).free()
	}
}

fn canonical_package(p Package) !Package {
	p.validate()!
	mut files := p.files.clone()
	files.sort(a.path < b.path)
	mut deps := p.dependencies.clone()
	deps.sort(a.id < b.id)
	mut permissions := p.permissions.clone()
	permissions.sort()
	mut associations := p.associations.clone()
	associations.sort()
	return Package{ ...p, files: files, dependencies: deps, permissions: permissions, associations: associations }
}
