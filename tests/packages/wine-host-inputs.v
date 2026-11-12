// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve selected host-tool bytes; original qualification paths remain required.
module main

import json2
import os
import tests.packages.winesource

struct HostInput {
	original string
	resolved string
	sha256 string
	mode u32
	stored string
}

fn run() ! {
	if os.args.len != 3 { return error('usage: wine-host-inputs NATIVE_RUN FRESH_OUTPUT') }
	run := os.real_path(os.args[1])
	out := os.abs_path(os.args[2])
	if os.exists(out) || os.is_link(out) { return error('output must be fresh') }
	index := run + '/inputs-verified.json'
	declaration := run + '/declaration.json'
	index_hash := winesource.file_digest(index)!
	declaration_hash := winesource.file_digest(declaration)!
	inputs := json2.decode[map[string]string](os.read_file(index)!)!
	decl := json2.decode[map[string]string](os.read_file(declaration)!)!
	producer_index := decl['prepared'] + '/inputs-verified.json'
	producer_hash := winesource.file_digest(producer_index)!
	producer_inputs := json2.decode[map[string]string](os.read_file(producer_index)!)!
	mut paths := ['/opt/homebrew/opt/llvm/bin/clang', '/opt/homebrew/opt/llvm/bin/llvm-readelf',
		'/opt/homebrew/bin/ld.lld', '/usr/bin/tar']
	for key in ['qemu', 'firmware', 'firmware_vars', 'arm_loader', 'iso_bootx64',
		'iso_limine_cd', 'iso_xorriso']! {
		path := decl[key] or { return error('missing boot tool declaration: ' + key) }
		if path != '' { paths << path }
	}
	mut captured := []HostInput{}
	for path in paths {
		expected := inputs[path] or {
			producer_inputs[path] or { return error('selected host input was not inventoried: ' + path) }
		}
		if path in producer_inputs && producer_inputs[path] != expected {
			return error('native/producer host input disagreement: ' + path)
		}
		if !os.is_abs_path(path) || expected.len != 64 || !os.is_file(path)
			|| winesource.file_digest(path)! != expected { return error('selected host input changed: ' + path) }
		captured << HostInput{original: path, resolved: os.real_path(path), sha256: expected,
			mode: u32(os.stat(path)!.mode) & 0o7777, stored: 'blobs/' + expected}
	}
	os.mkdir_all(out + '/blobs')!
	for input in captured {
		target := out + '/' + input.stored
		if !os.exists(target) { os.cp(input.resolved, target)! }
		if winesource.file_digest(target)! != input.sha256
			|| winesource.file_digest(input.original)! != input.sha256
			|| os.real_path(input.original) != input.resolved
			|| u32(os.stat(input.original)!.mode) & 0o7777 != input.mode {
			return error('selected host input changed while preserving: ' + input.original)
		}
	}
	if winesource.file_digest(index)! != index_hash || winesource.file_digest(declaration)! != declaration_hash
		|| winesource.file_digest(producer_index)! != producer_hash {
		return error('native input declarations changed while preserving')
	}
	os.cp(index, out + '/original-inputs.json')!
	os.cp(declaration, out + '/original-declaration.json')!
	os.cp(producer_index, out + '/original-producer-inputs.json')!
	os.write_file(out + '/host-inputs.json', json2.encode(captured) + '\n')!
	println('WINE HOST INPUTS PRESERVED ' + captured.len.str() + ': bytes only; no new admission or dependency-closure claim')
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
