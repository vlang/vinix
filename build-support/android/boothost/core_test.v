module boothost

import androidhost as ah
import json2
import os

fn test_python_receipt_equality_keeps_wide_integers_and_float_types() {
	corpus := json2.decode[ah.Value](os.read_file(os.dir(@FILE) + '/testdata/equality.json') or { panic(err) },
		strict: true
	) or { panic(err) }
	for row in ah.field(corpus.object(), 'cases').items() {
		fields := row.object()
		assert equal(ah.field(fields, 'left'), ah.field(fields, 'right')) == ah.field(fields, 'equal') as bool
	}
}

fn test_version_strip_uses_python_unicode_whitespace() {
	assert strip_python('\u0085\u001c\u3000D8 8.3.37 (build fixture)\u2000\n') == 'D8 8.3.37 (build fixture)'
	assert strip_python('\u200bD8\u200b') == '\u200bD8\u200b'
}

fn test_class_archive_order_compares_path_components() {
	mut names := ['/classes/a-foo/Other.class', '/classes/a/One.class', '/classes/a-z.class']
	names.sort_with_compare(fn (a &string, b &string) int { return path_order(*a, *b) })
	assert names == ['/classes/a/One.class', '/classes/a-foo/Other.class', '/classes/a-z.class']
}

fn test_strict_integer_fields_accept_signed_zero_and_reject_booleans_and_floats() {
	assert (integer_compare(ah.Value(ah.Number{'-0'}), 0) or { panic('missing integer') }) == 0
	assert integer_spelling(ah.Value(true)) == none
	assert integer_spelling(ah.Value(ah.Number{'0.0'})) == none
	assert integer_spelling(ah.Value(ah.Number{'1e0'})) == none
	assert (integer_compare(ah.Value(ah.Number{'10000000000000000000000000000000000000000'}), 1) or { panic('missing integer') }) == 1
	assert (integer_compare(ah.Value(ah.Number{'-10000000000000000000000000000000000000000'}), 0) or { panic('missing integer') }) == -1
}
