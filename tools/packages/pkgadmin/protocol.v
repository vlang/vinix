// SPDX-License-Identifier: GPL-2.0-or-later
module pkgadmin

import crypto.sha256
import json2

pub const action = 'packages-change'
pub const request_limit = 4096
pub const password_limit = 256
pub const result_prefix = 'VINIX-PACKAGE-ADMIN '

pub struct Request {
pub:
	format int = 1
	nonce string
	arguments []string
}

fn hex(value string, length int) bool {
	if value.len != length { return false }
	for byte in value { if !((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`)) { return false } }
	return true
}

fn identifier(value string) bool {
	if value.len == 0 || value.len > 128 || value[0] < `a` || value[0] > `z` { return false }
	for byte in value { if !((byte >= `a` && byte <= `z`) || (byte >= `0` && byte <= `9`) || byte in [u8(`.`), `-`, `_`]!) { return false } }
	return true
}

fn path(value string) bool { return value.starts_with('/') && printable(value) }
fn printable(value string) bool {
	if value.len == 0 || value.len > 4096 { return false }
	for byte in value { if byte < 32 || byte == 127 { return false } }
	return true
}

// Authorization is for reviewed administration only. No executable, alternate
// root, publisher tooling, raw transaction, shell, or application launch crosses.
pub fn validate_arguments(arguments []string) ! {
	if arguments.len == 0 || arguments.len > 69 { return error('invalid administrator package argument count') }
	mut at := 0
	if arguments[at] == '--progress' { at++ }
	if at < arguments.len && arguments[at] == '--offline' { at++ }
	if at == arguments.len { return error('an administrator package command is required') }
	args := unsafe { arguments[at..] }
	for value in args { if !printable(value) { return error('invalid administrator package argument') } }
	command := args[0]
	if command == 'update' && args.len == 1 { return }
	if args.len < 2 || !hex(args[1], 64) { return error('administrator package changes require their exact review fingerprint') }
	match command {
		'apply' {
			if args.len >= 4 && args[2] in ['install', 'remove'] && args[3..].all(identifier(it)) { return }
			if args.len == 3 && args[2] in ['upgrade', 'repair', 'rollback'] { return }
		}
		'repo-apply' {
			if args.len == 4 && args[2] == 'revoke' && identifier(args[3]) { return }
			if args.len == 6 && args[2] == 'enroll' && identifier(args[3]) && printable(args[4]) && hex(args[5], 64) { return }
		}
		'deployment-apply', 'policy-apply' { if args.len == 3 && path(args[2]) { return } }
		'mirror-apply' { if args.len >= 4 && path(args[2]) && args[3..].all(identifier(it)) { return } }
		'mirror-deployment-apply' { if args.len == 4 && path(args[2]) && path(args[3]) { return } }
		else {}
	}
	return error('unsupported or unreviewed administrator package operation')
}

pub fn administrative(arguments []string) bool {
	return arguments.len > 0 && arguments[0] in ['update', 'apply', 'repo-apply', 'deployment-apply', 'policy-apply', 'mirror-apply', 'mirror-deployment-apply']
}

pub fn (request &Request) encode() !string {
	if request.format != 1 || !hex(request.nonce, 32) { return error('invalid administrator package request identity') }
	validate_arguments(request.arguments)!
	mut bytes := []u8{cap: request_limit}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(request, mut bytes)
	text := bytes.bytestr()
	if text.len > request_limit { unsafe { text.free() }; return error('administrator package request exceeds 4096 bytes') }
	return text
}

pub fn decode(text string) !Request {
	if text.len == 0 || text.len > request_limit { return error('invalid administrator package request size') }
	mut request := json2.decode[Request](text)!
	mut accepted := false
	defer { if !accepted { request.close() } }
	canonical := request.encode()!
	defer { unsafe { canonical.free() } }
	// Canonical transport refuses unknown/duplicate/escaped keys and trailing
	// data even if the general decoder would otherwise ignore them.
	if canonical != text { return error('administrator package request is not canonical') }
	accepted = true
	return request
}

pub fn (request &Request) receipt(code int) string {
	encoded := request.encode() or { return '' }
	bytes := encoded.bytes()
	digest := sha256.sum(bytes).hex()
	number := code.str()
	defer { unsafe { encoded.free(); bytes.free(); digest.free(); number.free() } }
	return result_prefix + request.nonce + ' ' + digest + ' ' + number
}

pub fn (request &Request) result(line string) !int {
	encoded := request.encode()!
	bytes := encoded.bytes()
	digest := sha256.sum(bytes).hex()
	prefix := result_prefix + request.nonce + ' ' + digest + ' '
	defer { unsafe { encoded.free(); bytes.free(); digest.free(); prefix.free() } }
	if line.starts_with(prefix) {
		number := unsafe { tos(line.str + prefix.len, line.len - prefix.len) }
		if number.len >= 1 && number.len <= 3 && (number.len == 1 || number[0] != `0`) {
			mut value := 0
			for byte in number {
				if byte < `0` || byte > `9` { return error('invalid administrator package result code') }
				value = value * 10 + int(byte - `0`)
			}
			if value < 256 { return value }
		}
	}
	return error('administrator package completion receipt is invalid')
}

pub fn (mut request Request) close() {
	unsafe {
		request.nonce.free()
		for value in request.arguments { value.free() }
		(&array(&request.arguments)).free()
	}
	request = Request{}
}
