// SPDX-License-Identifier: GPL-2.0-or-later
module javacacerts

import crypto.sha1
import crypto.sha256
import encoding.utf8
import os

const pem_begin = '-----BEGIN CERTIFICATE-----'
const pem_end = '-----END CERTIFICATE-----'

fn append_be(mut output []u8, value u64, width int) {
	for offset in 0 .. width {
		output << u8(value >> (8 * (width - offset - 1)))
	}
}

// JKS uses Java's UTF-16 code units for the password digest, including a
// surrogate pair for each supplementary character. Invalid UTF-8 is rejected.
pub fn password_bytes(password string) ![]u8 {
	if !utf8.validate_str(password) { return error('password is not valid UTF-8') }
	mut output := []u8{}
	for character in password.runes() {
		value := u32(character)
		if value <= 0xffff {
			append_be(mut output, value, 2)
		} else {
			append_be(mut output, 0xd800 + ((value - 0x10000) >> 10), 2)
			append_be(mut output, 0xdc00 + ((value - 0x10000) & 0x3ff), 2)
		}
	}
	return output
}

fn append_utf(mut output []u8, value string) ! {
	if value.len > 0xffff { return error('JKS string is too long') }
	append_be(mut output, u64(value.len), 2)
	output << value.bytes()
}

pub fn build_jks(certificates [][]u8, password string) ![]u8 {
	mut checksum_input := password_bytes(password)!
	checksum_input << 'Mighty Aphrodite'.bytes()
	mut body := []u8{}
	append_be(mut body, 0xfeedfeed, 4)
	append_be(mut body, 2, 4)
	append_be(mut body, u64(certificates.len), 4)
	for certificate in certificates {
		append_be(mut body, 2, 4)
		append_utf(mut body, sha256.sum(certificate).hex())!
		append_be(mut body, 0, 8)
		append_utf(mut body, 'X.509')!
		append_be(mut body, u64(certificate.len), 4)
		body << certificate
	}
	checksum_input << body
	body << sha1.sum(checksum_input)
	return body
}

fn base64_value(character u8) int {
	return match character {
		`A`...`Z` { int(character - `A`) }
		`a`...`z` { int(character - `a`) + 26 }
		`0`...`9` { int(character - `0`) + 52 }
		`+` { 62 }
		`/` { 63 }
		else { -1 }
	}
}

// Preserve the original non-strict PEM decoder: ignore non-alphabet bytes,
// tolerate leading/interior padding, stop at sufficient terminal padding,
// and reject an incomplete unpadded quartet.
pub fn decode_pem(payload []u8) ![]u8 {
	mut output := []u8{cap: payload.len / 4 * 3}
	mut position := 0
	mut previous := u32(0)
	mut padding := 0
	for character in payload {
		if character == `=` {
			if position >= 2 {
				padding++
				if position + padding >= 4 { return output }
			}
			continue
		}
		decoded := base64_value(character)
		if decoded < 0 { continue }
		value := u32(decoded)
		padding = 0
		match position {
			0 { previous = value }
			1 {
				output << u8((previous << 2) | (value >> 4))
				previous = value & 15
			}
			2 {
				output << u8((previous << 4) | (value >> 2))
				previous = value & 3
			}
			3 {
				output << u8((previous << 6) | value)
				previous = 0
			}
			else {}
		}
		position = (position + 1) % 4
	}
	if position == 1 { return error('invalid base64 certificate: data length is 1 modulo 4') }
	if position != 0 { return error('invalid base64 certificate: incorrect padding') }
	return output
}

pub fn parse_pem(data []u8) ![][]u8 {
	text := data.bytestr()
	mut certificates := [][]u8{}
	mut offset := 0
	for offset < text.len {
		begin := text.index_after(pem_begin, offset) or { break }
		start := begin + pem_begin.len
		end := text.index_after(pem_end, start) or { break }
		certificates << decode_pem(data[start..end])!
		offset = end + pem_end.len
	}
	return certificates
}

pub fn read_certificates(directory string) ![][]u8 {
	mut certificates := [][]u8{}
	if os.is_dir(directory) {
		mut names := os.ls(directory)!
		names.sort()
		for name in names {
			if name.ends_with('.crt') {
				certificates << parse_pem(os.read_bytes(os.join_path(directory, name))!)!
			}
		}
	}
	if certificates.len == 0 { return error('no PEM certificates found in ${directory}') }
	return certificates
}

fn generate(directory string, output string, password string) ! {
	certificates := read_certificates(directory)!
	data := build_jks(certificates, password)!
	os.mkdir_all(os.dir(output))!
	os.write_file_array(output, data)!
	println('wrote ${certificates.len} certificates to ${output}')
}

fn option_value(value string) bool {
	if !value.starts_with('-') || value == '-' { return true }
	number := value[1..]
	if number != '' && number.bytes().all(it.is_digit()) { return true }
	return number.count('.') == 1 && number.all_after('.').len > 0
		&& number.all_before('.').bytes().all(it.is_digit())
		&& number.all_after('.').bytes().all(it.is_digit())
}

pub fn run(args []string) int {
	mut positional := []string{}
	mut password := 'changeit'
	mut options := true
	mut index := 0
	for index < args.len {
		argument := args[index]
		if options && argument in ['-h', '--help'] {
			println('Usage: java-cacerts CERTIFICATES OUTPUT [--password PASSWORD]')
			return 0
		} else if options && argument == '--' {
			options = false
		} else if options && argument.starts_with('--') && argument.all_before('=').len > 2
			&& '--password'.starts_with(argument.all_before('=')) {
			if argument.contains('=') {
				password = argument.all_after('=')
			} else {
				index++
				if index >= args.len || !option_value(args[index]) {
					eprintln('java-cacerts: --password requires a value')
					return 2
				}
				password = args[index]
			}
		} else if options && !option_value(argument) {
			eprintln('java-cacerts: unknown option ${argument}')
			return 2
		} else {
			positional << argument
		}
		index++
	}
	if positional.len != 2 {
		eprintln('Usage: java-cacerts CERTIFICATES OUTPUT [--password PASSWORD]')
		return 2
	}
	generate(positional[0], positional[1], password) or {
		eprintln('java-cacerts: ${err}')
		return 1
	}
	return 0
}
