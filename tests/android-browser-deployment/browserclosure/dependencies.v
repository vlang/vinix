// SPDX-License-Identifier: GPL-2.0-or-later
module browserclosure

import tarstream

struct PackageMetadata {
	name string
	version string
	dependencies []string
	provides []string
}

struct Dependency {
	name string
	operator string
	version string
	conflict bool
}

struct Provider {
	package string
	version string
}

fn absolute_command(name string) bool {
	for prefix in ['/bin/', '/sbin/', '/usr/bin/', '/usr/sbin/'] {
		if !name.starts_with(prefix) { continue }
		base := name[prefix.len..]
		return base !in ['', '.', '..'] && base.bytes().all((it >= `a` && it <= `z`)
			|| (it >= `A` && it <= `Z`) || (it >= `0` && it <= `9`)
			|| it in [u8(`_`), `+`, `-`, `.`])
	}
	return false
}

fn dependency(value string) !Dependency {
	if value == '' || value.len > 4096 || !value.bytes().all(it > 32 && it < 127) {
		return error('invalid APK dependency')
	}
	conflict := value.starts_with('!')
	text := if conflict { value[1..] } else { value }
	mut at := 0
	for at < text.len && text[at] !in [u8(`<`), `>`, `=`, `~`, `!`] { at++ }
	name := text[..at]
	if name == '' || (!absolute_command(name) && !name.bytes().all((it >= `a` && it <= `z`)
		|| (it >= `A` && it <= `Z`) || (it >= `0` && it <= `9`)
		|| it in [u8(`_`), `+`, `-`, `.`, `:`])) {
		return error('invalid APK dependency name: ' + value)
	}
	start := at
	for at < text.len && text[at] in [u8(`<`), `>`, `=`, `~`, `!`] { at++ }
	operator := text[start..at]
	version := text[at..]
	if operator !in ['', '=', '==', '<', '<=', '>', '>=']
		|| (operator == '') != (version == '') || version.contains_any('<>=~!/:\\') {
		return error('unsupported APK dependency constraint: ' + value)
	}
	return Dependency{name, operator, version, conflict}
}

fn package_metadata(path string) !PackageMetadata {
	mut archive := tarstream.open_concatenated(path)!
	defer { archive.close() }
	mut body := ''
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		if member.name != '.PKGINFO' { continue }
		if body != '' || !member.regular() || member.size <= 0 || member.size > 1024 * 1024 {
			return error('invalid duplicate or oversized APK metadata: ' + path)
		}
		mut bytes := []u8{len: int(member.size)}
		mut position := 0
		for position < bytes.len {
			mut part := unsafe { bytes[position..] }
			n := archive.read(mut part)!
			if n == 0 { return error('truncated APK metadata') }
			position += n
		}
		body = bytes.bytestr()
	}
	mut fields := map[string][]string{}
	for line in body.split_into_lines() {
		if line == '' || line.starts_with('#') { continue }
		if line.contains_any('\x00\r') { return error('invalid APK metadata framing') }
		pieces := line.split_nth(' = ', 2)
		if pieces.len != 2 { return error('malformed APK metadata') }
		fields[pieces[0]] << pieces[1]
	}
	if fields['pkgname'].len != 1 || fields['pkgver'].len != 1
		|| (fields['arch'] != ['aarch64'] && fields['arch'] != ['noarch']) {
		return error('APK metadata requires unique aarch64/noarch identity: ' + path)
	}
	identity := dependency(fields['pkgname'][0] + '=' + fields['pkgver'][0])!
	if identity.conflict || identity.name.contains_any(':/') { return error('invalid APK package identity') }
	return PackageMetadata{identity.name, identity.version, fields['depend'], fields['provides']}
}

// Inequalities use the ordinary numeric release form. Unsupported APK version
// extensions fail closed rather than approximating Alpine's ordering rules.
fn numeric_version(value string) !([]string, string) {
	pieces := value.split('-r')
	if pieces.len > 2 { return error('unsupported APK version ordering: ' + value) }
	parts := pieces[0].split('.')
	revision := if pieces.len == 2 { pieces[1] } else { '0' }
	for part in parts {
		if part == '' || !part.bytes().all(it >= `0` && it <= `9`)
			|| (part.len > 1 && part.starts_with('0')) {
			return error('unsupported APK version ordering: ' + value)
		}
	}
	if revision == '' || !revision.bytes().all(it >= `0` && it <= `9`) {
		return error('unsupported APK version revision: ' + value)
	}
	return parts, revision
}

fn number_compare(a string, b string) int {
	left, right := a.trim_left('0'), b.trim_left('0')
	if left.len != right.len { return if left.len < right.len { -1 } else { 1 } }
	if left == right { return 0 }
	return if left < right { -1 } else { 1 }
}

fn version_compare(a string, b string) !int {
	left, left_revision := numeric_version(a)!
	right, right_revision := numeric_version(b)!
	if left.len != right.len { return error('unsupported mixed APK version component counts') }
	for i in 0 .. left.len {
		comparison := number_compare(left[i], right[i])
		if comparison != 0 { return comparison }
	}
	return number_compare(left_revision, right_revision)
}

fn satisfies(version string, request Dependency) !bool {
	if request.operator == '' { return true }
	if request.operator in ['=', '=='] { return version == request.version }
	if version == '' { return false }
	comparison := version_compare(version, request.version)!
	return match request.operator {
		'<' { comparison < 0 }
		'<=' { comparison <= 0 }
		'>' { comparison > 0 }
		'>=' { comparison >= 0 }
		else { false }
	}
}

// Resolve only from caller-verified archives. No package repository, host
// installation or network may supply a missing or ambiguous dependency.
pub fn select_packages(archives map[string]string, roots []string) ![]string {
	if archives.len == 0 || archives.len > 1000 || roots.len == 0 { return error('invalid APK selection bounds') }
	mut packages := map[string]PackageMetadata{}
	mut providers := map[string][]Provider{}
	mut names := archives.keys()
	names.sort()
	for name in names {
		package := package_metadata(archives[name])!
		if package.name != name { return error('locked APK package identity mismatch: ' + name) }
		packages[name] = package
		providers[name] << Provider{name, package.version}
		for value in package.provides {
			provided := dependency(value)!
			if provided.conflict || provided.operator !in ['', '=', '=='] { return error('invalid APK provider: ' + value) }
			provider := Provider{name, provided.version}
			if provider !in providers[provided.name] { providers[provided.name] << provider }
		}
	}
	mut selected := map[string]bool{}
	mut bindings := map[string]string{}
	mut pending := roots.clone()
	mut conflicts := []Dependency{}
	for pending.len > 0 {
		value := pending.pop()
		request := dependency(value)!
		if request.conflict { conflicts << request; continue }
		mut candidates := []string{}
		for provider in providers[request.name] {
			if satisfies(provider.version, request)! && provider.package !in candidates { candidates << provider.package }
		}
		// A named real package is the deterministic provider for its own name.
		if request.name in candidates { candidates = [request.name] }
		if candidates.len != 1 { return error('unresolved or ambiguous APK dependency: ' + value) }
		name := candidates[0]
		if request.name in bindings && bindings[request.name] != name {
			return error('incompatible selected APK providers: ' + request.name)
		}
		bindings[request.name] = name
		if name in selected { continue }
		selected[name] = true
		pending << packages[name].dependencies
	}
	for conflict in conflicts {
		for provider in providers[conflict.name] {
			if provider.package in selected && satisfies(provider.version, conflict)! {
				return error('conflicting selected APK dependency: ' + conflict.name)
			}
		}
	}
	mut result := selected.keys()
	result.sort()
	return result
}
