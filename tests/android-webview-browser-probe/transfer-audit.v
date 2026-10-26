// SPDX-License-Identifier: GPL-2.0-or-later
// Freeze and recheck the selected V source closures around narrow tool builds.
module main

import browsertransfer
import json2
import os

const audit_scope = 'Target-selected V sources and selected compiler binaries; C headers, sysroots, linked libraries and transitive compiler executables are not a hermetic closure.'
const tool_paths = ['/Users/alex/code/v/v', '/Users/alex/code/v-tccbin-bootstrap-20261026/v', '/opt/homebrew/bin/aarch64-linux-musl-gcc']
const source_kinds = ['host', 'guest', 'collector', 'selftest', 'audit']

struct Input {
	path string
	frozen string
	sha256 string
}

struct Audit {
	format int = 1
	scope string = audit_scope
	inputs []Input
	tools map[string]string
}

fn schema(audit Audit) ! {
	if audit.format != 1 || audit.scope != audit_scope || audit.inputs.len == 0
		|| audit.inputs.len > 10240 || audit.tools.len != tool_paths.len {
		return error('complete bounded V closure receipt required')
	}
	for path in tool_paths {
		if path !in audit.tools { return error('missing selected compiler pin') }
		browsertransfer.expected(audit.tools[path], '1')!
	}
	for input in audit.inputs {
		parts := input.frozen.split('/')
		if !input.path.starts_with('/') || parts.len != 3 || parts[0] != 'closure'
			|| parts[1] !in source_kinds || input.frozen.contains('..') {
			return error('invalid closure input path')
		}
		browsertransfer.expected(input.sha256, '1')!
	}
}

fn run() ! {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		mut rejected := false
		schema(json2.decode[Audit]('{}')!) or { rejected = true }
		assert rejected, 'empty closure accepted'
		mut pins := map[string]string{}
		for path in tool_paths { pins[path] = 'a'.repeat(64) }
		valid := Audit{inputs: [Input{'/absolute/source.v', 'closure/host/0.v', 'b'.repeat(64)}], tools: pins}
		schema(valid)!
		rejected = false
		schema(Audit{...valid, format: 2}) or { rejected = true }
		assert rejected, 'wrong schema accepted'
		pins.delete(tool_paths[0])
		rejected = false
		schema(Audit{...valid, tools: pins}) or { rejected = true }
		assert rejected, 'missing compiler accepted'
		println('BROWSER-TCP CLOSURE SELF-TEST PASS empty-receipt wrong-format missing-compiler')
		return
	}
	if os.args.len != 3 || os.args[1] !in ['freeze', 'check'] { return error('usage: transfer-audit freeze|check BUILD_ROOT') }
	root := os.args[2]
	if os.args[1] == 'freeze' {
		os.mkdir(root + '/closure')!
		mut inputs := []Input{}
		for kind in source_kinds {
			list := root + '/' + kind + '-v-files.txt'
			if os.file_size(list) > 256 * 1024 { return error('source closure list limit') }
			lines := os.read_lines(list)!
			if lines.len == 0 || lines.len > 2048 { return error('source closure count limit') }
			os.mkdir(root + '/closure/' + kind)!
			for index, path in lines {
				if !path.starts_with('/') || os.lstat(path)!.get_filetype() != .regular || os.file_size(path) > 2 * 1024 * 1024 {
					return error('bounded regular absolute V input required')
				}
				sha := browsertransfer.file_hash(path)!
				frozen := 'closure/' + kind + '/' + index.str() + '.v'
				os.cp(path, root + '/' + frozen)!
				if browsertransfer.file_hash(root + '/' + frozen)! != sha || browsertransfer.file_hash(path)! != sha {
					return error('V input changed while freezing')
				}
				inputs << Input{path, frozen, sha}
			}
		}
		mut tools := map[string]string{}
		for path in tool_paths {
			tools[path] = browsertransfer.file_hash(path)!
		}
		os.write_file(root + '/closure.json', json2.encode(Audit{inputs: inputs, tools: tools}, prettify: true) + '\n')!
	} else {
		if os.lstat(root + '/closure.json')!.get_filetype() != .regular
			|| os.file_size(root + '/closure.json') > 4 * 1024 * 1024 {
			return error('bounded regular V closure receipt required')
		}
		audit := json2.decode[Audit](os.read_file(root + '/closure.json')!)!
		schema(audit)!
		mut expected_inputs := []string{}
		for kind in source_kinds {
			list := root + '/' + kind + '-v-files.txt'
			if os.lstat(list)!.get_filetype() != .regular || os.file_size(list) > 256 * 1024 {
				return error('bounded regular V source list required')
			}
			paths := os.read_lines(list)!
			if paths.len == 0 || paths.len > 2048 { return error('source closure count limit') }
			expected_inputs << paths
		}
		if audit.inputs.len != expected_inputs.len { return error('incomplete selected V closure') }
		for index, path in expected_inputs {
			if audit.inputs[index].path != path { return error('selected V closure order/path differs') }
		}
		for input in audit.inputs {
			if browsertransfer.file_hash(input.path)! != input.sha256 || browsertransfer.file_hash(root + '/' + input.frozen)! != input.sha256 {
				return error('V closure changed: ' + input.path)
			}
		}
		for path, sha in audit.tools { if browsertransfer.file_hash(path)! != sha { return error('compiler changed: ' + path) } }
		println('BROWSER-TCP CLOSURE PASS selected-inputs=' + audit.inputs.len.str())
	}
}

fn main() { run() or { eprintln(err.msg()); exit(1) } }
