// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

import crypto.sha256
import json2
import tools.packages.pkgprotocol
import tools.packages.audiopcm

pub const action = 'packages-launch'
pub const request_limit = 512 * 1024 // JSON escaping preserves the 64 KiB literal command contract
pub const result_prefix = 'VINIX-PACKAGE-LAUNCH '

pub struct Request {
pub:
	format int = 1
	nonce string
	arguments []string
	display string
	authority string
	audio audiopcm.Capability
}

// Version one remains byte-for-byte compatible for non-X11 launches. Version
// two adds one fixed private display pair, never an arbitrary environment map.
struct LiteralRequest {
	format int = 1
	nonce string
	arguments []string
}

struct DisplayRequest {
	format int = 2
	nonce string
	arguments []string
	display string
	authority string
}

pub fn valid_nonce(value string) bool {
	if value.len != 32 { return false }
	for byte in value { if !((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`)) { return false } }
	return true
}

fn identifier(value string) bool {
	if value.len == 0 || value.len > 128 || value[0] < `a` || value[0] > `z` { return false }
	for byte in value { if !((byte >= `a` && byte <= `z`) || (byte >= `0` && byte <= `9`) || byte in [u8(`.`), `-`, `_`]!) { return false } }
	return true
}

// Only an installed package and its literal launch input can be selected. No
// executable, account, sandbox flag or administrative command.
pub fn validate_arguments(arguments []string) ! {
	if arguments.len < 2 || arguments.len > 772 || !identifier(arguments[1]) { return error('invalid isolated package launch') }
	if arguments[0] in ['run', 'run-terminal', 'run-window'] {
		pkgprotocol.validate_command_input([], arguments[2..])!
		return
	}
	if arguments[0] !in ['run-args', 'run-terminal-args'] { return error('isolated transport supports installed application launches only') }
	capacity := if arguments.len / 2 < pkgprotocol.command_argument_limit + 1 {
		arguments.len / 2
	} else { pkgprotocol.command_argument_limit + 1 }
	mut documents := []string{cap: capacity}
	unsafe { documents.flags |= .noslices }
	defer { unsafe { (&array(&documents)).free() } }
	mut at := 2
	mut data_cwd := false
	for at < arguments.len && arguments[at] != '--' {
		if arguments[at] == '--data-cwd' && !data_cwd { data_cwd = true; at++; continue }
		if arguments[at] != '--file' || at + 1 == arguments.len { return error('invalid isolated command launch options') }
		// Validation borrows paths. Ordinary string append clones their storage.
		unsafe { documents.push_many(&arguments[at + 1], 1) }
		if documents.len > pkgprotocol.command_argument_limit { return error('too many isolated launch documents') }
		at += 2
	}
	if at == arguments.len { return error('isolated command launch requires --') }
	pkgprotocol.validate_command_input(arguments[at + 1..], documents)!
}

pub fn (request &Request) encode() !string {
	if !valid_nonce(request.nonce) { return error('invalid isolated package request identity') }
	validate_arguments(request.arguments)!
	request.validate_display_shape()!
	request.validate_audio_shape()!
	mut bytes := []u8{cap: request_limit}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	if request.format == 1 {
		json2.encode_append(LiteralRequest{ nonce: request.nonce, arguments: request.arguments }, mut bytes)
	} else if request.format == 2 {
		json2.encode_append(DisplayRequest{ nonce: request.nonce, arguments: request.arguments, display: request.display, authority: request.authority }, mut bytes)
	} else { json2.encode_append(request, mut bytes) }
	text := bytes.bytestr()
	if text.len > request_limit { unsafe { text.free() }; return error('isolated package request is too large') }
	return text
}

pub fn decode(text string) !Request {
	if text.len == 0 || text.len > request_limit { return error('invalid isolated package request size') }
	return decode_request(text)
}

pub fn (request &Request) receipt(code int) string {
	text := request.encode() or { message := err.msg(); unsafe { message.free(); err.free() }; return '' }
	bytes := text.bytes()
	mut hash := sha256.new()
	mut checksum := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); checksum.free() } }
	hash.write(bytes) or { panic(err) }
	hash.checksum_into(mut checksum)
	digest := checksum.hex()
	number := code.str()
	defer { unsafe { text.free(); bytes.free(); digest.free(); number.free() } }
	return result_prefix + request.nonce + ' ' + digest + ' ' + number
}

pub fn (request &Request) result(text string) !int {
	if text.len > 128 { return error('isolated package completion receipt is invalid') }
	number := text.all_after_last(' ')
	defer { unsafe { number.free() } }
	if number.len == 0 || number.len > 3 { return error('invalid isolated package result code') }
	mut code := 0
	for byte in number {
		if byte < `0` || byte > `9` { return error('invalid isolated package result code') }
		code = code * 10 + int(byte - `0`)
	}
	if code > 255 { return error('invalid isolated package result code') }
	candidate := request.receipt(code)
	defer { unsafe { candidate.free() } }
	if text != candidate { return error('isolated package completion receipt is invalid') }
	return code
}

pub fn (mut request Request) close() {
	unsafe { request.nonce.free(); request.display.free(); request.authority.free(); request.audio.path.free(); request.audio.manifest.free(); for value in request.arguments { value.free() }; (&array(&request.arguments)).free() }
	request = Request{}
}
