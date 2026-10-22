// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import strings
import time

struct Pin {
	path string
	sha256 string
}

fn check(program string, pins string, archive string, prefix string, name string, accepted bool, mut report strings.Builder) ! {
	mut child := os.new_process(program)
	child.set_args(['--check-inputs', pins, archive, prefix])
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	code := child.code
	child.close()
	if (code == 0) != accepted {
		return error(name + ': unexpected exit ' + code.str() + '\n' + output)
	}
	if accepted && !output.contains('GUEST TLS historical input evidence PASS') {
		return error(name + ': missing historical input evidence completion\n' + output)
	}
	report.writeln(name + if accepted { ' accepted PASS' } else { ' refused PASS' })
}

fn run() ! {
	if os.args.len !in [2, 3] {
		return error('usage: https-runtime-input-check RETAINER_BINARY [REPORT]')
	}
	work := os.join_path(os.temp_dir(), 'vinix-tls-inputs-' + os.getpid().str() + '-' + time.now().unix_milli().str())
	os.mkdir(work, mode: 0o700)!
	defer { os.rmdir_all(work) or {} }
	os.mkdir(work + '/source')!
	os.mkdir(work + '/archive')!
	path := work + '/source/input.v'
	archive := work + '/archive'
	pins := work + '/pins.json'
	prefix := work + '/source/'
	original := 'module original\n'
	hash := sha256.hexhash(original)
	os.write_file(path, original)!
	os.write_file(pins, json2.encode([Pin{path: path, sha256: hash}]))!
	mut report := strings.new_builder(1024)
	check(os.args[1], pins, archive, prefix, 'matching-current', true, mut report)!
	os.write_file(path, 'module changed\n')!
	check(os.args[1], pins, archive, prefix, 'changed-without-archive', false, mut report)!
	os.write_file(archive + '/' + hash, original)!
	check(os.args[1], pins, archive, prefix, 'exact-historical-copy', true, mut report)!
	check(os.args[1], pins, archive, prefix + 'other/', 'outside-source-prefix', false, mut report)!
	os.rm(path)!
	check(os.args[1], pins, archive, prefix, 'missing-current-exact-copy', true, mut report)!
	os.write_file(archive + '/' + hash, 'module corrupt\n')!
	check(os.args[1], pins, archive, prefix, 'corrupt-copy', false, mut report)!
	os.rm(archive + '/' + hash)!
	check(os.args[1], pins, archive, prefix, 'missing-copy', false, mut report)!
	for index, invalid in ['../' + hash, hash.to_upper(), hash[..63]] {
		os.write_file(pins, json2.encode([Pin{path: path, sha256: invalid}]))!
		check(os.args[1], pins, archive, prefix, ['digest-traversal', 'uppercase-digest', 'short-digest'][index], false, mut report)!
	}
	report.writeln('GUEST TLS historical input controls PASS')
	text := report.str()
	print(text)
	if os.args.len == 3 { os.write_file(os.args[2], text)! }
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
