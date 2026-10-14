// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

const software_view_keys = ['format', 'generation', 'architecture', 'offline', 'catalog_error', 'update_error', 'rows', 'launch_user']
const software_row_keys = ['id', 'name', 'description', 'version', 'installed_version', 'architecture', 'kind', 'runtime', 'repository', 'public_key', 'license', 'proprietary', 'firmware', 'permissions', 'requested', 'updatable', 'update_action', 'diagnostic', 'installed_name', 'installed_kind', 'installed_permissions', 'installed_window_protocol']

// Both presentation projections ignore additive/service-owned fields. Known
// fields remain typed, mandatory and unique, including escaped key spellings.
// Unknown values are syntax-checked without building a retained JSON tree.
fn (mut r MetadataReader) view_member(keys []string, seen u32) !int {
	key := r.quoted(8 * 1024 * 1024)!
	index := keys.index(key)
	unsafe { key.free() }
	if index >= 0 && seen & (u32(1) << index) != 0 { return error('duplicate package presentation JSON field') }
	r.expect(`:`)!
	return index
}

fn (mut r MetadataReader) skip_view_number() ! {
	if r.text[r.position] == `-` { r.position++ }
	start := r.position
	for r.position < r.text.len && r.text[r.position] >= `0` && r.text[r.position] <= `9` { r.position++ }
	if r.position == start || (r.position > start + 1 && r.text[start] == `0`) { return error('invalid package presentation extension number') }
	if r.position < r.text.len && r.text[r.position] == `.` {
		r.position++; fraction := r.position
		for r.position < r.text.len && r.text[r.position] >= `0` && r.text[r.position] <= `9` { r.position++ }
		if r.position == fraction { return error('invalid package presentation extension fraction') }
	}
	if r.position < r.text.len && r.text[r.position] in [u8(`e`), `E`]! {
		r.position++
		if r.position < r.text.len && r.text[r.position] in [u8(`+`), `-`]! { r.position++ }
		exponent := r.position
		for r.position < r.text.len && r.text[r.position] >= `0` && r.text[r.position] <= `9` { r.position++ }
		if r.position == exponent { return error('invalid package presentation extension exponent') }
	}
}

fn (mut r MetadataReader) skip_view_extension(depth int) ! {
	if depth > 32 { return error('package presentation extension exceeds nesting limit') }
	r.spaces()
	if r.position >= r.text.len { return error('incomplete package presentation extension') }
	byte := r.text[r.position]
	if byte == `"` { value := r.quoted(8 * 1024 * 1024)!; unsafe { value.free() }; return }
	if byte == `{` || byte == `[` {
		r.position++
		mut first := true
		for r.next(first, if byte == `{` { `}` } else { `]` })! {
			first = false
			if byte == `{` { key := r.quoted(8 * 1024 * 1024)!; unsafe { key.free() }; r.expect(`:`)! }
			r.skip_view_extension(depth + 1)!
		}
		return
	}
	if byte in [u8(`t`), `f`]! { r.boolean()!; return }
	if byte == `n` {
		if r.position + 4 > r.text.len || unsafe { tos(r.text.str + r.position, 4) } != 'null' { return error('invalid package presentation extension null') }
		r.position += 4
		return
	}
	if byte == `-` || (byte >= `0` && byte <= `9`) { r.skip_view_number()!; return }
	return error('invalid package presentation extension value')
}

fn (mut r MetadataReader) parse_software_row() !SoftwareRow {
	r.expect(`{`)!
	mut row := SoftwareRow{}
	mut accepted := false
	defer { if !accepted { close_software_row(row) } }
	mut seen := u32(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.view_member(software_row_keys, seen)!
		if member >= 0 { seen |= u32(1) << member }
		match member {
			0 { row = SoftwareRow{ ...row, id: r.quoted(128)! } }
			1 { row = SoftwareRow{ ...row, name: r.quoted(256)! } }
			2 { row = SoftwareRow{ ...row, description: r.quoted(4096)! } }
			3 { row = SoftwareRow{ ...row, version: r.quoted(29)! } }
			4 { row = SoftwareRow{ ...row, installed_version: r.quoted(29)! } }
			5 { row = SoftwareRow{ ...row, architecture: r.quoted(16)! } }
			6 { row = SoftwareRow{ ...row, kind: r.quoted(16)! } }
			7 { row = SoftwareRow{ ...row, runtime: r.quoted(128)! } }
			8 { row = SoftwareRow{ ...row, repository: r.quoted(128)! } }
			9 { row = SoftwareRow{ ...row, public_key: r.quoted(64)! } }
			10 { row = SoftwareRow{ ...row, license: r.quoted(256)! } }
			11 { row = SoftwareRow{ ...row, proprietary: r.boolean()! } }
			12 { row = SoftwareRow{ ...row, firmware: r.boolean()! } }
			13 { row = SoftwareRow{ ...row, permissions: r.strings(16, 5)! } }
			14 { row = SoftwareRow{ ...row, requested: r.boolean()! } }
			15 { row = SoftwareRow{ ...row, updatable: r.boolean()! } }
			16 { row = SoftwareRow{ ...row, update_action: r.quoted(16)! } }
			17 { row = SoftwareRow{ ...row, diagnostic: r.quoted(4096)! } }
			18 { row = SoftwareRow{ ...row, installed_name: r.quoted(256)! } }
			19 { row = SoftwareRow{ ...row, installed_kind: r.quoted(16)! } }
			20 { row = SoftwareRow{ ...row, installed_permissions: r.strings(16, 5)! } }
			21 { row = SoftwareRow{ ...row, installed_window_protocol: int(r.unsigned(2)!) } }
			else { r.skip_view_extension(0)! }
		}
	}
	if seen & 262143 != 262143 { return error('missing Software package field') }
	// SDK-1 services before installed launch columns, before window protocol,
	// and the current four-column group are the supported legacy shapes.
	if seen >> 18 !in [u32(0), 7, 15]! { return error('partial installed launch fields in Software view') }
	if seen >> 18 != 0 && row.installed_version != '' && (row.installed_name == '' || row.installed_kind == '') {
		return error('empty installed launch fields in Software view')
	}
	accepted = true
	return row
}

fn (mut r MetadataReader) parse_software_rows() ![]SoftwareRow {
	r.expect(`[` )!
	mut rows := []SoftwareRow{cap: 16}
	unsafe { rows.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { for row in rows { close_software_row(row) }; (&array(&rows)).free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if rows.len == 4096 { return error('Software view exceeds row limit') }
		row := r.parse_software_row()!
		pointer := unsafe { &row }
		unsafe { rows.push_many(pointer, 1) }
	}
	accepted = true
	return rows
}

fn (mut r MetadataReader) parse_software_view() !SoftwareView {
	r.expect(`{`)!
	mut view := SoftwareView{}
	mut accepted := false
	defer { if !accepted { view.close() } }
	mut seen := u32(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.view_member(software_view_keys, seen)!
		if member >= 0 { seen |= u32(1) << member }
		match member {
			0 { view = SoftwareView{ ...view, format: int(r.unsigned(1)!) } }
			1 { view = SoftwareView{ ...view, generation: r.unsigned(~u64(0))! } }
			2 { view = SoftwareView{ ...view, architecture: r.quoted(16)! } }
			3 { view = SoftwareView{ ...view, offline: r.boolean()! } }
			4 { view = SoftwareView{ ...view, catalog_error: r.quoted(4096)! } }
			5 { view = SoftwareView{ ...view, update_error: r.quoted(4096)! } }
			6 { view = SoftwareView{ ...view, rows: r.parse_software_rows()! } }
			7 { view = SoftwareView{ ...view, launch_user: r.quoted(32)! } }
			else { r.skip_view_extension(0)! }
		}
	}
	if seen != 255 { return error('missing Software view field') }
	view.validate()!
	accepted = true
	return view
}

pub fn decode_software_view(text string) !SoftwareView {
	if text.len > 8 * 1024 * 1024 { return error('Software view exceeds reply limit') }
	mut reader := &MetadataReader{ text: text }
	defer { unsafe { free(reader) } }
	mut view := reader.parse_software_view()!
	reader.spaces()
	if reader.position != text.len { view.close(); return error('trailing Software view metadata') }
	return view
}
