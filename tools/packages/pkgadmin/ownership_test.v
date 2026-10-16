// SPDX-License-Identifier: GPL-2.0-or-later
module pkgadmin

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

const owner_nonce = '0123456789abcdef0123456789abcdef'
const owner_fingerprint = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
fn admin_error(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }
fn admin_window(label string) {
	$if track_heap ? {
		kept := C.vinix_heap_end(); assert kept == 0, kept.str()
		println('ADMIN ENVELOPE ' + label + ' retained 0 bytes PASS')
	} $else { println('ADMIN ENVELOPE ' + label + ' PASS') }
}
fn admin_requests() ![]Request {
	inputs := [
		['update'], ['--progress', 'update'], ['--progress', '--offline', 'apply', owner_fingerprint, 'install', 'example.app'],
		['apply', owner_fingerprint, 'remove', 'example.app'], ['apply', owner_fingerprint, 'upgrade'],
		['apply', owner_fingerprint, 'repair'], ['apply', owner_fingerprint, 'rollback'], ['cleanup-apply', owner_fingerprint],
		['repo-apply', owner_fingerprint, 'revoke', 'publisher'],
		['repo-apply', owner_fingerprint, 'enroll', 'publisher', 'file:///media/a space; $literal "quote" \\ 💡', owner_fingerprint],
		['deployment-apply', owner_fingerprint, '/etc/company/approved apps.json'],
		['policy-apply', owner_fingerprint, '/etc/company/policy.json'],
		['mirror-apply', owner_fingerprint, '/media/offline', 'example.app'],
		['mirror-deployment-apply', owner_fingerprint, '/media/offline', '/etc/company/lock.json'],
	]
	mut requests := []Request{cap: inputs.len + 2}
	for arguments in inputs {
		request := Request{ nonce: owner_nonce, arguments: arguments }
		unsafe { requests.push_many(&request, 1) }
	}
	unsafe { (&array(&inputs)).free() }
	mut batch := []string{cap: 69}
	for value in ['--progress', '--offline', 'apply', owner_fingerprint, 'install']! { unsafe { batch.push_many(&value, 1) } }
	for i in 0 .. 64 {
		number := i.str(); value := 'app-' + number
		unsafe { number.free(); batch.push_many(&value, 1) }
	}
	maximum := Request{ nonce: owner_nonce, arguments: batch }
	unsafe { requests.push_many(&maximum, 1) }
	seed := Request{ nonce: owner_nonce, arguments: ['policy-apply', owner_fingerprint, '/'] }
	text := seed.encode()!; size := request_limit - (text.len - 1)
	unsafe { text.free(); (&array(&seed.arguments)).free() }
	suffix := 'a'.repeat(size - 1); path := '/' + suffix
	unsafe { suffix.free() }
	boundary := Request{ nonce: owner_nonce, arguments: ['policy-apply', owner_fingerprint, path] }
	unsafe { requests.push_many(&boundary, 1) }
	return requests
}
fn admin_close_requests(mut requests []Request) {
	for mut request in requests { request.close() }
	unsafe { (&array(&requests)).free() }
}

fn test_owned_admin_envelopes_and_receipts_retire_storage() {
	mut requests := admin_requests()!; defer { admin_close_requests(mut requests) }
	assert requests.len == 16 && requests[14].arguments.len == 69
	// Prime only shared JSON type metadata outside the tracked window.
	text := requests[0].encode()!; mut warm := decode(text)!; warm.close(); unsafe { text.free() }
	for request in requests {
		$if track_heap ? { C.vinix_heap_begin() }
		for cycle in 0 .. 1000 {
			encoded := request.encode()!
			mut decoded := decode(encoded)!; mut sibling := decode(encoded)!
			unsafe { encoded.free() }
			decoded.close(); decoded.close()
			assert sibling.nonce == request.nonce && sibling.arguments == request.arguments
			codes := [0, 1, 37, 124, 126, 127, 143, 255]!
			code := codes[cycle % codes.len]
			receipt := sibling.receipt(code)
			assert request.result(receipt)! == code
			unsafe { receipt.free() }
			sibling.close(); sibling.close()
		}
		admin_window('16 reviewed commands/boundaries x1000 and eight statuses')
	}
	boundary := requests[15].encode()!; assert boundary.len == request_limit; unsafe { boundary.free() }
}

fn admin_malformed(text string) []string {
	return [text + '{}', text + ' ', ' ' + text,
		text.replace('"format":1', '"format":2'), text.replace('"format":1', '"format":"1"'),
		text.replace('"format":1', '"format":null'), text.replace('"format":1', '"format":1,"format":1'),
		text.replace('"format":1', '"format":1,"unknown":[]'), text.replace('"format":1', '"forma\\u0074":1'),
		text.replace('"arguments":[', '"arguments":[17,'), text.replace('"arguments":[', '"arguments":[{},'),
		text.replace('"arguments":[', '"arguments":[null,'), text.replace('"arguments":[', '"arguments":[[],'),
		text.replace('"arguments":[', '"arguments":[true,'), text.replace('"arguments":[', '"arguments":["\\q",'),
		text.replace('"arguments":[', '"arguments":["\\u0061",'), text.replace('"arguments":[', '"arguments":["\\/",'),
		text.replace('"nonce":"0', '"nonce":"F'), text.replace('"nonce":"0', '"nonce":"00'),
		text.replace('"policy-apply"', '"run"'), text.replace('/etc/company/policy.json', '/bad\\u0000name'),
		text.replace('/etc/company/policy.json', '/bad\\nname'), text.replace('/etc/company/policy.json', '/bad\x7fname'),
		text.replace('/etc/company/policy.json', '/bad\x01name'), text.replace(']}', ',]}'),
		'{"format":1,"nonce":"0123456789abcdef0123456789abcdef","arguments":[]}',
		'{"format":1,"nonce":"0123456789abcdef0123456789abcdef","arguments":' + '['.repeat(1000) + '0' + ']'.repeat(1000) + '}',
		'x'.repeat(request_limit + 1)]
}
fn test_partial_and_noncanonical_admin_requests_retire_every_field() {
	mut requests := admin_requests()!; defer { admin_close_requests(mut requests) }
	encoded := requests[11].encode()!; defer { unsafe { encoded.free() } }
	mut invalid := admin_malformed(encoded); defer { unsafe { invalid.free() } }
	assert invalid.len == 28
	// Every truncated prefix of the largest legal request, including late
	// failures after an owned nonce and partially decoded strings.
	maximum := requests[15].encode()!; defer { unsafe { maximum.free() } }
	$if track_heap ? { C.vinix_heap_begin() }
	for cut in 0 .. maximum.len {
		if mut decoded := decode(unsafe { tos(maximum.str, cut) }) { decoded.close(); assert false } else { admin_error(err) }
	}
	admin_window('all 4096 truncated prefixes')
	for text in invalid {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			if mut decoded := decode(text) { decoded.close(); assert false } else { admin_error(err) }
		}
		admin_window('28 malformed/schema/limit paths x1000')
	}
	// clone() copies the table but borrows these string values. Retire only
	// that table; the original requests still own the application names.
	mut too_many := requests[14].arguments.clone()
	extra := 'another'
	unsafe { too_many.flags |= .noslices; too_many.push_many(&extra, 1) }
	defer { unsafe { (&array(&too_many)).free() } }
	oversized := maximum.replace(']}', '"]}')
	defer { unsafe { oversized.free() } }
	bad := Request{ nonce: owner_nonce, arguments: too_many }
	long_path := requests[15].arguments[2] + 'a'
	overflow := Request{ nonce: owner_nonce, arguments: ['policy-apply', owner_fingerprint, long_path] }
	defer { unsafe { long_path.free(); (&array(&overflow.arguments)).free() } }
	batch := requests[14].encode()!; many := batch.replace(']}', ',"another"]}')
	defer { unsafe { batch.free(); many.free() } }
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		if value := bad.encode() { unsafe { value.free() }; assert false } else { admin_error(err) }
		assert bad.receipt(0) == ''
		if value := overflow.encode() { unsafe { value.free() }; assert false } else { admin_error(err) }
		assert overflow.receipt(0) == ''
		if mut decoded := decode(many) { decoded.close(); assert false } else { admin_error(err) }
		if mut decoded := decode(oversized) { decoded.close(); assert false } else { admin_error(err) }
	}
	admin_window('excess arguments, oversized encode/decode and invalid receipt construction x1000')
}

fn test_admin_receipt_refusals_retire_hash_and_error_scratch() {
	mut requests := admin_requests()!; defer { admin_close_requests(mut requests) }
	request := requests[2]
	text := request.encode()!; unsafe { text.free() }
	receipt := request.receipt(0); defer { unsafe { receipt.free() } }
	prefix := receipt[..receipt.len - 1]; defer { unsafe { prefix.free() } }
	other := ['update']; defer { unsafe { (&array(&other)).free() } }
	bad := [prefix + '00', prefix + '01', prefix + '-1', prefix + '256', prefix + '1x', prefix + ' 1',
		receipt + '\n', receipt + ' extra', receipt.replace(owner_nonce, 'ffffffffffffffffffffffffffffffff'),
		Request{ nonce: owner_nonce, arguments: other }.receipt(0), '', 'x'.repeat(16385)]
	defer { unsafe { bad.free() } }
	for value in bad {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			if _ := request.result(value) { assert false } else { admin_error(err) }
		}
		admin_window('12 invalid completion paths x1000')
	}
}
