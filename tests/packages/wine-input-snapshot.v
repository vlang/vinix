// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve selected input bytes; this does not relocate historical auditors.
module main

import json2
import os
import tests.packages.wineoverlay

struct TypedInput { kind string target string sha256 string }
struct Copy { path string sha256 string method string }
fn run() ! {
	if os.args.len != 4 { return error('usage: SNAPSHOT FLAT_INPUTS PE_TYPED_INPUTS FRESH_OUTPUT') }
	output := os.abs_path(os.args[3])
	if os.exists(output) || os.is_link(output) { return error('fresh snapshot directory required') }
	mut inputs := json2.decode[map[string]string](os.read_file(os.args[1])!)!
	typed := json2.decode[map[string]TypedInput](os.read_file(os.args[2])!)!
	for path, entry in typed {
		if entry.kind == 'file' {
			if path in inputs && inputs[path] != entry.sha256 { return error('input inventories disagree') }
			inputs[path] = entry.sha256
		} else if entry.kind == 'symlink' {
			if !os.is_link(path) || os.readlink(path)! != entry.target { return error('selected input link differs') }
		} else if entry.kind == 'directory' {
			if !os.is_dir(path) || os.is_link(path) { return error('selected input directory differs') }
		} else { return error('unsupported selected input type') }
	}
	if inputs.len == 0 || inputs.len > 100000 { return error('selected input count outside bound') }
	os.mkdir_all(output + '/files')!
	mut paths := inputs.keys(); paths.sort()
	mut copies := map[string]Copy{}
	for index, path in paths {
		if path.contains('\x00') || !os.is_abs_path(path) || path == output || path.starts_with(output + '/') { return error('invalid snapshot input path') }
		if wineoverlay.digest(path)! != inputs[path] { return error('selected input differs before snapshot: ' + path) }
		selected := output + '/files/' + index.str()
		// Resolve only the payload source: original typed link descriptors are
		// preserved separately, and no original path or link is rewritten.
		mut method := 'clone'
		wineoverlay.clone_fresh(os.real_path(path), selected) or {
			if os.exists(selected) || os.is_link(selected) { return error('failed clone left a snapshot target') }
			os.cp(os.real_path(path), selected)!
			method = 'copy'
		}
		if wineoverlay.digest(selected)! != inputs[path] { return error('snapshot copy differs') }
		copies[path] = Copy{path: selected, sha256: inputs[path], method: method}
	}
	for path, hash in inputs { if wineoverlay.digest(path)! != hash { return error('selected input changed during snapshot: ' + path) } }
	for path, entry in typed { if entry.kind == 'symlink' && os.readlink(path)! != entry.target { return error('input link changed during snapshot') } }
	os.write_file(output + '/copies.json', json2.encode(copies))!
	os.write_file(output + '/typed-inputs.json', json2.encode(typed))!
	os.write_file(output + '/scope.txt', 'Complete selected file bytes and typed PE link/directory records. Original namespaces and complete original bundles remain required by historical auditors; no relocation or build qualification waiver.\n')!
	println('WINE INPUT SNAPSHOT PASS selected bytes preserved; original namespaces unchanged')
}
fn main() { run() or { eprintln(err); exit(1) } }
