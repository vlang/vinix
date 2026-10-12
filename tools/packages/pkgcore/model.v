// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

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
	return value.len > 0 && value.len <= 128 && value[0] >= `a` && value[0] <= `z`
		&& value.bytes().all((it >= `a` && it <= `z`) || (it >= `0` && it <= `9`) || it in [
			u8(`.`),
			`-`,
			`_`,
		])
}

pub fn relative_path(path string) bool {
	return path.len > 0 && path.len <= 1024 && !path.starts_with('/')
		&& !path.contains('\\') && !path.bytes().any(it < 32 || it == 127)
		&& path.split('/').all(it != '' && it != '.' && it != '..')
}

pub fn digest_valid(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn printable(value string, limit int) bool {
	return value.len <= limit && !value.bytes().any(it < 32 || it == 127)
}

pub fn version_parts(version string) ![]u64 {
	parts := version.split('.')
	if parts.len != 3 { return error('version must contain three numeric components: ${version}') }
	mut result := []u64{}
	for part in parts {
		if part.len == 0 || part.len > 9 || !part.bytes().all(it >= `0` && it <= `9`)
			|| (part.len > 1 && part[0] == `0`) {
			return error('invalid version: ${version}')
		}
		result << part.u64()
	}
	return result
}

pub fn compare_versions(left string, right string) int {
	a := version_parts(left) or { return 0 }
	b := version_parts(right) or { return 0 }
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
	if d.minimum != '' { version_parts(d.minimum)! }
	if d.before != '' { version_parts(d.before)! }
	if d.minimum != '' && d.before != '' && compare_versions(d.minimum, d.before) >= 0 {
		return error('empty dependency range for ${d.id}')
	}
}

pub fn (p Package) validate() ! {
	if !identifier(p.id) { return error('invalid package ID: ${p.id}') }
	version_parts(p.version)!
	if p.architecture !in ['aarch64', 'x86_64', 'all'] {
		return error('unsupported architecture: ${p.architecture}')
	}
	if p.kind !in ['native', 'linux', 'windows', 'apple', 'runtime', 'data'] {
		return error('invalid package kind: ${p.kind}')
	}
	if p.sdk != 1 { return error('unsupported SDK for ${p.id}') }
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
	if p.permissions.any(it !in ['network', 'files', 'process', 'display', 'audio']) {
		return error('${p.id}: unknown permission')
	}
	if p.associations.len > 128 || p.associations.any(!printable(it, 128) || !it.contains('/') || it.contains(';') || it.contains('=')) {
		return error('${p.id}: invalid MIME association')
	}
	if p.dependencies.len > 128 { return error('${p.id}: too many dependencies') }
	for dependency in p.dependencies { dependency.validate()! }
	mut dependencies := map[string]bool{}
	for dependency in p.dependencies {
		if dependency.id in dependencies { return error('${p.id}: duplicate dependency ID') }
		dependencies[dependency.id] = true
	}
	if p.files.len == 0 || p.files.len > max_files { return error('${p.id}: invalid file count') }
	mut paths := map[string]bool{}
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
		mut parent := ''
		parts := file.path.split('/')
		for component in parts[..parts.len - 1] {
			parent = if parent == '' { component } else { parent + '/' + component }
			if parent in paths { return error('${p.id}: file/directory collision: ${file.path}') }
		}
	}
	if p.runtime == '' && p.kind !in ['runtime', 'data'] && !p.files.any(it.path == p.entrypoint && it.executable) {
		return error('${p.id}: executable entrypoint missing from payload')
	}
}

pub fn (c Config) validate() ! {
	if c.format != 1 || c.architecture !in ['aarch64', 'x86_64'] {
		return error('unsupported package configuration')
	}
	if c.launch_user != '' && (!launch_account_name(c.launch_user) || c.launch_user in ['root', 'greeter', 'nobody']) {
		return error('package launch_user must name an ordinary account')
	}
	mut ids := map[string]bool{}
	for repository in c.repositories {
		if !identifier(repository.id) || repository.id in ids || !digest_valid(repository.public_key)
			|| !printable(repository.url, 4096) || repository.url.contains('?') || repository.url.contains('#')
			|| !(repository.url.starts_with('https://') || (repository.url.starts_with('file:///') && relative_path(repository.url[8..]))) {
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
	for label, values in {'allowlist': policy.allowed, 'permissions': policy.permissions, 'licenses': policy.licenses} {
		mut seen := map[string]bool{}
		for value in values {
			if value in seen || value == '' || !printable(value, 256)
				|| (label == 'allowlist' && !identifier(value))
				|| (label == 'permissions' && value !in ['network', 'files', 'process', 'display', 'audio']) {
				return error('invalid or duplicate organization ${label} entry: ${value}')
			}
			seen[value] = true
		}
	}
	mut pins := map[string]bool{}
	for pin in policy.pins {
		pin.validate()!
		if pin.id in pins { return error('duplicate organization version pin: ${pin.id}') }
		pins[pin.id] = true
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
	packages.sort_with_compare(package_order)
	mut canonical := []Package{}
	for p in packages {
		canonical << canonical_package(p)!
	}
	return json2.encode(Index{ ...index, packages: canonical }) + '\n'
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
