// SPDX-License-Identifier: GPL-2.0-or-later
// Checked interpreter source generator; see maps-art-mterp-20261114.md.
// Native compilation and runtime validation remain pending.
module main

import artmterp
import crypto.sha256
import json2
import os

fn check_source(header string, directory string, output string) ! {
	os.mkdir(output)!
	mut names := os.ls(directory)!.filter(it.ends_with('.S'))
	names.sort()
	if names != ['arithmetic.S', 'array.S', 'control_flow.S', 'floating_point.S',
		'invoke.S', 'main.S', 'object.S', 'other.S'] {
		return error('expected the eight ARM64 interpreter templates')
	}
	mut paths := [header]
	for name in names { paths << directory + '/' + name }
	mut records := []map[string]string{}
	for path in paths {
		records << {'path': path, 'sha256': sha256.sum(os.read_bytes(path)!).hex()}
	}
	text := artmterp.mterp(os.read_file(header)!, paths[1..])!
	for record in records {
		if record['sha256'] != sha256.sum(os.read_bytes(record['path'])!).hex() {
			return error('interpreter input changed during generation')
		}
	}
	lines := text.split_into_lines()
	mut labels := map[string]bool{}
	for line in lines {
		if line.starts_with('.L_op_') && line.contains(': /* 0x') && line.ends_with(' */') {
			label := line.all_before(':')
			if label in labels { return error('duplicate packed opcode label') }
			labels[label] = true
		}
	}
	if labels.len != 256 { return error('expected all 256 packed opcode labels') }
	os.write_file(output + '/mterp_arm64.S', text)!
	os.write_file(output + '/inputs.json', json2.encode(records, prettify: true) + '\n')!
	os.write_file(output + '/output.sha256', sha256.sum(text.bytes()).hex() + '  mterp_arm64.S\n')!
	println('ART-MTERP-SOURCE-PASS templates=8 opcodes=256 bytes=${text.len}')
}

fn main() {
	if os.args.len == 5 && os.args[1] == '--check-source' {
		check_source(os.args[2], os.args[3], os.args[4]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 3 && os.args[1] == '--self-test' {
		artmterp.check_mterp(os.abs_path(os.args[2])) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len < 3 {
		eprintln('usage: art-mterp OPCODE_HEADER TEMPLATE... | --self-test FRESH_ROOT')
		exit(2)
	}
	input := os.read_file(os.args[1]) or { eprintln(err); exit(1) }
	output := artmterp.mterp(input, os.args[2..]) or { eprintln(err); exit(1) }
	print(output)
}
