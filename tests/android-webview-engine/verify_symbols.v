// SPDX-License-Identifier: GPL-2.0-or-later
// Offline ABI audit of the pinned AArch64 runtime, without loading foreign code.
import crypto.sha256
import encoding.hex
import json2
import os

struct Audit {
	format            int = 1
	api_sha256        string
	cookie_api_sha256 string
	libraries         map[string]string
	symbol_count      int
}

fn digest(path string) !string {
	bytes := os.read_bytes(path)!
	return hex.encode(sha256.sum(bytes))
}

fn run() ! {
	if os.args.len !in [5, 6] {
		return error('usage: verify_symbols NM RUNTIME_ROOTS_COLON_SEPARATED API_SOURCE OUTPUT_JSON [COOKIE_API_SOURCE]')
	}
	nm, runtime, source, output := os.args[1], os.args[2], os.args[3], os.args[4]
	cookie_source := if os.args.len == 6 { os.args[5] } else { '' }
	text := os.read_file(source)! + if cookie_source != '' {
		os.read_file(cookie_source)!
	} else {
		''
	}
	mut required := map[string]bool{}
	for suffix in text.split('dl.sym_opt(')[1..] {
		name := suffix.all_after("'").all_before("'")
		if name == '' || name.contains_any('\n\r\x00') {
			return error('invalid API symbol declaration')
		}
		required[name] = true
	}
	if required.len < 50 { return error('incomplete engine API inventory') }
	mut available := map[string]bool{}
	mut pins := map[string]string{}
	mut libraries := ['libwebkitgtk-6.0.so.4', 'libgtk-4.so.1', 'libgobject-2.0.so.0',
		'libglib-2.0.so.0', 'libsoup-3.0.so.0', 'libX11.so.6', 'libXtst.so.6']
	if cookie_source != '' { libraries << 'libsqlite3.so.0' }
	for library in libraries {
		mut paths := []string{}
		for root in runtime.split(':') {
			candidate := root + '/usr/lib/' + library
			if os.exists(candidate) { paths << candidate }
		}
		if paths.len != 1 { return error('library missing or ambiguous: ' + library) }
		path := paths[0]
		pins[library] = digest(path)!
		mut process := os.new_process(nm)
		process.set_args(['-D', '--defined-only', path])
		process.set_redirect_stdio()
		process.run()
		stdout := process.stdout_slurp()
		stderr := process.stderr_slurp()
		process.wait()
		if process.code != 0 {
			return error('symbol tool failed for ${library}: ${stderr.trim_space()}')
		}
		for line in stdout.split_into_lines() {
			words := line.fields()
			if words.len >= 3 { available[words.last().all_before('@')] = true }
		}
		process.close()
	}
	mut missing := []string{}
	for name, _ in required { if name !in available { missing << name } }
	missing.sort()
	if missing.len != 0 { return error('missing pinned API exports: ' + missing.join(', ')) }
	os.write_file(output, json2.encode(Audit{
		api_sha256:        digest(source)!
		cookie_api_sha256: if cookie_source != '' { digest(cookie_source)! } else { '' }
		libraries:         pins
		symbol_count:      required.len
	}, prettify: true) + '\n')!
	println('PASS: ${required.len} engine API symbols exported by pinned libraries')
}

run() or {
	eprintln(err)
	exit(1)
}
