// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import encoding.utf8

pub const health_diagnostic_limit = 384

pub struct PackageHealth {
pub:
	id string
	name string
	version string
	kind string
	repository string
	public_key string
	issue string // empty, namespace, payload, registration; first issue per package
	diagnostic string
}

// Integrity of each package's own installed tree, not trust, launch admission,
// dependency health or authorization to repair. Scanning continues after issues.
pub struct HealthReport {
pub:
	format int = 1
	generation u64
	architecture string
	rows []PackageHealth
}

pub fn (report &HealthReport) validate() ! {
	if report.format != 1 || report.architecture !in ['aarch64', 'x86_64']!
		|| report.rows.len > 4096 || (report.generation == 0 && report.rows.len != 0) {
		return error('invalid installed health report')
	}
	mut previous := ''
	for row in report.rows {
		if !identifier(row.id) || row.id <= previous || row.name == '' || !printable(row.name, 256)
			|| !utf8.validate_str(row.name) || !version(row.version) || !identifier(row.repository)
			|| !digest(row.public_key) || row.kind !in ['native', 'linux', 'windows', 'apple', 'runtime', 'data']!
			|| row.issue !in ['', 'namespace', 'payload', 'registration']!
			|| ((row.issue == '') != (row.diagnostic == ''))
			|| !printable(row.diagnostic, health_diagnostic_limit) || !utf8.validate_str(row.diagnostic)
			|| (row.issue == 'registration' && row.kind in ['runtime', 'data']!) {
			return error('invalid package in installed health report')
		}
		previous = row.id
	}
}

fn close_package_health(row PackageHealth) {
	unsafe {
		row.id.free(); row.name.free(); row.version.free(); row.kind.free()
		row.repository.free(); row.public_key.free(); row.issue.free(); row.diagnostic.free()
	}
}

pub fn (mut report HealthReport) close() {
	unsafe {
		report.architecture.free()
		for row in report.rows { close_package_health(row) }
		(&array(&report.rows)).free()
	}
	report = HealthReport{}
}

const health_keys = ['format', 'generation', 'architecture', 'rows']
const health_row_keys = ['id', 'name', 'version', 'kind', 'repository', 'public_key', 'issue', 'diagnostic']

fn (mut r MetadataReader) health_row() !PackageHealth {
	r.expect(`{`)!
	mut row := PackageHealth{}
	mut accepted := false
	defer { if !accepted { close_package_health(row) } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(health_row_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { row = PackageHealth{ ...row, id: r.quoted(128)! } }
			1 { row = PackageHealth{ ...row, name: r.quoted(256)! } }
			2 { row = PackageHealth{ ...row, version: r.quoted(29)! } }
			3 { row = PackageHealth{ ...row, kind: r.quoted(16)! } }
			4 { row = PackageHealth{ ...row, repository: r.quoted(128)! } }
			5 { row = PackageHealth{ ...row, public_key: r.quoted(64)! } }
			6 { row = PackageHealth{ ...row, issue: r.quoted(16)! } }
			7 { row = PackageHealth{ ...row, diagnostic: r.quoted(health_diagnostic_limit)! } }
			else {}
		}
	}
	if seen != 255 { return error('missing installed health row field') }
	accepted = true
	return row
}

fn (mut r MetadataReader) health_rows() ![]PackageHealth {
	r.expect(`[` )!
	mut rows := []PackageHealth{cap: 16}
	unsafe { rows.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { mut discarded := HealthReport{ rows: rows }; discarded.close() } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if rows.len == 4096 { return error('installed health row count exceeds its bound') }
		row := r.health_row()!
		pointer := unsafe { &row }
		unsafe { rows.push_many(pointer, 1) }
	}
	accepted = true
	return rows
}

pub fn decode_health(text string) !HealthReport {
	if text.len > 8 * 1024 * 1024 { return error('installed health response exceeds its bound') }
	mut r := &MetadataReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut report := HealthReport{}
	mut accepted := false
	defer { if !accepted { report.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(health_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { r.expect(`1`)! }
			1 { report = HealthReport{ ...report, generation: r.unsigned(~u64(0))! } }
			2 { report = HealthReport{ ...report, architecture: r.quoted(16)! } }
			3 { report = HealthReport{ ...report, rows: r.health_rows()! } }
			else {}
		}
	}
	r.spaces()
	if seen != 15 || r.position != text.len { return error('incomplete or trailing installed health report') }
	report.validate()!
	accepted = true
	return report
}
