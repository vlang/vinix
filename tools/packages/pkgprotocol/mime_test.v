// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn test_mime_associations_accept_bare_vendor_suffix_and_scheme_names() {
	for value in ['a/b', 'text/plain', 'Text/Plain', 'application/vnd.example.editor+json',
		'application/x-vinix', 'x-scheme-handler/https', '1/2', 'a/b!#$&-^_.+',
		'a/' + 'b'.repeat(126), 'a'.repeat(126) + '/b'] {
		if !valid_mime_association(value) { panic('valid bare MIME association refused: ' + value) }
	}
}

fn test_mime_associations_refuse_empty_parts_parameters_escapes_and_ambiguous_lists() {
	for value in ['', '/', 'text', 'text/', '/plain', 'text/plain/extra', 'text//plain',
		'text/plain;', 'text/plain;application/json', 'text/plain;charset=utf-8',
		'text=plain/other', 'text/plain other', ' text/plain', 'text/plain ', 'text /plain',
		'text/ plain', 'text/pl\\ain', 'text/pl\\sain', 'text/pl\nain', 'text/pl\tain',
		'text/pl\x00ain', 'text/pl\x7fain', 'text/é', 'text/😀', '*/plain', 'text/*',
		'text/.plain', '-text/plain', 'text/+json', 'text/pl%ain', 'text/pl\'ain',
		'text/"plain"', 'text/(plain)', 'a/' + 'b'.repeat(127)] {
		if valid_mime_association(value) { panic('invalid bare MIME association accepted: ' + value) }
	}
}

fn test_mime_scans_preserve_borrowed_bytes_without_retained_allocations() {
	values := ['application/vnd.example.editor+json'.clone(), 'text/plain/extra'.clone()]
	defer { unsafe { values.free() } }
	mut accepted := 0
	mut refused := 0
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 10000 {
		if valid_mime_association(values[0]) { accepted++ }
		if !valid_mime_association(values[1]) { refused++ }
	}
	$if track_heap ? {
		kept := C.vinix_heap_end()
		count := C.vinix_heap_count()
		if kept != 0 || count != 0 { panic('MIME scan retained tracked allocations') }
	}
	if accepted != 10000 || refused != 10000 || values[0] != 'application/vnd.example.editor+json'
		|| values[1] != 'text/plain/extra' { panic('MIME scans changed borrowed input or skipped work') }
	println('MIME 20000 scans preserve input; tracked build requires zero retained bytes and records PASS')
}
