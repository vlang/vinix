// SPDX-License-Identifier: GPL-2.0-or-later
// Recover a repeated raw archive only when it matches the original UART header.
// The ordinary strict collector must still validate the reconstructed transfer.
module main

import crypto.sha256
import encoding.base64
import json2
import os
import strconv

const prefix = 'VINIX-BROWSER-RESULTS-1 '
const archive_prefix = '{"version":1,"root_mode":'
const max_serial = 64 * 1024 * 1024
const max_archive = 32 * 1024 * 1024

fn recover_archive(serial string) !string {
	if serial.len > max_serial { return error('serial size limit') }
	mut digest := ''
	mut length := 0
	mut headers := 0
	for line in serial.split_into_lines() {
		if !line.starts_with(prefix + 'BEGIN ') { continue }
		fields := line.fields()
		if fields.len != 5 { return error('invalid original header') }
		digest = fields[2]
		if digest.len != 64 || digest.bytes().any(!((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))) {
			return error('invalid original digest')
		}
		length = strconv.atoi(fields[3])!
		chunks := strconv.atoi(fields[4])!
		if length <= 0 || length > max_archive || chunks != (length + 511) / 512 {
			return error('invalid original bounds')
		}
		headers++
	}
	if headers != 1 { return error('one original transfer header required') }
	mut matched := ''
	mut matches := 0
	mut offset := 0
	for offset < serial.len {
		relative := serial[offset..].index(archive_prefix) or { break }
		start := offset + relative
		if start + length <= serial.len {
			candidate := serial[start..start + length]
			if sha256.sum(candidate.bytes()).hex() == digest {
				matched = candidate
				matches++
			}
		}
		offset = start + 1
	}
	if matches != 1 { return error('one byte-exact repeated archive required') }
	return matched
}

fn framed(payload string) string {
	digest := sha256.sum(payload.bytes()).hex()
	bounds := digest + ' ' + payload.len.str() + ' ' + ((payload.len + 511) / 512).str() + '\n'
	mut result := prefix + 'BEGIN ' + bounds
	for offset := 0; offset < payload.len; offset += 512 {
		end := if offset + 512 < payload.len { offset + 512 } else { payload.len }
		result += prefix + 'CHUNK ' + digest + ' ' + (offset / 512).str() + ' ' +
			base64.encode(payload[offset..end].bytes()) + '\n'
	}
	return result + prefix + 'END ' + bounds
}

fn self_test() ! {
	payload := archive_prefix + '448,"entries":[]}'
	header := framed(payload).all_before('\n') + '\r\n'
	assert recover_archive(header + 'unrelated logs\r\n' + payload)! == payload
	for invalid in [payload, header, header + payload + payload, header + payload[..payload.len - 1],
		header + payload.replace('448', '449'), header + header + payload,
		header.replace('BEGIN ', 'BEGIN x') + payload, header.replace(' 1\r', ' 2\r') + payload] {
		if _ := recover_archive(invalid) { return error('invalid recovery accepted') }
	}
	println('BROWSER-EXPORT-RECOVERY-PASS exact-hash length unique-header unique-payload corrupt truncated')
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test()!; return }
	if os.args.len != 3 { return error('usage: recover-export SERIAL_LOG FRESH_EXTERNAL_RESULTS') }
	serial_path := os.real_path(os.args[1])
	if os.file_size(serial_path) > max_serial { return error('serial size limit') }
	serial := os.read_file(serial_path)!
	payload := recover_archive(serial)!
	root := os.abs_path(os.args[2])
	if os.exists(root) || os.real_path(os.dir(root)) != os.dir(root)
		|| root == '/Users/alex/code/vinix' || root.starts_with('/Users/alex/code/vinix/') {
		return error('fresh canonical external output required')
	}
	os.mkdir(root, mode: 0o700)!
	os.write_file(root + '/serial-original.log', serial)!
	os.write_file(root + '/archive.json', payload)!
	os.write_file(root + '/serial-reconstructed.log', framed(payload))!
	os.write_file(root + '/recovery.json', json2.encode({
		'kind': 'vinix-browser-raw-archive-recovery-v1'
		'serial_path': serial_path
		'serial_sha256': sha256.sum(serial.bytes()).hex()
		'archive_sha256': sha256.sum(payload.bytes()).hex()
		'archive_length': payload.len.str()
		'scope': 'Exact original archive retransmission; strict collector validation remains required.'
	}, prettify: true) + '\n')!
	println('BROWSER-EXPORT-RECOVERY-PASS ' + root)
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
