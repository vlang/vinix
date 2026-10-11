// SPDX-License-Identifier: GPL-2.0-or-later
module packagecore

import json2
import os
import desktop.workflowcore

pub const association_prefix = 'package.'
pub const request_prefix = 'software.launch:'

// The compositor reads only presentation fields from administrator-owned state.
// Executable paths, arguments, trust and confinement stay in vinix-package.
struct Manifest {
	id           string
	name         string
	description  string
	architecture string
	kind         string
	permissions  []string
	associations []string
}

struct Installed {
	package Manifest
}

struct State {
	// Own raw number text explicitly; json2's numeric substring conversion is
	// otherwise retained by the current compiler under -manualfree.
	format       string @[raw]
	generation   string @[raw]
	architecture string
	packages     []Installed
}

pub struct App {
pub:
	id           string
	name         string
	description  string
	association  string
	start_action string
	open_action  string
	mime_types   []string
}

pub struct Registry {
pub mut:
	apps       []App
	generation u64
mut:
	seen      workflowcore.Identity
	seen_arch int
}

pub struct Request {
pub:
	id       string
	document string
}

pub fn identifier(value string) bool {
	if value.len == 0 || value.len > 128 || value[0] < `a` || value[0] > `z` { return false }
	for byte in value {
		if !((byte >= `a` && byte <= `z`) || (byte >= `0` && byte <= `9`) || byte in [
			`-`,
			`_`,
			`.`,
		]) {
			return false
		}
	}
	return true
}

fn printable(value string, limit int) bool {
	if value.len > limit { return false }
	for byte in value { if byte < 32 || byte == 127 { return false } }
	return true
}

pub fn (request Request) validate() ! {
	if !identifier(request.id) || (request.document != '' && (!request.document.starts_with('/') || !printable(request.document, 4096))) {
		return error('invalid package launch request')
	}
}

pub fn (app &App) accepts(mime string) bool { return mime in app.mime_types }

pub fn (registry &Registry) find(id string) ?int {
	for index, app in registry.apps { if app.id == id { return index } }
	return none
}

pub fn (registry &Registry) handler(name string, mime string) ?string {
	for app in registry.apps {
		if app.association == name && app.accepts(mime) { return app.id }
	}
	return none
}

pub fn (mut registry Registry) close() {
	for app in registry.apps {
		unsafe {
			app.id.free()
			app.name.free()
			app.description.free()
			app.association.free()
			app.start_action.free()
			app.open_action.free()
			for mime in app.mime_types { mime.free() }
			(&array(&app.mime_types)).free()
		}
	}
	unsafe { registry.apps.free() }
	registry.apps = []App{}
	registry.generation = 0
	registry.seen = workflowcore.Identity{}
	registry.seen_arch = 0
}

fn trusted(path string, owner u32, directory bool) !workflowcore.Identity {
	info := workflowcore.identify(path)!
	if info.uid != owner || info.mode & 0o022 != 0 || if directory {
		!info.directory()
	} else {
		!info.regular()
	} {
		return error('untrusted package registration')
	}
	return info
}

// Resolving current once gives a coherent generation even during activation.
// Readers do not need a catalog or network connection. Launch rechecks current
// state and holds its lease; a stale menu cannot execute a removed generation.
pub fn (mut registry Registry) refresh(directory string, owner u32, architecture string) !bool {
	target_arch := match architecture {
		'aarch64' { 1 }
		'x86_64' { 2 }
		else { return error('unsupported package architecture') }
	}
	current := directory + '/current'
	defer { unsafe { current.free() } }
	if !os.exists(current) && !os.is_link(current) {
		changed := registry.apps.len > 0 || registry.generation != 0
		registry.close()
		return changed
	}
	trusted(directory, owner, true)!
	activation := workflowcore.identify(current)!
	if !activation.link() || activation.uid != owner {
		return error('untrusted package activation')
	}
	target := os.readlink(current)!
	defer { unsafe { target.free() } }
	if !target.starts_with('generations/') || target.len <= 12 || target.len > 32 {
		return error('invalid package generation')
	}
	number := unsafe { tos(target.str + 12, target.len - 12) }
	for byte in number {
		if byte < `0` || byte > `9` { return error('invalid package generation') }
	}
	if number.u64() == 0 { return error('invalid package generation') }
	parent := directory + '/generations'
	generation := directory + '/' + target
	path := generation + '/state.json'
	defer {
		unsafe {
			parent.free()
			generation.free()
			path.free()
		}
	}
	trusted(parent, owner, true)!
	trusted(generation, owner, true)!
	identity := trusted(path, owner, false)!
	if registry.seen_arch == target_arch && registry.seen.unchanged(identity) { return false }
	bytes := workflowcore.read_regular(path, 8 * 1024 * 1024)!
	defer { unsafe { bytes.free() } }
	state := json2.decode[State](unsafe { tos(bytes.data, bytes.len) })!
	defer {
		unsafe {
			state.format.free()
			state.generation.free()
			state.architecture.free()
			for installed in state.packages {
				p := installed.package
				p.id.free()
				p.name.free()
				p.description.free()
				p.architecture.free()
				p.kind.free()
				for permission in p.permissions { permission.free() }
				(&array(&p.permissions)).free()
				for mime in p.associations { mime.free() }
				(&array(&p.associations)).free()
			}
			(&array(&state.packages)).free()
		}
	}
	if state.format != '1' || state.generation != number || state.architecture != architecture || state.packages.len > 4096 {
		return error('incompatible package registration')
	}
	mut ids := map[string]bool{}
	defer { unsafe { ids.free() } }
	// Validate the entire snapshot before replacing the existing registry.
	for installed in state.packages {
		p := installed.package
		if !identifier(p.id) || p.id in ids || p.architecture !in [architecture, 'all']
			|| p.name == '' || !printable(p.name, 256) || !printable(p.description, 4096)
			|| p.kind !in ['native', 'linux', 'windows', 'apple', 'runtime', 'data']
			|| (p.architecture == 'all' && p.kind != 'data') || p.associations.len > 128 {
			return error('invalid package registration')
		}
		ids[p.id] = true
		for mime in p.associations {
			if !printable(mime, 128) || !mime.contains('/') || mime.contains(';') || mime.contains('=') {
				return error('invalid package MIME registration')
			}
		}
	}
	registry.close()
	registry.apps = []App{cap: state.packages.len}
	unsafe { registry.apps.flags |= .noslices }
	for installed in state.packages {
		p := installed.package
		if p.kind in ['runtime', 'data'] { continue }
		mut mimes := []string{cap: p.associations.len}
		// Advertising a MIME handler requires the same files grant as launch.
		if 'files' in p.permissions {
			for mime in p.associations { mimes << mime.clone() }
		}
		app := App{
			id:           p.id.clone()
			name:         p.name.clone()
			description:  p.description.clone()
			association:  association_prefix + p.id
			start_action: 'start.package.' + p.id
			open_action:  'session.open.package.' + p.id
			mime_types:   mimes
		}
		unsafe { registry.apps.push_many(&app, 1) }
	}
	registry.apps.sort(a.id < b.id)
	registry.generation = number.u64()
	registry.seen = identity
	registry.seen_arch = target_arch
	return true
}
