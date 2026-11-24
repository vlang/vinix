// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

const personal_data_keys = ['format', 'rows']
const personal_data_row_keys = ['id', 'installed', 'diagnostic']

pub struct PersonalData {
pub:
	id         string
	installed  bool
	diagnostic string
}

// An observation of the calling account's data, never permission to delete it.
// purge-data rechecks installed state, live generation leases and filesystem
// ownership after confirmation.
pub struct PersonalDataStatus {
pub:
	format int
	rows   []PersonalData
}

pub fn decode_personal_data(text string) !PersonalDataStatus {
	if text.len > 8 * 1024 * 1024 { return error('personal data status exceeds metadata limit') }
	mut reader := &MetadataReader{ text: text }
	defer { unsafe { free(reader) } }
	reader.expect(`{`)!
	mut status := &PersonalDataStatus{}
	defer { unsafe { free(status) } }
	mut accepted := false
	defer { if !accepted { status.close() } }
	mut seen := u16(0)
	mut first := true
	for reader.next(first, `}`)! {
		first = false
		field := reader.member(personal_data_keys, seen)!
		seen |= u16(1) << field
		if field == 0 {
			reader.expect(`1`)!
			unsafe { *status = PersonalDataStatus{ ...status, format: 1 } }
		} else {
			unsafe { *status = PersonalDataStatus{ ...status, rows: reader.rows()! } }
		}
	}
	reader.spaces()
	if seen != 3 || reader.position != text.len { return error('incomplete or trailing personal data status') }
	status.validate()!
	accepted = true
	return *status
}

fn (mut r MetadataReader) row() !PersonalData {
	r.expect(`{`)!
	mut row := PersonalData{}
	mut accepted := false
	defer { if !accepted { close_personal_data_row(row) } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(personal_data_row_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { row = PersonalData{ ...row, id: r.quoted(128)! } }
			1 { row = PersonalData{ ...row, installed: r.boolean()! } }
			2 { row = PersonalData{ ...row, diagnostic: r.quoted(512)! } }
			else {}
		}
	}
	if seen != 7 { return error('missing personal data row field') }
	accepted = true
	return row
}

fn (mut r MetadataReader) rows() ![]PersonalData {
	r.expect(`[` )!
	mut rows := []PersonalData{cap: 16}
	unsafe { rows.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { close_personal_data_rows(rows) } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if rows.len == 4096 { return error('personal data row count exceeds its bound') }
		rows << r.row()!
	}
	accepted = true
	return rows
}

pub fn (status &PersonalDataStatus) validate() ! {
	if status.format != 1 || status.rows.len > 4096 { return error('unsupported personal data status') }
	for index, row in status.rows {
		if !identifier(row.id) || (row.diagnostic != '' && !printable(row.diagnostic, 512)) {
			return error('invalid personal data entry')
		}
		for previous in 0 .. index {
			if status.rows[previous].id == row.id { return error('duplicate personal data ID') }
		}
	}
}

fn close_personal_data_row(row PersonalData) {
	unsafe {
		row.id.free()
		row.diagnostic.free()
	}
}

fn close_personal_data_rows(rows []PersonalData) {
	for row in rows { close_personal_data_row(row) }
	unsafe { (&array(&rows)).free() }
}

pub fn (mut status PersonalDataStatus) close() {
	close_personal_data_rows(status.rows)
	status = PersonalDataStatus{}
}
