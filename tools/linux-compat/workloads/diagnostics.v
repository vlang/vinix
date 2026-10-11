// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

struct DiagnosticFile {
	path string
	content string
	truncated bool
	error string
}

struct DiagnosticSnapshot {
	phase string
	files []DiagnosticFile
}

// Proc files often report a size of zero. Read at most limit+1 bytes, retaining
// the extra byte only to distinguish exact-size data from a truncated result.
// Missing or unreadable diagnostics never replace the command's real failure.
fn diagnostic_file(path string, limit int) DiagnosticFile {
	mut file := os.open(path) or { return DiagnosticFile{path: path, error: err.msg()} }
	defer { file.close() }
	mut bytes := []u8{len: limit + 1}
	mut used := 0
	mut read_error := ''
	for used < bytes.len {
		n := file.read(mut bytes[used..]) or {
			if err !is os.Eof { read_error = err.msg() }
			break
		}
		if n <= 0 { break }
		used += n
	}
	return DiagnosticFile{path, bytes[..if used > limit { limit } else { used }].bytestr(), used > limit, read_error}
}

fn (suite Suite) diagnostic_snapshot(phase string, pid int) DiagnosticSnapshot {
	if suite.diagnostics_root == '' { return DiagnosticSnapshot{phase: phase} }
	mut files := []DiagnosticFile{}
	for name in ['meminfo', 'kernel-resources'] {
		files << diagnostic_file(suite.diagnostics_root + '/' + name, 8192)
	}
	if pid > 0 {
		base := suite.diagnostics_root + '/' + pid.str()
		files << diagnostic_file(base + '/status', 8192)
		files << diagnostic_file(base + '/maps', 32768)
		files << diagnostic_file(suite.diagnostics_root + '/slabinfo', 8192)
	}
	return DiagnosticSnapshot{phase, files}
}
