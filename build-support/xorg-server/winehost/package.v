// SPDX-License-Identifier: GPL-2.0-or-later
module winehost

// Inspect borrowed execve strings without allocating or accepting another CLI
// operation. The account launcher still verifies the installed manifest, trust,
// policy, files and private display before executing the signed application.
fn package_token(value &char, expected string) bool {
	unsafe {
		if value == nil { return false }
		for index, byte in expected { if value[index] == 0 || u8(value[index]) != byte { return false } }
		return value[expected.len] == 0
	}
}

fn package_length(value &char, limit int, document bool) int {
	unsafe {
		if value == nil || (document && u8(value[0]) != `/`) { return -1 }
		for length := 0; length <= limit; length++ {
			byte := u8(value[length])
			if byte == 0 { return length }
			if document && (byte < 32 || byte == 127) { return -1 }
		}
	}
	return -1
}

pub fn package_command_allowed(argc i32, argv &&char) bool {
	unsafe {
		if argc < 3 || argc > 773 || argv == nil || !package_token(argv[0], '/usr/bin/vinix-package') { return false }
		id_length := package_length(argv[2], 128, false)
		if id_length < 1 || u8(argv[2][0]) < `a` || u8(argv[2][0]) > `z` { return false }
		for index in 0 .. id_length {
			byte := u8(argv[2][index])
			if !((byte >= `a` && byte <= `z`) || (byte >= `0` && byte <= `9`) || byte == `.` || byte == `-` || byte == `_`) { return false }
		}
		if package_token(argv[1], 'run') {
			return argc == 3 || (argc == 4 && package_length(argv[3], 4096, true) >= 0)
		}
		if !package_token(argv[1], 'run-args') { return false }
		mut at := 3
		mut data_cwd := false
		mut documents := 0
		mut bytes := 0
		for at < argc && !package_token(argv[at], '--') {
			if package_token(argv[at], '--data-cwd') && !data_cwd { data_cwd = true; at++; continue }
			if !package_token(argv[at], '--file') || at + 1 >= argc { return false }
			length := package_length(argv[at + 1], 4096, true)
			if length < 0 { return false }
			documents++; bytes += length + 1
			if documents > 256 || bytes > 65536 { return false }
			at += 2
		}
		if at == argc || argc - at - 1 > 256 { return false }
		at++
		for at < argc {
			length := package_length(argv[at], 4096, false)
			if length < 0 { return false }
			bytes += length + 1
			if bytes > 65536 { return false }
			at++
		}
		return true
	}
}
