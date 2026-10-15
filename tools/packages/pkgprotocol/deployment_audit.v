// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

pub const deployment_audit_fields = ['architecture', 'metadata_sha256', 'public_key', 'repository', 'requested', 'sequence', 'version']

pub struct DeploymentAuditRow {
pub:
	id string
	status string // match, missing, unexpected, changed
	expected_version string
	installed_version string
	differences []string // sorted field names; sequence means below the lock floor
}

// Comparison of recorded metadata only. A match does not attest payload health,
// current publisher trust, policy admission or authorization to install/launch.
pub struct DeploymentAudit {
pub:
	format int = 1
	generation u64
	architecture string
	deployment_sha256 string // exact captured input bytes, including whitespace
	matches bool
	rows []DeploymentAuditRow // sorted union of target and installed package IDs
}

pub fn (report &DeploymentAudit) validate() ! {
	if report.format != 1 || report.architecture !in ['aarch64', 'x86_64']!
		|| !digest(report.deployment_sha256) || report.rows.len > 8192 {
		return error('invalid deployment audit report')
	}
	mut previous := ''; mut matches := true
	for row in report.rows {
		if !identifier(row.id) || row.id <= previous || row.differences.len > deployment_audit_fields.len {
			return error('invalid deployment audit row')
		}
		previous = row.id
		mut prior := ''
		for field in row.differences {
			if field !in deployment_audit_fields || field <= prior { return error('invalid deployment audit difference') }
			prior = field
		}
		if report.generation == 0 && row.installed_version != '' { return error('fresh deployment audit has installed packages') }
		match row.status {
			'missing' { if !version(row.expected_version) || row.installed_version != '' || row.differences.len != 0 { return error('invalid missing deployment row') } }
			'unexpected' { if row.expected_version != '' || !version(row.installed_version) || row.differences.len != 0 { return error('invalid unexpected deployment row') } }
			'match', 'changed' {
				if !version(row.expected_version) || !version(row.installed_version)
					|| ((row.status == 'match') != (row.differences.len == 0))
					|| ((row.expected_version != row.installed_version) != ('version' in row.differences)) {
					return error('incoherent deployment audit row')
				}
			}
			else { return error('unknown deployment audit status') }
		}
		if row.status != 'match' { matches = false }
	}
	if report.matches != matches { return error('incoherent deployment audit result') }
}

fn close_deployment_audit_row(row DeploymentAuditRow) {
	unsafe {
		row.id.free(); row.status.free(); row.expected_version.free(); row.installed_version.free()
		for field in row.differences { field.free() }
		(&array(&row.differences)).free()
	}
}

pub fn (mut report DeploymentAudit) close() {
	unsafe {
		report.architecture.free(); report.deployment_sha256.free()
		for row in report.rows { close_deployment_audit_row(row) }
		(&array(&report.rows)).free()
	}
	report = DeploymentAudit{}
}

const deployment_audit_keys = ['format', 'generation', 'architecture', 'deployment_sha256', 'matches', 'rows']
const deployment_audit_row_keys = ['id', 'status', 'expected_version', 'installed_version', 'differences']

fn (mut r MetadataReader) deployment_audit_row() !DeploymentAuditRow {
	r.expect(`{`)!
	mut row := DeploymentAuditRow{}
	mut accepted := false
	defer { if !accepted { close_deployment_audit_row(row) } }
	mut seen := u16(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(deployment_audit_row_keys, seen)!; seen |= u16(1) << field
		match field {
			0 { row = DeploymentAuditRow{ ...row, id: r.quoted(128)! } }
			1 { row = DeploymentAuditRow{ ...row, status: r.quoted(16)! } }
			2 { row = DeploymentAuditRow{ ...row, expected_version: r.quoted(29)! } }
			3 { row = DeploymentAuditRow{ ...row, installed_version: r.quoted(29)! } }
			4 { row = DeploymentAuditRow{ ...row, differences: r.strings(32, 7)! } }
			else {}
		}
	}
	if seen != 31 { return error('missing deployment audit row field') }
	accepted = true
	return row
}

fn (mut r MetadataReader) deployment_audit_rows() ![]DeploymentAuditRow {
	r.expect(`[` )!
	mut rows := []DeploymentAuditRow{cap: 16}
	unsafe { rows.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { mut discarded := DeploymentAudit{ rows: rows }; discarded.close() } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if rows.len == 8192 { return error('deployment audit row count exceeds its bound') }
		row := r.deployment_audit_row()!
		pointer := unsafe { &row }
		unsafe { rows.push_many(pointer, 1) }
	}
	accepted = true
	return rows
}

pub fn decode_deployment_audit(text string) !DeploymentAudit {
	if text.len > 8 * 1024 * 1024 { return error('deployment audit exceeds its bound') }
	mut r := &MetadataReader{ text: text }; defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut report := DeploymentAudit{}; mut accepted := false
	defer { if !accepted { report.close() } }
	mut seen := u16(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(deployment_audit_keys, seen)!; seen |= u16(1) << field
		match field {
			0 { r.expect(`1`)! }
			1 { report = DeploymentAudit{ ...report, generation: r.unsigned(~u64(0))! } }
			2 { report = DeploymentAudit{ ...report, architecture: r.quoted(16)! } }
			3 { report = DeploymentAudit{ ...report, deployment_sha256: r.quoted(64)! } }
			4 { report = DeploymentAudit{ ...report, matches: r.boolean()! } }
			5 { report = DeploymentAudit{ ...report, rows: r.deployment_audit_rows()! } }
			else {}
		}
	}
	r.spaces()
	if seen != 63 || r.position != text.len { return error('incomplete or trailing deployment audit') }
	report.validate()!
	accepted = true
	return report
}
