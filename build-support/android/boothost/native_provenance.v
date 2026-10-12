// SPDX-License-Identifier: GPL-2.0-or-later
module boothost

import androidhost as ah
import json2
import os

pub fn receipt_equal(left ah.Value, right ah.Value) bool { return equal(left, right) }

pub fn unicode_strip(value string) string { return strip_python(value) }

// Preserve the existing exact numeric and source-receipt policy while native
// producers supply SDK filesystem and DEX operations directly.
pub fn validate_native_provenance(root string, manifest ah.Value, payloads ah.Value, inspect fn (string) !ah.DexInfo) ! {
	c := constants()
	row := manifest.object()
	if manifest !is map[string]ah.Value || (integer_compare(ah.field(row, 'format'), 1) or { -1 }) != 0
		|| !equal(ah.field(row, 'inputs'), c['INPUTS']!) || !equal(ah.field(row, 'compiler_arguments'), c['COMPILER_ARGUMENTS']!)
		|| ah.field(row, 'compiler') !is string || !text(row, 'compiler').starts_with('D8 8.3.37 (build ') {
		return fail('bootclasspath provenance does not match the pinned compiler and inputs')
	}
	if !is_lower_hash(ah.field(row, 'input_key')) { return fail('bootclasspath provenance has an invalid input key') }
	files := ah.field(row, 'files')
	if files !is []ah.Value || files.items().len != c['BOOT_JARS']!.items().len { return fail('bootclasspath provenance must contain both Java boot libraries') }
	records := payload_records(payloads)!
	mut seen := []string{}
	allowed := c['BOOT_JARS']!.items().map(c['BOOT_DIRECTORY']!.text() + '/' + it.text())
	for value in files.items() {
		if value !is map[string]ah.Value { return fail('bootclasspath file receipt must be an object') }
		record := value.object()
		name := ah.field(record, 'path')
		if name !is string || name.text() !in allowed || name.text() in seen { return fail('bootclasspath provenance has an unexpected or duplicate library') }
		name_text := name.text()
		seen << name_text
		original := key(c['BOOT_ORIGINAL']!.object(), name_text.all_after_last('/'))!.object()
		for field, expected in original {
			if !equal(ah.field(record, field), expected) { return fail('bootclasspath provenance has a different source library: ' + name_text) }
		}
		for field in ['size', 'classes_before', 'classes_after', 'bootstrap_callsites_before', 'bootstrap_callsites_after'] {
			if integer_spelling(ah.field(record, field)) == none { return fail('bootclasspath provenance lost classes or retained bootstrap calls: ' + name_text) }
		}
		before := integer_spelling(key(record, 'classes_before')!) or { return fail('invalid class count') }
		after := integer_spelling(key(record, 'classes_after')!) or { return fail('invalid class count') }
		if (integer_compare(key(record, 'size')!, 0) or { -1 }) < 0 || (integer_compare(key(record, 'bootstrap_callsites_after')!, 0) or { -1 }) != 0 || signed_big(after)! < signed_big(before)! { return fail('bootclasspath provenance lost classes or retained bootstrap calls: ' + name_text) }
		if payloads !is json2.Null {
			if name_text !in records { return fail('bootclasspath receipt does not match the ART payload: ' + name_text) }
			for field in ['sha256', 'size'] {
				if !equal(ah.field((records[name_text] or { ah.Value(json2.null) }).object(), field), ah.field(record, field)) { return fail('bootclasspath receipt does not match the ART payload: ' + name_text) }
			}
		}
		if os.is_link(root) { return fail('bootclasspath payload must not use symlinks: ' + name_text) }
		mut parent := root
		for part in name_text.split('/') {
			parent = parent.trim_right('/') + '/' + part
			if os.is_link(parent) { return fail('bootclasspath payload must not use symlinks: ' + name_text) }
		}
		target := root.trim_right('/') + '/' + name_text
		if !os.is_file(target) { return fail('bootclasspath payload checksum mismatch: ' + name_text) }
		if !equal(ah.Value(os.stat(target)!.size), key(record, 'size')!) || ah.digest(target)! != ah.field(record, 'sha256').text() { return fail('bootclasspath payload checksum mismatch: ' + name_text) }
		info := inspect(target)!
		if (integer_compare(key(record, 'classes_after')!, u64(info.classes.len)) or { -1 }) != 0 || info.callsites != 0 { return fail('bootclasspath DEX does not match its compiler receipt: ' + name_text) }
	}
}
