// SPDX-License-Identifier: GPL-2.0-or-later
// SDK 1 presentation protocol; no package database or privileged operations.
module pkgprotocol

pub struct ReviewPackage {
pub:
	id                string
	name              string
	description       string
	version           string
	installed_version string
	architecture      string
	kind              string
	runtime           string
	repository        string
	public_key        string
	license           string
	proprietary       bool
	firmware          bool
	permissions       []string
	installed_permissions_known bool
	installed_permissions []string // optional format-2 pair; frozen active-generation declarations
	requested         bool
	action            string // install, update, keep, remove, export (mirror only)
}

pub struct Review {
pub:
	format            int
	operation         string
	names             []string
	architecture      string
	generation        u64
	target_generation u64 // rollback source; restored into a fresh generation
	fingerprint       string
	requested         []string
	rows              []ReviewPackage // target closure and removals, sorted by ID
	disk_needed       u64
	disk_available    u64
	disk_reserve      u64
}


fn identifier(value string) bool {
	if value.len == 0 || value.len > 128 || value[0] < `a` || value[0] > `z` { return false }
	for byte in value {
		if !((byte >= `a` && byte <= `z`) || (byte >= `0` && byte <= `9`) || byte in [
			u8(`.`),
			`-`,
			`_`,
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

fn digest(value string) bool {
	if value.len != 64 { return false }
	for byte in value {
		if !((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`)) { return false }
	}
	return true
}

fn version(value string) bool {
	if value.len == 0 || value.len > 29 { return false }
	mut components := 1
	mut digits := 0
	mut zero := false
	for byte in value {
		if byte == `.` {
			if digits == 0 { return false }
			components++
			digits = 0
			zero = false
		} else {
			if byte < `0` || byte > `9` || digits >= 9 || zero { return false }
			zero = digits == 0 && byte == `0`
			digits++
		}
	}
	return components == 3 && digits > 0
}

// The action describes the same installed state as the version fields. Updates
// may retain a version (repair/provenance changes) or go backwards (rollback).
fn review_action_valid(row &ReviewPackage, operation string) bool {
	if operation == 'remove' && row.action !in ['keep', 'remove']! { return false }
	return match row.action {
		'install', 'export' { row.installed_version == '' }
		'keep', 'remove' { row.installed_version == row.version }
		'update' { row.installed_version != '' }
		else { false }
	}
}

pub fn (review &Review) validate() ! {
	if review.format !in [1, 2]! || review.operation !in ['install', 'remove', 'upgrade', 'deploy', 'repair', 'rollback', 'mirror']
		|| review.architecture !in ['aarch64', 'x86_64'] || !digest(review.fingerprint)
		|| review.rows.len > 8192 || review.names.len > 4096 || review.requested.len > 4096
		|| review.names.any(!identifier(it)) || review.requested.any(!identifier(it))
		|| (review.operation in ['install', 'remove', 'mirror'] && review.names.len == 0)
		|| (review.operation in ['upgrade', 'repair', 'rollback'] && review.names.len != 0)
		|| (review.operation == 'rollback' && review.target_generation == 0)
		|| (review.operation != 'rollback' && review.target_generation != 0) {
		return error('invalid package review response')
	}
	mut previous := ''
	for row in review.rows {
		if !identifier(row.id) || row.id <= previous || row.name == '' || !printable(row.name, 256)
			|| !printable(row.description, 4096) || !version(row.version)
			|| (row.installed_version != '' && !version(row.installed_version)) || !printable(row.license, 256) || row.license == ''
			|| row.architecture !in [review.architecture, 'all']
			|| row.kind !in ['native', 'linux', 'windows', 'apple', 'runtime', 'data']
			|| (row.architecture == 'all' && row.kind != 'data')
			|| (row.kind in ['linux', 'windows', 'apple'] && row.runtime == '')
			|| (row.runtime != '' && !identifier(row.runtime)) || !identifier(row.repository)
			|| !digest(row.public_key) || !review_action_valid(row, review.operation)
			|| ((row.action == 'export') != (review.operation == 'mirror'))
			|| (review.operation == 'repair' && (row.action !in ['keep', 'update'] || row.installed_version != row.version))
			|| !view_permissions(row.permissions)
			|| !view_permissions(row.installed_permissions)
			|| (review.format == 1 && (row.installed_permissions_known || row.installed_permissions.len > 0))
			|| (!row.installed_permissions_known && row.installed_permissions.len > 0)
			|| (row.installed_permissions_known && (row.installed_version == '' || review.operation == 'mirror'))
			|| (row.installed_permissions_known && (row.action == 'install'
				|| ((row.action in ['keep', 'remove']! || review.operation == 'repair')
					&& (row.permissions.len != row.installed_permissions.len || row.permissions.any(it !in row.installed_permissions)))))
			|| row.requested != (row.id in review.requested) || (row.action == 'remove' && row.requested) {
			return error('invalid package in review response')
		}
		previous = row.id
	}
	for id in review.requested {
		if !review.rows.any(it.id == id && it.action != 'remove') {
			return error('package review is missing a requested application')
		}
	}
}

fn close_review_package(row ReviewPackage) {
	unsafe {
		row.id.free(); row.name.free(); row.description.free(); row.version.free()
		row.installed_version.free(); row.architecture.free(); row.kind.free(); row.runtime.free()
		row.repository.free(); row.public_key.free(); row.license.free(); row.action.free()
		for permission in row.permissions { permission.free() }
		(&array(&row.permissions)).free()
		for permission in row.installed_permissions { permission.free() }
		(&array(&row.installed_permissions)).free()
	}
}

// Decoded responses own their strings. UI reload/cancel/close retires all of them.
pub fn (mut review Review) close() {
	unsafe {
		review.operation.free()
		for name in review.names { name.free() }
		(&array(&review.names)).free()
		review.architecture.free()
		review.fingerprint.free()
		for id in review.requested { id.free() }
		(&array(&review.requested)).free()
		for row in review.rows { close_review_package(row) }
		(&array(&review.rows)).free()
	}
	review = Review{}
}
