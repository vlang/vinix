// SPDX-License-Identifier: GPL-2.0-or-later
// Independently exercise layout admission without claiming a Wine native pass.
module main

import crypto.sha256
import json2
import os
import tools.packages.wineadapter

struct LayoutReport {
	scope string
	baseline string
	refused string
	inputs_sha256 string
}

fn content_digest(text string) string {
	bytes := text.bytes()
	mut hash := sha256.new()
	mut sum := []u8{len: sha256.size}
	defer { unsafe { bytes.free(); sum.free(); hash.free(); free(hash) } }
	hash.write(bytes) or { panic(err) }
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn digest(path string) !string {
	bytes := os.read_file(path)!
	defer { unsafe { bytes.free() } }
	return content_digest(bytes)
}

fn source(root string, name string, embedded string) ! {
	defer { unsafe { embedded.free() } }
	path := root + '/' + name
	defer { unsafe { path.free() } }
	actual := digest(path)!
	expected := content_digest(embedded)
	defer { unsafe { actual.free(); expected.free() } }
	if actual != expected { return error('compiled Wine layout control source differs: ' + name) }
}

fn check() ! {
	$if prod {} $else { return error('compile Wine layout controls with -prod') }
	if os.args.len != 4 { return error('usage: wine-layout-check RUNTIME PRODUCER_INPUTS NEW_OUTPUT') }
	directory := os.dir(@FILE)
	tests := os.dir(directory)
	root := os.dir(tests)
	defer { unsafe { directory.free(); tests.free(); root.free() } }
	source(root, 'tests/packages/wine-layout-check.v', $embed_file('wine-layout-check.v').to_string())!
	source(root, 'tools/packages/wineadapter/layout.v', $embed_file('../../tools/packages/wineadapter/layout.v').to_string())!
	source(root, 'tools/packages/wineadapter/patch.v', $embed_file('../../tools/packages/wineadapter/patch.v').to_string())!
	runtime := os.real_path(os.args[1])
	defer { unsafe { runtime.free() } }
	st := os.lstat(os.args[2])!
	if st.get_filetype() != .regular || st.size < 1 || st.size > 16 * 1024 * 1024 {
		return error('Wine layout producer input inventory must be a bounded ordinary file')
	}
	input_text := os.read_file(os.args[2])!
	defer { unsafe { input_text.free() } }
	inputs := json2.decode[map[string]string](input_text)!
	defer {
		for key, value in inputs { unsafe { key.free(); value.free() } }
		unsafe { inputs.free() }
	}
	out := os.abs_path(os.args[3])
	defer { unsafe { out.free() } }
	if os.exists(out) { return error('Wine layout proof directory exists') }
	wineadapter.admit_private_layout(runtime, inputs)!
	os.mkdir_all(out)!
	copy_path := out + '/runtime'
	defer { unsafe { copy_path.free() } }
	os.cp_all(runtime, copy_path, false)!
	wineadapter.admit_private_layout(copy_path, inputs)!
	mut refused := []string{cap: 10}
	defer { unsafe { (&array(&refused)).free() } }
	for suffix in ['/bin/wine64', '/bin/wineserver', '/root/usr/bin/wine',
		'/root/usr/bin/wine64', '/root/usr/bin/wineserver',
		'/root/lib/ld-musl-x86_64.so.1', '/root/usr/bin/vinix-wine-musl',
		'/root/usr/libexec/vinix-wine/wine', '/root/usr/libexec/vinix-wine/wineserver',
		'/root/usr/lib/wine/x86_64-unix/ntdll.so']! {
		path := copy_path + suffix
		original := runtime + suffix
		defer { unsafe { path.free(); original.free() } }
		os.rm(path)!
		os.write_file(path, 'changed private executable\n')!
		mut rejected := false
		wineadapter.admit_private_layout(copy_path, inputs) or { rejected = true; unsafe { err.free() } }
		if !rejected { return error('changed private executable was admitted: ' + suffix) }
		os.rm(path)!
		os.cp(original, path)!
		wineadapter.admit_private_layout(copy_path, inputs)!
		refused << suffix
	}
	// A loader symlink would canonicalize /proc/self/exe back into root/lib.
	loader := copy_path + '/root/usr/bin/vinix-wine-musl'
	defer { unsafe { loader.free() } }
	os.rm(loader)!
	os.symlink('../../lib/ld-musl-x86_64.so.1', loader)!
	mut rejected := false
	wineadapter.admit_private_layout(copy_path, inputs) or { rejected = true; unsafe { err.free() } }
	if !rejected { return error('symlinked private loader was admitted') }
	joined := refused.join(',')
	refusals := joined + ',symlinked-loader'
	input_digest := content_digest(input_text)
	defer { unsafe { joined.free(); refusals.free(); input_digest.free() } }
	report := json2.encode(LayoutReport{
		scope: 'private executable layout and source binding only; no native Wine execution claim'
		baseline: 'original and copied layout admitted'
		refused: refusals
		inputs_sha256: input_digest
	})
	text := report + '\n'
	report_path := out + '/controls.json'
	defer { unsafe { report.free(); text.free(); report_path.free() } }
	os.write_file(report_path, text)!
	println('WINE LAYOUT PASS: original/copied baselines and 11 private-executable refusals')
}

fn main() { check() or { eprintln(err); exit(1) } }
